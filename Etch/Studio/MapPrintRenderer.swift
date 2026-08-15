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
        if request.kind.isArt { return artImage(for: request, scale: scale) }
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
        let nominal = request.posterNominalSize
        let target = min(longEdgePixels, maxLongEdgePixels)
        let scale = max(2, target / max(nominal.width, nominal.height))
        return await image(for: request, scale: scale)
    }

    // MARK: Wall Art — abstract, full-bleed, text-free

    /// Every route projected directly (no base map) onto a solid ground. The weight, opacity and
    /// treatment adapt to how much you've run, so it reads as art whether that's five runs or five
    /// hundred.
    private static func artImage(for request: MapPrintRequest, scale: CGFloat) -> UIImage? {
        let runs = request.mapped
        guard !runs.isEmpty else { return nil }
        let size = request.posterNominalSize
        let palette = request.artPalette

        let region = request.region
        let latMax = region.center.latitude + region.span.latitudeDelta / 2
        let latMin = region.center.latitude - region.span.latitudeDelta / 2
        let lonMin = region.center.longitude - region.span.longitudeDelta / 2
        let lonMax = region.center.longitude + region.span.longitudeDelta / 2
        let lonScale = max(cos(((latMin + latMax) / 2) * .pi / 180), 0.01)
        let dataW = max((lonMax - lonMin) * lonScale, 1e-6)
        let dataH = max(latMax - latMin, 1e-6)
        let fit = min(size.width / dataW, size.height / dataH) * 0.82   // generous gallery margin
        let offX = (size.width - dataW * fit) / 2
        let offY = (size.height - dataH * fit) / 2

        func point(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(x: offX + (c.longitude - lonMin) * lonScale * fit,
                    y: offY + (latMax - c.latitude) * fit)
        }

        // Adapt weight/opacity to route count: few = bold & solid, many = fine & layered.
        let count = runs.count
        let unit = size.width / 1000
        let lineWidth: CGFloat = (count <= 12 ? 4.2 : count <= 80 ? 2.8 : 1.9) * unit
        let alpha: CGFloat = count <= 12 ? 0.95 : count <= 80 ? 0.78 : 0.55

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ground = UIColor(palette.ground)
        let line = UIColor(palette.line)

        func routePath(_ run: Run) -> UIBezierPath? {
            let coordinates = run.coordinates
            guard coordinates.count > 1 else { return nil }
            let path = UIBezierPath()
            var started = false
            for coordinate in coordinates {
                let p = point(coordinate)
                if started { path.addLine(to: p) } else { path.move(to: p); started = true }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            return path
        }

        return renderer.image { context in
            let cg = context.cgContext
            ground.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            switch request.artStyle {
            case .lines:
                line.withAlphaComponent(alpha).setStroke()
                for run in runs {
                    guard let path = routePath(run) else { continue }
                    path.lineWidth = lineWidth
                    path.stroke()
                }

            case .glow:
                // Additive light on dark grounds makes overlaps glow; on light grounds fall back
                // to a soft-shadowed line so it still reads.
                if palette.isDark { cg.setBlendMode(.plusLighter) }
                for run in runs {
                    guard let path = routePath(run) else { continue }
                    cg.saveGState()
                    cg.setShadow(offset: .zero, blur: lineWidth * 3, color: line.cgColor)
                    line.withAlphaComponent(alpha * 0.7).setStroke()
                    path.lineWidth = lineWidth
                    path.stroke()
                    cg.restoreGState()
                }
                cg.setBlendMode(.normal)

            case .points:
                // A constellation of where you've been — elegant for a few runs, a starfield for
                // many. Sized to the count.
                let radius: CGFloat = (count <= 12 ? 11 : count <= 80 ? 7 : 4.5) * unit
                for run in runs {
                    guard let first = run.coordinates.first else { continue }
                    let p = point(first)
                    let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
                    cg.saveGState()
                    if palette.isDark {
                        cg.setShadow(offset: .zero, blur: radius * 1.6, color: line.cgColor)
                    }
                    line.withAlphaComponent(alpha).setFill()
                    UIBezierPath(ovalIn: rect).fill()
                    cg.restoreGState()
                }

            case .clusters:
                // Group nearby runs into bubbles sized by how many runs are there — the home map's
                // cluster view, as art.
                let cell = size.width / 18
                var bins: [String: (sumX: CGFloat, sumY: CGFloat, count: Int)] = [:]
                for run in runs {
                    guard let first = run.coordinates.first else { continue }
                    let p = point(first)
                    let key = "\(Int((p.x / cell).rounded(.down)))_\(Int((p.y / cell).rounded(.down)))"
                    var bin = bins[key] ?? (0, 0, 0)
                    bin.sumX += p.x; bin.sumY += p.y; bin.count += 1
                    bins[key] = bin
                }
                let maxCount = CGFloat(bins.values.map(\.count).max() ?? 1)
                for bin in bins.values {
                    let c = CGPoint(x: bin.sumX / CGFloat(bin.count), y: bin.sumY / CGFloat(bin.count))
                    let t = sqrt(CGFloat(bin.count) / maxCount)
                    let radius = (7 + 26 * t) * unit
                    let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
                    cg.saveGState()
                    if palette.isDark { cg.setShadow(offset: .zero, blur: radius * 0.7, color: line.cgColor) }
                    line.withAlphaComponent(0.85).setFill()
                    UIBezierPath(ovalIn: rect).fill()
                    cg.restoreGState()
                    // A soft ring for a considered, cluster-marker feel.
                    line.withAlphaComponent(0.4).setStroke()
                    let ring = UIBezierPath(ovalIn: rect.insetBy(dx: -radius * 0.4, dy: -radius * 0.4))
                    ring.lineWidth = 1.5 * unit
                    ring.stroke()
                }
            }

            // Gallery finish: a subtle vignette for depth.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxDim = max(size.width, size.height)
            let colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.16).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: maxDim * 0.32,
                                      endCenter: center, endRadius: maxDim * 0.72,
                                      options: .drawsAfterEndLocation)
            }
        }
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
            case .artMap:
                break   // handled by artImage; never reaches here
            case .allRuns:
                if let name = request.boundaryStateName { drawStateBoundary(name, on: snapshot) }
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

            // A dot at the start keeps each run visible when the frame is zoomed out and the
            // route itself collapses to a point.
            if let first = coordinates.first {
                let point = snapshot.point(for: first)
                let radius: CGFloat = 5
                let dot = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                      width: radius * 2, height: radius * 2))
                UIColor.white.withAlphaComponent(0.85).setStroke()
                route.setFill()
                dot.fill()
                dot.lineWidth = 1.5
                dot.stroke()
            }
        }
    }

    /// Draws a US state's outline (single-state prints).
    private static func drawStateBoundary(_ name: String, on snapshot: MKMapSnapshotter.Snapshot) {
        guard let boundary = USStateBoundaries.shared.boundaries.first(where: { $0.name == name }) else { return }
        let fill = UIColor(Theme.Palette.blue).withAlphaComponent(0.08)
        let stroke = UIColor(Theme.Palette.blue).withAlphaComponent(0.7)
        for polygon in boundary.polygons {
            let path = UIBezierPath()
            let pts = polygon.points()
            for i in 0..<polygon.pointCount {
                let point = snapshot.point(for: pts[i].coordinate)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.close()
            fill.setFill()
            path.fill()
            stroke.setStroke()
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
