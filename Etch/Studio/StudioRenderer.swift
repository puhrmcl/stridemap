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
        var photoLayout: StudioPhotoLayout = .single
        var statSlots: [StatMetric] = [.time, .pace, .elevationGain]
        var showElevationProfile: Bool = false
        var includeWeather: Bool = false
        var routeColor: Color? = nil
        var textColor: Color? = nil
        var groundColor: Color? = nil
    }

    /// Largest long edge (px) rendered on-device, to stay within memory limits (~18–20″ at
    /// 300 DPI). Bigger sizes are rendered server-side once Studio Web / the print backend land.
    static let maxLongEdgePixels: CGFloat = 6000

    /// The map / contour art panel image. Nil for photo and paper editions.
    static func panelImage(for request: Request, panelPixelWidth: CGFloat) async -> UIImage? {
        let panelSize = CGSize(width: StudioComposition.width, height: StudioComposition.artHeight)
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
        guard request.edition.isPhoto else { return [] }
        let ids = Array(request.run.photoReferences.prefix(request.photoLayout.maxPhotos))
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
            photoLayout: request.photoLayout,
            statSlots: request.statSlots,
            elevationSamples: profile,
            showElevationProfile: request.showElevationProfile,
            routeOverride: request.routeColor, textOverride: request.textColor,
            groundOverride: request.groundColor
        )
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// The route's terrain elevation profile, fetched only when the strip is enabled.
    static func elevationProfile(for request: Request) async -> [Double] {
        guard request.showElevationProfile else { return [] }
        return await ElevationService.routeProfile(for: request.run.coordinates) ?? []
    }

    /// A print-resolution image whose long edge is ~`longEdgePixels` (capped for on-device
    /// memory). 5400 px ≈ 18″ at 300 DPI — a genuine gallery-grade file.
    static func printImage(for request: Request, longEdgePixels: CGFloat = 5400) async -> UIImage? {
        let compositionLongEdge = StudioComposition.size.height   // nominal points
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
