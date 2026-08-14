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
        var includeWeather: Bool = false
        var routeColor: Color? = nil
        var textColor: Color? = nil
    }

    /// Largest long edge (px) rendered on-device, to stay within memory limits (~18–20″ at
    /// 300 DPI). Bigger sizes are rendered server-side once Studio Web / the print backend land.
    static let maxLongEdgePixels: CGFloat = 6000

    /// The art panel image (muted map snapshot, or the run's photo for Memory). `panelPixelWidth`
    /// sizes the photo request so a print render pulls a higher-resolution photo.
    static func panelImage(for request: Request, panelPixelWidth: CGFloat) async -> UIImage? {
        if request.edition.isPhoto {
            guard let id = request.run.photoReferences.first else { return nil }
            let target = max(panelPixelWidth, 1200)
            return await PhotoLibrary.image(for: id, targetSize: CGSize(width: target, height: target))
        }
        if request.edition.mapKind != nil {
            let panelSize = CGSize(width: StudioComposition.width, height: StudioComposition.artHeight)
            return await PosterMap.studioPanel(for: request.run, size: panelSize,
                                               edition: request.edition, route: request.routeColor)
        }
        return nil
    }

    /// Renders the composition at the given `ImageRenderer` scale.
    static func image(for request: Request, scale: CGFloat) async -> UIImage? {
        let panel = await panelImage(for: request, panelPixelWidth: StudioComposition.width * scale)
        let composition = StudioComposition(
            run: request.run, edition: request.edition, panelImage: panel,
            includeWeather: request.includeWeather, layout: request.layout,
            routeOverride: request.routeColor, textOverride: request.textColor
        )
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        return renderer.uiImage
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
