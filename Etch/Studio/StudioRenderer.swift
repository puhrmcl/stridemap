import SwiftUI
import UIKit
import CoreImage

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
        var dataPlacement: StudioDataPlacement = .right
        var photoLayout: StudioPhotoLayout = .single
        var titleOverride: String? = nil
        var dateOverride: String? = nil
        var showEditorialPhoto: Bool = false
        var showMemoryRoute: Bool = false
        var heroMetric: StatMetric = .distance
        var statSlots: [StatMetric] = [.time, .pace, .elevationGain]
        /// Whether the small caption labels under data values (and the headline's unit) are drawn.
        var showStatLabels: Bool = true
        var showElevationProfile: Bool = false
        /// Draw the recorded pace band (only meaningful when the run carries a pace series).
        var showPaceProfile: Bool = false
        var galleryShowMapTile: Bool = false
        var galleryCellsRaw: [String] = []
        /// Gallery: which photo fills each cell (parallel to `galleryCellsRaw`; -1 = automatic).
        var galleryPhotoPicks: [Int] = []
        var includeWeather: Bool = false
        var routeColor: Color? = nil
        var textColor: Color? = nil
        var groundColor: Color? = nil
        /// The share/export canvas — `poster` (native) or a social aspect the poster is matted onto.
        var outputSize: StudioOutputSize = .poster

        // MARK: Remodel options
        /// Render the whole piece in black & white (images desaturated, vector colours toned to grey).
        var monochrome: Bool = false
        /// The curated Title typeface.
        var titleFont: PosterFont = .editorial
        /// Whether the title line is drawn.
        var showTitle: Bool = true
        /// Whether the location line is drawn.
        var showLocation: Bool = true
        /// Whether the date line is drawn.
        var showDate: Bool = true
        /// Location override; nil falls back to the run's city/state.
        var locationOverride: String? = nil
        /// Gallery product: which of the five curated art layouts to compose.
        var galleryDesignRaw: String = GalleryDesign.portfolio.rawValue
        /// Map product: how the area beneath the map is composed (statement / minimal / photo).
        var mapLayoutRaw: String = MapLayout.statement.rawValue
        /// Map Photo layout: how many photos to show (1–3).
        var mapPhotoCount: Int = 1
        /// Multiplies every text point size on the poster (user-adjustable). 1 = designed size.
        var textScale: CGFloat = 1
        /// Per-element size multipliers layered on `textScale`.
        var titleScale: CGFloat = 1
        var locationScale: CGFloat = 1
        var dateScale: CGFloat = 1
        var heroScale: CGFloat = 1
        var statScale: CGFloat = 1
        /// The print shape the artwork is composed into (2:3 primary, 4:5 secondary).
        var printAspect: PrintAspect = .twoThree
    }

    /// The largest print size this device can render at an acceptable DPI. Anything bigger has to
    /// be rendered server-side — the on-device ceiling is a memory limit, not a choice.
    static func canRenderOnDevice(_ geometry: PrintGeometry) -> Bool {
        geometry.isAcceptable(longEdgePixels: maxLongEdgePixels)
    }

    /// Largest long edge (px) rendered on-device, to stay within memory limits (~18–20″ at
    /// 300 DPI). Bigger sizes are rendered server-side once Studio Web / the print backend land.
    static let maxLongEdgePixels = PrintGeometry.deviceRenderLongEdge

    /// The map / contour art panel image. Nil for photo and paper editions.
    static func panelImage(for request: Request, panelPixelWidth: CGFloat) async -> UIImage? {
        // Full Bleed runs the map across the entire sheet, so its panel is snapshotted at the
        // canvas shape rather than the square art panel — no stretch, no crop surprise.
        let panelSize = request.mapLayoutRaw == MapLayout.fullBleed.rawValue && request.layout == .classic
            ? StudioComposition.canvasSize(request.orientation, request.dataPlacement, request.printAspect)
            : StudioComposition.artSize(request.orientation, request.dataPlacement)
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

    /// Loads the composition's photos at a resolution matched to how many cells share the panel —
    /// plus each photo's saliency focus point, so gallery cells crop toward the subject. Empty for
    /// non-photo editions. `panelPixelWidth` is the full panel width; grid cells need only a
    /// fraction of it, keeping memory in check.
    ///
    /// The third element is the Gallery's *compact* per-cell photo plan: the tile plan can pick
    /// any of the run's photos per cell (no cap), so only the photos actually used are loaded and
    /// the stored absolute indices are rewritten to positions in the loaded pool. Empty for
    /// non-gallery layouts.
    static func photoImages(for request: Request,
                            panelPixelWidth: CGFloat) async -> ([UIImage], [CGPoint], [Int]) {
        if request.layout == .gallery {
            return await galleryPhotoImages(for: request, panelPixelWidth: panelPixelWidth)
        }
        // Memory fills the panel (single or grid); the Editorial layout may show one cover photo
        // beside the text.
        let ids: [String]
        if request.edition.isPhoto {
            ids = Array(request.run.photoReferences.prefix(request.photoLayout.maxPhotos))
        } else if request.layout == .keepsake {
            ids = Array(request.run.photoReferences.prefix(1))
        } else if request.mapLayoutRaw == MapLayout.photo.rawValue {
            // Map Photo layout: a strip of up to 3 photos fills the data area.
            ids = Array(request.run.photoReferences.prefix(max(1, min(3, request.mapPhotoCount))))
        } else if request.showEditorialPhoto {
            ids = Array(request.run.photoReferences.prefix(1))
        } else {
            ids = []
        }
        guard !ids.isEmpty else { return ([], [], []) }
        // In a grid the cell is at most half the panel; a single fills it.
        let cellWidth = ids.count > 1 ? panelPixelWidth / 2 : panelPixelWidth
        let target = max(cellWidth, 1200)
        var images: [UIImage] = []
        var focuses: [CGPoint] = []
        for id in ids {
            if let image = await PhotoLibrary.image(for: id, targetSize: CGSize(width: target, height: target)) {
                images.append(image)
                focuses.append(await PhotoFocus.focusPoint(id: id, image: image))
            }
        }
        return (images, focuses, [])
    }

    /// Gallery: resolve the tile plan to the *absolute* photo indices it uses (explicit picks
    /// win; automatic cells take photo order), load exactly those, and rewrite the plan to
    /// positions in the loaded pool. A pick whose photo fails to load maps past the pool, which
    /// the composition renders as the awaiting-photo placeholder.
    private static func galleryPhotoImages(for request: Request,
                                           panelPixelWidth: CGFloat) async -> ([UIImage], [CGPoint], [Int]) {
        var autoIndex = 0
        var neededAbsolute: [Int] = []
        var cellAbsolute: [Int] = []   // per cell: absolute photo index, or -1 for non-photo cells
        for (cell, raw) in request.galleryCellsRaw.enumerated() {
            guard GalleryTileKind(rawValue: raw) == .photo else {
                cellAbsolute.append(-1)
                continue
            }
            let pick = cell < request.galleryPhotoPicks.count && request.galleryPhotoPicks[cell] >= 0
                ? request.galleryPhotoPicks[cell] : autoIndex
            autoIndex += 1
            cellAbsolute.append(pick)
            if !neededAbsolute.contains(pick) { neededAbsolute.append(pick) }
        }
        let refs = request.run.photoReferences
        let cellWidth = neededAbsolute.count > 1 ? panelPixelWidth / 2 : panelPixelWidth
        let target = max(cellWidth, 1200)
        var images: [UIImage] = []
        var focuses: [CGPoint] = []
        var positionByAbsolute: [Int: Int] = [:]
        for absolute in neededAbsolute where refs.indices.contains(absolute) {
            let id = refs[absolute]
            if let image = await PhotoLibrary.image(for: id, targetSize: CGSize(width: target, height: target)) {
                positionByAbsolute[absolute] = images.count
                images.append(image)
                focuses.append(await PhotoFocus.focusPoint(id: id, image: image))
            }
        }
        let compact = cellAbsolute.map { $0 >= 0 ? (positionByAbsolute[$0] ?? Int.max) : -1 }
        return (images, focuses, compact)
    }

    /// Renders the composition at the given `ImageRenderer` scale.
    static func image(for request: Request, scale: CGFloat) async -> UIImage? {
        let pixelWidth = StudioComposition.width * scale
        async let panelTask = panelImage(for: request, panelPixelWidth: pixelWidth)
        async let photosTask = photoImages(for: request, panelPixelWidth: pixelWidth)
        async let profileTask = elevationProfile(for: request)
        let (panelRaw, photoPack, profile) = await (panelTask, photosTask, profileTask)
        var panel = panelRaw
        var photos = photoPack.0
        let focuses = photoPack.1
        let picks = photoPack.2
        // Black & white: desaturate the raster panels here (ImageRenderer can't apply a colour
        // filter to a live map/photo), and let the composition tone its vector colours to grey.
        if request.monochrome {
            panel = panel.map { $0.desaturated() }
            photos = photos.map { $0.desaturated() }
        }
        let plan = fitPlan(for: request, photos: photos, picks: picks, profile: profile)
        let composition = composition(for: request, panel: panel, photos: photos, focuses: focuses,
                                      picks: picks, profile: profile, fitScale: plan.scale,
                                      measuring: false, artHeight: plan.artHeight)
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        guard let base = renderer.uiImage else { return nil }
        guard let aspect = request.outputSize.aspect else { return base }
        return matted(base, aspect: aspect, ground: request.groundColor ?? request.edition.ground)
    }

    /// Builds the composition view for a request — the one construction site, shared by the real
    /// render and the measurement pass so the two can never drift apart.
    private static func composition(for request: Request, panel: UIImage?, photos: [UIImage],
                                    focuses: [CGPoint] = [], picks: [Int] = [], profile: [Double],
                                    fitScale: CGFloat, measuring: Bool,
                                    artHeight: CGFloat? = nil) -> StudioComposition {
        StudioComposition(
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
            showStatLabels: request.showStatLabels,
            elevationSamples: profile,
            showElevationProfile: request.showElevationProfile,
            paceSamples: request.showPaceProfile ? request.run.paceSeries : [],
            showPaceProfile: request.showPaceProfile,
            galleryShowMapTile: request.galleryShowMapTile,
            galleryCellsRaw: request.galleryCellsRaw,
            routeOverride: request.routeColor, textOverride: request.textColor,
            groundOverride: request.groundColor,
            monochrome: request.monochrome,
            titleFont: request.titleFont,
            showTitle: request.showTitle,
            showLocation: request.showLocation,
            showDate: request.showDate,
            locationOverride: request.locationOverride,
            galleryDesignRaw: request.galleryDesignRaw,
            mapLayoutRaw: request.mapLayoutRaw,
            mapPhotoCount: request.mapPhotoCount,
            textScale: request.textScale,
            titleScale: request.titleScale,
            locationScale: request.locationScale,
            dateScale: request.dateScale,
            heroScale: request.heroScale,
            statScale: request.statScale,
            fitScale: fitScale,
            measuring: measuring,
            galleryPhotoPicks: picks,
            photoFocusPoints: focuses,
            artHeightOverride: artHeight,
            printAspect: request.printAspect
        )
    }

    /// The auto-fit pass: measures the fixed content's natural height (type, bands, footer) and
    /// returns both a uniform shrink factor (applied when the content would push the art below
    /// its design floor or off the sheet) and the art panel's *exact* height — canvas minus the
    /// measured fixed content — so the composition sizes the art explicitly instead of trusting
    /// the stack negotiation, which could hand the art more than its share and clip the bottom
    /// data rows off the sheet.
    ///
    /// Measured with `ImageRenderer` — the same engine that draws the real render — on a probe of
    /// the same composition with the flexible art collapsed to its floor, so the numbers are
    /// exact by construction. The shrink converges in a pass or two since type dominates the
    /// fixed height; floored at 0.5 — a sheet that still overflows at half size is not a layout
    /// problem the renderer should paper over.
    private static func fitPlan(for request: Request, photos: [UIImage], picks: [Int] = [],
                                profile: [Double]) -> (scale: CGFloat, artHeight: CGFloat?) {
        // Overlay compositions (full-bleed map, keepsake) set type *over* the art between
        // spacers — they always fit.
        let isFullBleed = request.layout == .classic
            && request.mapLayoutRaw == MapLayout.fullBleed.rawValue
        guard request.layout != .keepsake, !isFullBleed else { return (1, nil) }

        let canvas = StudioComposition.canvasSize(request.orientation, request.dataPlacement,
                                                  request.printAspect)
        let floor = StudioComposition.artFloor(request.orientation, request.dataPlacement,
                                               layout: request.layout, aspect: request.printAspect)
        let budget = canvas.height - floor
        guard budget > 0 else { return (1, nil) }

        // The probe renders at a light raster scale purely to read its laid-out height in points.
        func fixedHeight(at scale: CGFloat) -> CGFloat? {
            let probe = composition(for: request, panel: nil, photos: photos, picks: picks,
                                    profile: profile, fitScale: scale, measuring: true)
            let renderer = ImageRenderer(content: probe)
            renderer.scale = 0.5
            guard let image = renderer.uiImage else { return nil }
            return image.size.height - floor
        }

        guard var fixed = fixedHeight(at: 1) else { return (1, nil) }
        var scale: CGFloat = 1
        var passes = 0
        while fixed > budget + 1, scale > 0.5, passes < 3 {
            scale = max(0.5, scale * budget / fixed)
            guard let remeasured = fixedHeight(at: scale) else { break }
            fixed = remeasured
            passes += 1
        }

        // The side-column landscape has no flexing art — its square panel is the sheet height —
        // so only the shrink applies there.
        if request.orientation == .landscape && request.dataPlacement.isSide {
            return (scale, nil)
        }
        return (scale, max(1, canvas.height - fixed))
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

            // The social signature: the etch. wordmark, quiet in the bottom mat. Shared images
            // are the brand's only ad; prints and poster exports stay unbranded — the wall art
            // carries no logo, ever.
            let trait = UITraitCollection(userInterfaceStyle: isDark(mat) ? .dark : .light)
            if let logo = UIImage(named: "BrandLogo", in: nil, compatibleWith: trait) {
                let logoWidth = longEdge * 0.075
                let logoHeight = logoWidth * (logo.size.height / logo.size.width)
                let bandTop = origin.y + size.height
                let bandHeight = canvas.height - bandTop
                let logoRect = CGRect(
                    x: (canvas.width - logoWidth) / 2,
                    y: bandTop + (bandHeight - logoHeight) / 2,
                    width: logoWidth, height: logoHeight
                )
                logo.draw(in: logoRect, blendMode: .normal, alpha: 0.55)
            }
        }
    }

    /// Perceived-luminance check for picking the wordmark variant against the mat.
    private static func isDark(_ color: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
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
        let nominal = StudioComposition.canvasSize(request.orientation, request.dataPlacement,
                                                   request.printAspect)
        let compositionLongEdge = max(nominal.width, nominal.height)   // nominal points
        // Social exports don't need print DPI; ~2× the composition keeps files light to share.
        guard request.outputSize.aspect == nil else { return await image(for: request, scale: 2) }
        let target = min(longEdgePixels, maxLongEdgePixels)
        let scale = max(2, target / compositionLongEdge)
        return await image(for: request, scale: scale)
    }
}

extension UIImage {
    /// A black & white copy, for monochrome posters. Falls back to the original if the filter
    /// can't be built. Shared CIContext keeps repeated renders cheap.
    private static let monoContext = CIContext(options: nil)

    func desaturated() -> UIImage {
        guard let ciInput = CIImage(image: self),
              let filter = CIFilter(name: "CIPhotoEffectMono") else { return self }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              let cg = UIImage.monoContext.createCGImage(output, from: output.extent) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
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
