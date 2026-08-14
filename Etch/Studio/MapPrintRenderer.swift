import SwiftUI
import MapKit

/// Renders an aggregate map print: snapshots the framed region on a muted base map, draws the
/// kind's content over it (every route / the state choropleth / city or landmark pins), and wraps
/// it in `MapPrintComposition`. Mirrors `StudioRenderer` so preview, high-res, and print share one
/// path.
@MainActor
enum MapPrintRenderer {

    static let maxLongEdgePixels: CGFloat = 6000

    /// Preview / working image at the given `ImageRenderer` scale.
    static func image(for request: MapPrintRequest, scale: CGFloat) async -> UIImage? {
        let panelSize = CGSize(width: MapPrintComposition.width, height: MapPrintComposition.artHeight)
        let visited = request.kind == .states ? await visitedStateIntensities(request.runs) : [:]
        guard let panel = await panel(for: request, size: panelSize, visited: visited) else { return nil }

        let boundaries = USStateBoundaries.shared
        let visitedCount = visited.keys.filter { boundaries.isState($0) }.count
        let composition = MapPrintComposition(panelImage: panel, orientation: request.orientation,
                                              footer: request.footerData(visitedStateCount: visitedCount))
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// Print-resolution image (~18″ at 300 DPI), capped for on-device memory.
    static func printImage(for request: MapPrintRequest, longEdgePixels: CGFloat = 5400) async -> UIImage? {
        let nominal = MapPrintComposition.nominalSize(request.orientation)
        let target = min(longEdgePixels, maxLongEdgePixels)
        let scale = max(2, target / max(nominal.width, nominal.height))
        return await image(for: request, scale: scale)
    }

    // MARK: Panel

    private static func panel(for request: MapPrintRequest, size: CGSize,
                              visited: [String: Double]) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = request.region
        options.size = size
        options.scale = 2
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
            snapshotter.start(with: .main) { snap, _ in continuation.resume(returning: snap) }
        }
        guard let snapshot else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = options.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let route = UIColor(request.routeColor)
        let bone = UIColor(Theme.Palette.bone)

        return renderer.image { context in
            let cg = context.cgContext
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            bone.withAlphaComponent(0.16).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            switch request.kind {
            case .allRuns:
                drawRoutes(request.mapped, on: snapshot, route: route)
            case .states:
                drawStates(visited: visited, on: snapshot)
            case .cities:
                drawPins(RunStatistics(request.runs).travelPlaces.map(\.coordinate),
                         on: snapshot, fill: route)
            case .countries:
                drawPins(RunStatistics(request.runs).countryPlaces.map(\.coordinate),
                         on: snapshot, fill: route)
            case .landmarks:
                drawPins(RunStatistics(request.runs).landmarkPlaces.map(\.coordinate),
                         on: snapshot, fill: UIColor(Theme.Palette.brass))
            }
        }
    }

    private static func drawRoutes(_ runs: [Run], on snapshot: MKMapSnapshotter.Snapshot, route: UIColor) {
        for run in runs {
            let coordinates = run.coordinates
            guard coordinates.count > 1 else { continue }
            let path = UIBezierPath()
            var started = false
            for coordinate in coordinates {
                let point = snapshot.point(for: coordinate)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            UIColor.white.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 5
            path.stroke()
            route.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()
        }
    }

    private static func drawStates(visited: [String: Double], on snapshot: MKMapSnapshotter.Snapshot) {
        let navy = UIColor(Theme.Palette.navy)
        let outline = UIColor(Theme.Palette.ink).withAlphaComponent(0.35)
        for boundary in USStateBoundaries.shared.boundaries {
            let intensity = visited[boundary.name]
            for polygon in boundary.polygons {
                let path = UIBezierPath()
                let pts = polygon.points()
                for i in 0..<polygon.pointCount {
                    let point = snapshot.point(for: pts[i].coordinate)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.close()
                if let intensity {
                    navy.withAlphaComponent(0.30 + 0.5 * CGFloat(intensity)).setFill()
                    path.fill()
                    navy.withAlphaComponent(0.9).setStroke()
                    path.lineWidth = 1.2
                } else {
                    outline.setStroke()
                    path.lineWidth = 0.7
                }
                path.stroke()
            }
        }
    }

    private static func drawPins(_ coordinates: [CLLocationCoordinate2D],
                                 on snapshot: MKMapSnapshotter.Snapshot, fill: UIColor) {
        for coordinate in coordinates {
            let point = snapshot.point(for: coordinate)
            let radius: CGFloat = 9
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            UIColor.white.setStroke()
            fill.setFill()
            let dot = UIBezierPath(ovalIn: rect)
            dot.fill()
            dot.lineWidth = 3
            dot.stroke()
        }
    }

    // MARK: State intensities

    /// Visited-state fill intensities (0…1), by boundary name — the same normalization the Home
    /// choropleth uses. Runs are matched to states by their start coordinate.
    private static func visitedStateIntensities(_ runs: [Run]) async -> [String: Double] {
        let coordinates = runs.compactMap(\.startCoordinate)
        let counts = await Task.detached(priority: .userInitiated) { () -> [String: Int] in
            let boundaries = USStateBoundaries.shared
            var counts: [String: Int] = [:]
            for coordinate in coordinates {
                if let name = boundaries.region(containing: coordinate) {
                    counts[name, default: 0] += 1
                }
            }
            return counts
        }.value
        let maxCount = counts.values.max() ?? 1
        return counts.mapValues { min(1, (Double($0) / Double(maxCount)).squareRoot()) }
    }
}

/// Renders a print-resolution aggregate map print and hands it to the share sheet — the working
/// high-res download, and the render that will feed the Prodigi print order once wired.
struct MapPrintExportSheet: View {
    let request: MapPrintRequest
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
        guard let rendered = await MapPrintRenderer.printImage(for: request) else { return }
        image = rendered
        if let data = rendered.pngData() {
            let name = "Etch-\(request.kind.rawValue)-map.png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? data.write(to: url)
            fileURL = url
        }
    }
}
