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
        if request.isSingleState { return await stateImage(for: request, scale: scale) }
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

    // MARK: Single-state print — map fills the page, metrics float over the bottom

    private static func stateImage(for request: MapPrintRequest, scale: CGFloat) async -> UIImage? {
        let size = request.statePosterSize
        guard let panel = await statePanel(for: request, size: size) else { return nil }

        // High / low terrain elevation across the state's run starts (best-effort).
        var high: Double?, low: Double?
        if request.stateMetrics.contains(where: { $0.needsElevation }) {
            let starts = request.mapped.compactMap(\.startCoordinate)
            if let elevations = await ElevationService.elevations(for: starts), !elevations.isEmpty {
                high = elevations.max(); low = elevations.min()
            }
        }

        let metrics = request.stateFooterMetrics(elevHigh: high, elevLow: low)
        let composition = StatePrintComposition(panelImage: panel, title: request.displayTitle,
                                                metrics: metrics, size: size)
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// The full-page state map: the muted region snapshot with the state outline and the routes.
    private static func statePanel(for request: MapPrintRequest, size: CGSize) async -> UIImage? {
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
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            bone.withAlphaComponent(0.14).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            if let name = request.boundaryStateName { drawStateBoundary(name, on: snapshot) }
            drawRoutes(request.mapped, on: snapshot, route: route)
        }
    }

    // MARK: Wall Art — abstract, full-bleed, text-free

    /// Text-free abstract wall art, four ways — always full and balanced whether that's five runs
    /// or five hundred.
    private static func artImage(for request: MapPrintRequest, scale: CGFloat) -> UIImage? {
        let runs = request.mapped
        guard !runs.isEmpty else { return nil }
        let size = request.posterNominalSize
        let palette = request.artPalette

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ground = UIColor(palette.ground)
        let line = UIColor(palette.line)
        let unit = size.width / 1000

        return renderer.image { context in
            let cg = context.cgContext
            ground.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            switch request.artStyle {
            case .grid:          drawGrid(runs, size: size, line: line, unit: unit)
            case .bloom:         drawBloom(runs, size: size, line: line, unit: unit, cg: cg, dark: palette.isDark)
            case .homeTurf:      drawHomeTurf(runs, region: request.region, size: size, line: line, unit: unit, cg: cg, dark: palette.isDark)
            case .constellation: drawConstellation(runs, region: request.region, size: size, line: line, unit: unit, cg: cg, dark: palette.isDark)
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

    /// A geography projector mapping coordinates into the poster, aspect-preserving with margin.
    private static func geoProjector(region: MKCoordinateRegion, size: CGSize,
                                     margin: CGFloat = 0.82) -> (CLLocationCoordinate2D) -> CGPoint {
        let latMax = region.center.latitude + region.span.latitudeDelta / 2
        let latMin = region.center.latitude - region.span.latitudeDelta / 2
        let lonMin = region.center.longitude - region.span.longitudeDelta / 2
        let lonMax = region.center.longitude + region.span.longitudeDelta / 2
        let lonScale = max(cos(((latMin + latMax) / 2) * .pi / 180), 0.01)
        let dataW = max((lonMax - lonMin) * lonScale, 1e-6)
        let dataH = max(latMax - latMin, 1e-6)
        let fit = min(size.width / dataW, size.height / dataH) * margin
        let offX = (size.width - dataW * fit) / 2
        let offY = (size.height - dataH * fit) / 2
        return { c in
            CGPoint(x: offX + (c.longitude - lonMin) * lonScale * fit,
                    y: offY + (latMax - c.latitude) * fit)
        }
    }

    private static func routePath(_ coordinates: [CLLocationCoordinate2D],
                                  project: (CLLocationCoordinate2D) -> CGPoint) -> UIBezierPath? {
        guard coordinates.count > 1 else { return nil }
        let path = UIBezierPath()
        var started = false
        for c in coordinates {
            let p = project(c)
            if started { path.addLine(to: p) } else { path.move(to: p); started = true }
        }
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        return path
    }

    // MARK: The Grid — a contact sheet of per-run glyphs

    private static func drawGrid(_ runs: [Run], size: CGSize, line: UIColor, unit: CGFloat) {
        let sorted = runs.sorted { $0.startDate < $1.startDate }   // a chronicle
        let n = sorted.count
        let aspect = Double(size.width / size.height)
        var cols = max(1, Int((Double(n) * aspect).squareRoot().rounded()))
        cols = min(cols, n)
        let rows = Int(ceil(Double(n) / Double(cols)))

        let margin = size.width * 0.06
        let cellW = (size.width - margin * 2) / CGFloat(cols)
        let cellH = (size.height - margin * 2) / CGFloat(rows)
        let glyphWidth = max(min(cellW, cellH) / 16, 0.8)
        line.withAlphaComponent(0.92).setStroke()

        for (i, run) in sorted.enumerated() {
            let r = i / cols, c = i % cols
            let cell = CGRect(x: margin + CGFloat(c) * cellW, y: margin + CGFloat(r) * cellH,
                              width: cellW, height: cellH)
            let inner = cell.insetBy(dx: cellW * 0.16, dy: cellH * 0.16)
            drawGlyph(run.coordinates, in: inner, lineWidth: glyphWidth)
        }
    }

    /// Draws a route normalized to fill a rect (aspect-preserving, centred) — geography irrelevant.
    private static func drawGlyph(_ coordinates: [CLLocationCoordinate2D], in rect: CGRect, lineWidth: CGFloat) {
        guard coordinates.count > 1 else { return }
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let lonScale = max(cos(((minLat + maxLat) / 2) * .pi / 180), 0.01)
        let dataW = max((maxLon - minLon) * lonScale, 1e-6)
        let dataH = max(maxLat - minLat, 1e-6)
        let scale = min(rect.width / dataW, rect.height / dataH)
        let offX = rect.minX + (rect.width - dataW * scale) / 2
        let offY = rect.minY + (rect.height - dataH * scale) / 2
        let path = UIBezierPath()
        var started = false
        for c in coordinates {
            let p = CGPoint(x: offX + (c.longitude - minLon) * lonScale * scale,
                            y: offY + (maxLat - c.latitude) * scale)
            if started { path.addLine(to: p) } else { path.move(to: p); started = true }
        }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    // MARK: The Bloom — every route re-centred to a common origin

    private static func drawBloom(_ runs: [Run], size: CGSize, line: UIColor, unit: CGFloat,
                                  cg: CGContext, dark: Bool) {
        let withRoutes = runs.filter { $0.coordinates.count > 1 }
        guard !withRoutes.isEmpty else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Common projection: re-centre each route at its start, one global scale, north up.
        let midLat = withRoutes.compactMap { $0.coordinates.first?.latitude }.reduce(0, +) / Double(withRoutes.count)
        let lonScale = max(cos(midLat * .pi / 180), 0.01)
        var maxExtent = 1e-6
        for run in withRoutes {
            guard let start = run.coordinates.first else { continue }
            for c in run.coordinates {
                let dx = (c.longitude - start.longitude) * lonScale
                let dy = (c.latitude - start.latitude)
                maxExtent = max(maxExtent, (dx * dx + dy * dy).squareRoot())
            }
        }
        let radius = Double(min(size.width, size.height)) * 0.42
        let scale = radius / maxExtent
        let lineWidth = (withRoutes.count <= 12 ? 3.4 : withRoutes.count <= 80 ? 2.2 : 1.5) * unit

        if dark { cg.setBlendMode(.plusLighter) }
        for (i, run) in withRoutes.enumerated() {
            guard let start = run.coordinates.first else { continue }
            let t = withRoutes.count > 1 ? CGFloat(i) / CGFloat(withRoutes.count - 1) : 1  // 0 old → 1 new
            line.withAlphaComponent(0.22 + 0.6 * t).setStroke()
            let path = UIBezierPath()
            var started = false
            for c in run.coordinates {
                let p = CGPoint(x: center.x + CGFloat((c.longitude - start.longitude) * lonScale * scale),
                                y: center.y - CGFloat((c.latitude - start.latitude) * scale))
                if started { path.addLine(to: p) } else { path.move(to: p); started = true }
            }
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
        cg.setBlendMode(.normal)
    }

    // MARK: Home Turf — the dense tangle, as heat

    private static func drawHomeTurf(_ runs: [Run], region: MKCoordinateRegion, size: CGSize,
                                     line: UIColor, unit: CGFloat, cg: CGContext, dark: Bool) {
        let project = geoProjector(region: region, size: size)
        let count = runs.count
        let lineWidth = (count <= 12 ? 4.0 : count <= 80 ? 2.6 : 1.8) * unit
        let alpha: CGFloat = count <= 12 ? 0.9 : count <= 80 ? 0.66 : 0.42
        if dark { cg.setBlendMode(.plusLighter) }
        for run in runs {
            guard let path = routePath(run.coordinates, project: project) else { continue }
            cg.saveGState()
            cg.setShadow(offset: .zero, blur: lineWidth * 2.6, color: line.cgColor)
            line.withAlphaComponent(alpha).setStroke()
            path.lineWidth = lineWidth
            path.stroke()
            cg.restoreGState()
        }
        cg.setBlendMode(.normal)
    }

    // MARK: Constellation — points placed by geography, sized by distance

    private static func drawConstellation(_ runs: [Run], region: MKCoordinateRegion, size: CGSize,
                                          line: UIColor, unit: CGFloat, cg: CGContext, dark: Bool) {
        let project = geoProjector(region: region, size: size)
        let sorted = runs.sorted { $0.startDate < $1.startDate }

        // A quiet chronological thread linking the runs.
        let thread = UIBezierPath()
        var started = false
        for run in sorted {
            guard let start = run.startCoordinate else { continue }
            let p = project(start)
            if started { thread.addLine(to: p) } else { thread.move(to: p); started = true }
        }
        line.withAlphaComponent(0.16).setStroke()
        thread.lineWidth = 1 * unit
        thread.stroke()

        // Points sized by distance.
        let maxDist = runs.map(\.distance).max() ?? 1
        for run in runs {
            guard let start = run.startCoordinate else { continue }
            let p = project(start)
            let t = maxDist > 0 ? CGFloat(run.distance / maxDist) : 0
            let radius = (3 + 10 * t.squareRoot()) * unit
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            cg.saveGState()
            if dark { cg.setShadow(offset: .zero, blur: radius * 1.5, color: line.cgColor) }
            line.withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: rect).fill()
            cg.restoreGState()
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
