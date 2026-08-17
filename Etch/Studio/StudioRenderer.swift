import SwiftUI

/// Renders an Etch Studio artwork to an image — at preview scale for the gallery, or at print
/// resolution for a high-res download / print order. One path so the preview and the print are
/// the same composition, never an upscaled thumbnail.
///
/// The composition is authored at a fixed point size; rendering at a higher `ImageRenderer`
/// scale keeps the type and the route vector-crisp while the map/photo panel upsamples — which
/// is acceptable because the panel is a muted background, not the subject.
@MainActor
enum StudioRenderer {

    /// Everything needed to render one artwork: the run, the chosen edition + layout, and the
    /// user's options/overrides.
    struct Request {
        var run: Run
        var edition: StudioEdition
        var layout: StudioLayout = .classic
        var orientation: StudioOrientation = .portrait
        var dataPlacement: StudioDataPlacement = .side
        var photoLayout: StudioPhotoLayout = .single
        var titleOverride: String? = nil
        var dateOverride: String? = nil
        var showEditorialPhoto: Bool = false
        var showMemoryRoute: Bool = false
        var heroMetric: StatMetric = .distance
        var statSlots: [StatMetric] = [.time, .pace, .elevationGain]
        var showElevationProfile: Bool = false
        var galleryShowMapTile: Bool = false
        var galleryCellsRaw: [String] = []
        var includeWeather: Bool = false
        var routeColor: Color? = nil
        var textColor: Color? = nil
        var groundColor: Color? = nil
        /// The share/export canvas — `poster` (native) or a social aspect the poster is matted onto.
        var outputSize: StudioOutputSize = .poster
    }

    /// Largest long edge (px) rendered on-device, to stay within memory limits (~18–20″ at
    /// 300 DPI). Bigger sizes are rendered server-side once Studio Web / the print backend land.
    static let maxLongEdgePixels: CGFloat = 6000

    /// The map / contour art panel image. Nil for photo and paper editions.
    static func panelImage(for request: Request, panelPixelWidth: CGFloat) async -> UIImage? {
        let panelSize = StudioComposition.artSize(request.orientation, request.dataPlacement)
        if request.edition.isContour {
            let ground = request.groundColor ?? request.edition.ground
            return await PosterMap.topographicPanel(for: request.run, size: panelSize,
                                                    edition: request.edition, ground: ground,
                                                    route: request.routeColor)
        }
        guard request.edition.mapKind != nil else { return nil }
        return await PosterMap.studioPanel(for: request.run, size: panelSize,
                                           edition: request.edition, route: request.routeColor)
    }

    /// Loads the Memory edition's photos, cover-first, at a resolution matched to how many cells
    /// share the panel. Empty for non-photo editions. `panelPixelWidth` is the full panel width;
    /// grid cells need only a fraction of it, keeping memory in check.
    static func photoImages(for request: Request, panelPixelWidth: CGFloat) async -> [UIImage] {
        // Memory fills the panel (single or grid); the Editorial layout may show one cover photo
        // beside the text.
        let ids: [String]
        if request.edition.isPhoto {
            ids = Array(request.run.photoReferences.prefix(request.photoLayout.maxPhotos))
        } else if request.layout == .gallery {
            ids = Array(request.run.photoReferences.prefix(4))
        } else if request.layout == .keepsake {
            ids = Array(request.run.photoReferences.prefix(1))
        } else if request.showEditorialPhoto {
            ids = Array(request.run.photoReferences.prefix(1))
        } else {
            ids = []
        }
        guard !ids.isEmpty else { return [] }
        // In a grid the cell is at most half the panel; a single fills it.
        let cellWidth = ids.count > 1 ? panelPixelWidth / 2 : panelPixelWidth
        let target = max(cellWidth, 1200)
        var images: [UIImage] = []
        for id in ids {
            if let image = await PhotoLibrary.image(for: id, targetSize: CGSize(width: target, height: target)) {
                images.append(image)
            }
        }
        return images
    }

    /// Renders the composition at the given `ImageRenderer` scale.
    static func image(for request: Request, scale: CGFloat) async -> UIImage? {
        let pixelWidth = StudioComposition.width * scale
        async let panelTask = panelImage(for: request, panelPixelWidth: pixelWidth)
        async let photosTask = photoImages(for: request, panelPixelWidth: pixelWidth)
        async let profileTask = elevationProfile(for: request)
        let (panel, photos, profile) = await (panelTask, photosTask, profileTask)
        let composition = StudioComposition(
            run: request.run, edition: request.edition, panelImage: panel,
            photoImages: photos,
            includeWeather: request.includeWeather, layout: request.layout,
            orientation: request.orientation,
            dataPlacement: request.dataPlacement,
            photoLayout: request.photoLayout,
            titleOverride: request.titleOverride,
            dateOverride: request.dateOverride,
            showEditorialPhoto: request.showEditorialPhoto,
            showMemoryRoute: request.showMemoryRoute,
            heroMetric: request.heroMetric,
            statSlots: request.statSlots,
            elevationSamples: profile,
            showElevationProfile: request.showElevationProfile,
            galleryShowMapTile: request.galleryShowMapTile,
            galleryCellsRaw: request.galleryCellsRaw,
            routeOverride: request.routeColor, textOverride: request.textColor,
            groundOverride: request.groundColor
        )
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        guard let base = renderer.uiImage else { return nil }
        guard let aspect = request.outputSize.aspect else { return base }
        return matted(base, aspect: aspect, ground: request.groundColor ?? request.edition.ground)
    }

    /// Frames the finished poster as a print on a mat, sized to the target social aspect. The mat is
    /// a tone that *contrasts* the poster's ground (not the same colour, which made the poster's edges
    /// vanish and read as badly-centred content), and the print sits as a rounded card with a soft
    /// drop shadow and hairline — a deliberate, gallery-like social frame. Uniform breathing room on
    /// all sides, sized from the poster's *actual* rendered dimensions, so it can never clip.
    private static func matted(_ image: UIImage, aspect: CGFloat, ground: Color) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let margin = longEdge * 0.10        // generous, uniform breathing room around the print

        var width = size.width + margin * 2
        var height = size.height + margin * 2
        if width / height < aspect { width = height * aspect } else { height = width / aspect }
        let canvas = CGSize(width: width, height: height)

        let mat = matBackground(for: ground)
        let corner = longEdge * 0.02

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            mat.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))

            let origin = CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
            let rect = CGRect(origin: origin, size: size)
            let card = UIBezierPath(roundedRect: rect, cornerRadius: corner)

            // Soft drop shadow so the print lifts off the mat.
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: longEdge * 0.012),
                         blur: longEdge * 0.03, color: UIColor.black.withAlphaComponent(0.30).cgColor)
            UIColor.black.setFill()
            card.fill()
            cg.restoreGState()

            // The poster, clipped to the rounded card.
            cg.saveGState()
            card.addClip()
            image.draw(in: rect)
            cg.restoreGState()

            // A whisper of a keyline crisps the edge.
            UIColor.black.withAlphaComponent(0.06).setStroke()
            card.lineWidth = max(1, longEdge * 0.0016)
            card.stroke()
        }
    }

    /// A mat tone derived from the poster's ground but shifted toward the opposite luminance, so the
    /// print reads as a distinct card rather than dissolving into the background.
    private static func matBackground(for ground: Color) -> UIColor {
        let base = UIColor(ground)
        let target: UIColor = ground.isDarkGround ? .white : .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let t: CGFloat = 0.14
        return UIColor(red: r + (tr - r) * t, green: g + (tg - g) * t, blue: b + (tb - b) * t, alpha: 1)
    }

    /// The route's terrain elevation profile, fetched when the strip is enabled or a chosen metric
    /// needs it (start elevation).
    static func elevationProfile(for request: Request) async -> [Double] {
        let needsProfile = request.showElevationProfile
            || request.heroMetric.needsElevationProfile
            || request.statSlots.contains(where: { $0.needsElevationProfile })
        guard needsProfile else { return [] }
        return await ElevationService.routeProfile(for: request.run.coordinates) ?? []
    }

    /// The export image. A `poster` renders at print resolution (~5400 px long edge ≈ 18″ @ 300 DPI);
    /// a social size renders at a lighter digital resolution (the matting happens inside `image`).
    static func printImage(for request: Request, longEdgePixels: CGFloat = 5400) async -> UIImage? {
        let nominal = StudioComposition.nominalSize(request.orientation, request.dataPlacement)
        let compositionLongEdge = max(nominal.width, nominal.height)   // nominal points
        // Social exports don't need print DPI; ~2× the composition keeps files light to share.
        guard request.outputSize.aspect == nil else { return await image(for: request, scale: 2) }
        let target = min(longEdgePixels, maxLongEdgePixels)
        let scale = max(2, target / compositionLongEdge)
        return await image(for: request, scale: scale)
    }
}

/// Renders a print-resolution artwork and hands it to the share sheet (Save to Photos, Files,
/// AirDrop…). The working "digital high-res download" — and the same render that will be
/// uploaded to the print backend once Prodigi is wired.
struct StudioExportSheet: View {
    let request: StudioRenderer.Request
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var fileURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                            .padding(20)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Rendering high-resolution…")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("High-Resolution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let fileURL {
                        ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task { await render() }
        }
    }

    private func render() async {
        guard image == nil else { return }
        guard let rendered = await StudioRenderer.printImage(for: request) else { return }
        image = rendered
        if let data = rendered.pngData() {
            let name = "Etch-\(request.run.id.uuidString.prefix(8))-\(request.edition.id.rawValue).png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: url)
            fileURL = url
        }
    }
}
