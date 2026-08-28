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
        if request.kind == .cities && request.cityIndex { return cityIndexImage(for: request, scale: scale) }
        if request.isSingleState { return await stateImage(for: request, scale: scale) }
        let panelSize = CGSize(width: MapPrintComposition.width, height: MapPrintComposition.artHeight)
        let visited = request.kind == .states ? await visitedStateIntensities(request.runs) : [:]
        let boundaries = USStateBoundaries.shared
        let visitedNames = visited.keys.filter { boundaries.isState($0) }.sorted()

        // "USA only" draws a clean choropleth with no base map (so no Canada / Mexico); otherwise the
        // muted Apple base-map snapshot with surrounding context.
        let panelImage: UIImage?
        if request.kind == .states && request.statesUSAOnly {
            panelImage = statesChoroplethPanel(size: panelSize, visited: visited, ground: request.ground)
        } else {
            panelImage = await panel(for: request, size: panelSize, visited: visited)
        }
        guard let panelImage else { return nil }

        let composition = MapPrintComposition(panelImage: panelImage, orientation: request.orientation,
                                              footer: request.footerData(visitedStateNames: visitedNames),
                                              showFooter: request.showFooter)
        let renderer = ImageRenderer(content: composition)
        renderer.scale = scale
        return renderer.uiImage
    }

    /// A clean US choropleth on a plain ground — visited states filled, the rest outlined, no Apple
    /// base map. Framed to the lower 48 (Alaska / Hawaii fall outside the frame), so no neighbouring
    /// countries appear. This is the "USA only" states print.
    private static func statesChoroplethPanel(size: CGSize, visited: [String: Double], ground: Color) -> UIImage {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5, longitude: -96),
            span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 58)
        )
        let project = geoProjector(region: region, size: size, margin: 0.92)
        let navy = UIColor(Theme.Palette.navy)
        let outline = UIColor(Theme.Palette.ink).withAlphaComponent(0.28)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor(ground).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            for boundary in USStateBoundaries.shared.boundaries {
                let intensity = visited[boundary.name]
                for polygon in boundary.polygons {
                    let path = UIBezierPath()
                    let pts = polygon.points()
                    for i in 0..<polygon.pointCount {
                        let p = project(pts[i].coordinate)
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.close()
                    if let intensity {
                        navy.withAlphaComponent(0.30 + 0.55 * CGFloat(intensity)).setFill()
                        path.fill()
                        navy.withAlphaComponent(0.9).setStroke()
                        path.lineWidth = 1.2
                        path.stroke()
                    } else {
                        outline.setStroke()
                        path.lineWidth = 0.8
                        path.stroke()
                    }
                }
            }
        }
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
        let size = request.posterNominalSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawArt(request, size: size)
        }
    }

    /// The whole art composition, drawn absolutely into `size`. One body serves the screen
    /// preview and the banded print path — a band is just a translated window onto this same
    /// drawing, which is what guarantees a banded print cannot differ from the preview.
    private static func drawArt(_ request: MapPrintRequest, size: CGSize) {
        // Only the Grid draws routes, so only the Grid needs them. The calendar- and
        // distance-based styles take the whole history — which is what lets a treadmill-heavy
        // record still fill a Rings, a Thread or a Strata, exactly as their gates promise.
        let runs = request.artStyle == .grid ? request.mapped : request.runs
        guard !runs.isEmpty, let cg = UIGraphicsGetCurrentContext() else { return }
        let palette = request.artPalette
        let ground = UIColor(palette.ground)
        let line = UIColor(palette.line)
        let unit = size.width / 1000

        ground.setFill()
        cg.fill(CGRect(origin: .zero, size: size))

        let weight = request.artWeight.multiplier
        switch request.artStyle {
        case .grid:          drawGrid(runs, size: size, line: line, unit: unit, weight: weight)
        case .ridgeline:     drawRidgeline(runs, size: size, line: line, ground: ground, unit: unit, weight: weight)
        case .rings:         drawRings(runs, size: size, line: line, unit: unit, cg: cg, dark: palette.isDark, weight: weight)
        case .thread:        drawThread(runs, size: size, line: line, unit: unit, weight: weight)
        case .strata:        drawStrata(runs, size: size, line: line, unit: unit, weight: weight)
        }
        // No vignette or gradient finish: the ink on its ground *is* the piece — any overlay
        // reads as a filter, not a print.
        drawArtCaption(request, runs: runs, size: size)
    }

    /// The one line of type the Anthology allows itself: what this body of work is, set small in
    /// the margin. "GILBERT RUNS · 2019–2026 · 220 ACTIVITIES · 1,482 MI" is the whole grammar —
    /// the title half and the summary half each optional, the edge chosen, and hidden the
    /// default because the pieces earned their silence.
    private static func drawArtCaption(_ request: MapPrintRequest, runs: [Run], size: CGSize) {
        guard request.artCaptionEdge != .hidden,
              let cg = UIGraphicsGetCurrentContext() else { return }

        var parts: [String] = []
        if request.artCaptionShowsTitle, !request.title.isEmpty {
            parts.append(request.title.uppercased())
        }
        if request.artCaptionShowsSummary {
            let dates = runs.map(\.startDate)
            let calendar = Calendar.current
            if let first = dates.min(), let last = dates.max() {
                let y1 = calendar.component(.year, from: first)
                let y2 = calendar.component(.year, from: last)
                parts.append(y1 == y2 ? String(y1) : "\(y1)–\(y2)")
            }
            let count = runs.count
            parts.append(count == 1 ? "1 ACTIVITY" : "\(count) ACTIVITIES")
            let metres = runs.reduce(0.0) { $0 + $1.distance }
            parts.append(Format.distance(metres, decimals: 0).uppercased())
        }
        guard !parts.isEmpty else { return }
        let text = parts.joined(separator: "  ·  ") as NSString

        let unit = size.width / 1000
        let ink = UIColor(request.artPalette.line).withAlphaComponent(0.55)
        let font = UIFont.systemFont(ofSize: 14 * unit, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: ink, .kern: 2.2 * unit
        ]
        let drawn = text.size(withAttributes: attributes)
        let inset = size.width * 0.055

        switch request.artCaptionEdge {
        case .top:
            text.draw(at: CGPoint(x: (size.width - drawn.width) / 2, y: inset), withAttributes: attributes)
        case .bottom:
            text.draw(at: CGPoint(x: (size.width - drawn.width) / 2,
                                  y: size.height - inset - drawn.height), withAttributes: attributes)
        case .left:
            cg.saveGState()
            cg.translateBy(x: inset, y: (size.height + drawn.width) / 2)
            cg.rotate(by: -.pi / 2)
            text.draw(at: .zero, withAttributes: attributes)
            cg.restoreGState()
        case .right:
            cg.saveGState()
            cg.translateBy(x: size.width - inset - drawn.height, y: (size.height + drawn.width) / 2)
            cg.rotate(by: -.pi / 2)
            text.draw(at: .zero, withAttributes: attributes)
            cg.restoreGState()
        case .hidden:
            break
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

    private static func drawGrid(_ runs: [Run], size: CGSize, line: UIColor, unit: CGFloat, weight: CGFloat) {
        let sorted = runs.sorted { $0.startDate < $1.startDate }   // a chronicle
        let n = sorted.count
        guard n > 0 else { return }
        let aspect = Double(size.width / size.height)
        let ideal = min(n, max(1, Int((Double(n) * aspect).squareRoot().rounded())))

        // Pick a column count near the ideal that leaves the fewest empty cells on the last row,
        // so the grid never ends in a lone orphan glyph dangling under a full block. Ties break
        // toward the ideal (aspect-true) column count.
        var cols = ideal
        var bestGap = Int.max
        for candidate in max(1, ideal - 3)...min(n, ideal + 3) {
            let remainder = n % candidate
            let gap = remainder == 0 ? 0 : candidate - remainder
            if gap < bestGap || (gap == bestGap && abs(candidate - ideal) < abs(cols - ideal)) {
                bestGap = gap
                cols = candidate
            }
        }
        let rows = Int(ceil(Double(n) / Double(cols)))
        let lastRowCount = n - (rows - 1) * cols   // glyphs on the final (possibly partial) row

        let margin = size.width * 0.06
        let cellW = (size.width - margin * 2) / CGFloat(cols)
        let cellH = (size.height - margin * 2) / CGFloat(rows)
        let glyphWidth = max(min(cellW, cellH) / 16 * weight, 0.8)
        line.withAlphaComponent(0.92).setStroke()

        for (i, run) in sorted.enumerated() {
            let r = i / cols, c = i % cols
            // Centre the final partial row so any leftover glyphs sit in the middle rather than
            // hanging off the left edge.
            let rowCount = (r == rows - 1) ? lastRowCount : cols
            let rowOffset = CGFloat(cols - rowCount) / 2 * cellW
            let cell = CGRect(x: margin + rowOffset + CGFloat(c) * cellW,
                              y: margin + CGFloat(r) * cellH,
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

    // MARK: Ridgeline — every elevation profile stacked as one mountain chain

    /// The joy of stacked ridges: each run's elevation profile is a ridge, oldest at the top,
    /// each newer ridge filled with the ground before it's stroked so it occludes the chain
    /// behind it. Runs without an elevation series simply aren't ridges.
    private static func drawRidgeline(_ runs: [Run], size: CGSize, line: UIColor, ground: UIColor,
                                      unit: CGFloat, weight: CGFloat) {
        let ridged = runs.filter { $0.elevationSeries.count > 4 }
            .sorted { $0.startDate < $1.startDate }
            .suffix(48)
        guard !ridged.isEmpty else { return }

        let marginX = size.width * 0.12
        let marginY = size.height * 0.16
        let drawableHeight = size.height - marginY * 2
        let rowSpacing = ridged.count > 1 ? drawableHeight / CGFloat(ridged.count - 1) : 0
        // Ridges must overlap generously — the occlusion between them is the whole effect, and
        // a shallow amplitude reads as a wave pattern rather than a mountain chain.
        let amplitude = max(rowSpacing * 4.2, drawableHeight * 0.12)
        let width = size.width - marginX * 2

        for (row, run) in ridged.enumerated() {
            let baseline = marginY + (ridged.count > 1 ? CGFloat(row) * rowSpacing : drawableHeight / 2)
            let samples = run.elevationSeries
            let minV = samples.min() ?? 0
            let span = max((samples.max() ?? 0) - minV, 1)

            let ridge = UIBezierPath()
            ridge.move(to: CGPoint(x: marginX, y: baseline))
            for (i, sample) in samples.enumerated() {
                let x = marginX + width * CGFloat(i) / CGFloat(samples.count - 1)
                let norm = CGFloat((sample - minV) / span)
                ridge.addLine(to: CGPoint(x: x, y: baseline - norm * amplitude))
            }
            ridge.addLine(to: CGPoint(x: marginX + width, y: baseline))

            // Fill with the ground first: the newer ridge occludes the peaks behind it.
            let fill = ridge.copy() as! UIBezierPath
            fill.close()
            ground.setFill()
            fill.fill()

            line.withAlphaComponent(0.92).setStroke()
            ridge.lineWidth = 1.7 * unit * weight
            ridge.lineJoinStyle = .round
            ridge.lineCapStyle = .round
            ridge.stroke()
        }
    }

    // MARK: Rings — the years as tree rings

    /// One ring per year, every run a radial tick at its day-of-year angle, tick length by
    /// distance. Races strike through at full strength — the year's landmarks.
    private static func drawRings(_ runs: [Run], size: CGSize, line: UIColor, unit: CGFloat,
                                  cg: CGContext, dark: Bool, weight: CGFloat) {
        let calendar = Calendar.current
        let byYear = Dictionary(grouping: runs) { calendar.component(.year, from: $0.startDate) }
        let years = byYear.keys.sorted()
        guard !years.isEmpty else { return }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Each year owns a band, and every run is a tick growing outward from that year's
        // circle — so a heavy year fills its ring solid and a quiet one stays sparse, which is
        // the whole point of reading a trunk. The first cut drew short ticks *centred* on a
        // faint orbit, which read as dotted circles rather than growth.
        let outer = min(size.width, size.height) * 0.44
        let inner = outer * 0.24
        let band = (outer - inner) / CGFloat(years.count)
        let maxDist = runs.map(\.distance).max() ?? 1

        if dark { cg.setBlendMode(.plusLighter) }
        for (index, year) in years.enumerated() {
            let ringInner = inner + band * CGFloat(index)
            let usable = band * 0.84          // a hairline of air between years

            let orbit = UIBezierPath(arcCenter: center, radius: ringInner,
                                     startAngle: 0, endAngle: .pi * 2, clockwise: true)
            line.withAlphaComponent(0.22).setStroke()
            orbit.lineWidth = 0.9 * unit
            orbit.stroke()

            let yearRuns = byYear[year] ?? []
            // Tick width follows how crowded the ring is: a busy year becomes a solid band
            // instead of a smear, a light year keeps its individual marks.
            let circumference = 2 * .pi * ringInner
            let spacing = circumference / CGFloat(max(yearRuns.count, 1))
            let tickWidth = min(max(spacing * 0.55, 1.1 * unit), 7 * unit) * weight

            for run in yearRuns {
                let day = calendar.ordinality(of: .day, in: .year, for: run.startDate) ?? 1
                let angle = CGFloat(day) / 366 * 2 * .pi - .pi / 2
                let t = maxDist > 0 ? CGFloat(run.distance / maxDist) : 0
                // Every run reaches a third of the band; distance carries it the rest.
                let length = usable * (0.34 + 0.66 * t.squareRoot())
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                let tick = UIBezierPath()
                tick.move(to: CGPoint(x: center.x + direction.x * ringInner,
                                      y: center.y + direction.y * ringInner))
                tick.addLine(to: CGPoint(x: center.x + direction.x * (ringInner + length),
                                         y: center.y + direction.y * (ringInner + length)))
                line.withAlphaComponent(run.isRace ? 1.0 : 0.72).setStroke()
                tick.lineWidth = run.isRace ? tickWidth * 1.9 : tickWidth
                tick.lineCapStyle = .butt
                tick.stroke()
            }
        }
        // The eye: a small solid mark, so the composition has a centre to grow from.
        let eyeRadius = 3.5 * unit
        line.withAlphaComponent(0.8).setFill()
        UIBezierPath(ovalIn: CGRect(x: center.x - eyeRadius, y: center.y - eyeRadius,
                                    width: eyeRadius * 2, height: eyeRadius * 2)).fill()
        cg.setBlendMode(.normal)
    }

    // MARK: Thread — the whole history as one unbroken line

    /// Every activity in date order becomes a stretch of a single continuous line, its length
    /// proportional to its distance, wrapped boustrophedon across the sheet like text. Where an
    /// activity recorded elevation, its stretch carries the profile as a gentle vertical
    /// modulation; a flat stretch is simply a flat road. The claim the piece makes is literal:
    /// this is every mile, as one line that never lifts off the paper.
    private static func drawThread(_ runs: [Run], size: CGSize, line: UIColor, unit: CGFloat, weight: CGFloat) {
        let ordered = runs.sorted { $0.startDate < $1.startDate }
        let total = ordered.reduce(0.0) { $0 + max($1.distance, 1) }
        guard total > 0 else { return }

        let marginX = size.width * 0.10
        let marginY = size.height * 0.12
        let usableW = size.width - marginX * 2
        let usableH = size.height - marginY * 2
        // Rows from the sheet's own shape: a portrait 2:3 gets 12, a landscape 3:2 gets 6 —
        // the line stays airy rather than packing tighter as the history grows, because the
        // scale (miles per point) absorbs the growth instead.
        let rows = max(4, Int((size.height / size.width * 6).rounded()))
        let rowH = usableH / CGFloat(rows - 1 == 0 ? 1 : rows - 1)
        let threadLength = usableW * CGFloat(rows)
        // Rendered proof forced both numbers down: at 8 rows per portrait sheet and a third of
        // the row as amplitude, two hundred activities of sawtooth elevation read as static
        // noise, not as a drawn line. Fewer rows give the line air; a sixth of the row keeps
        // the modulation a suggestion of terrain rather than a seismograph.
        let amplitude = min(rowH * 0.16, usableH * 0.035)

        // Cumulative length along the thread → a point on the sheet, alternating direction
        // per row so the line turns back on itself rather than teleporting.
        func point(at length: CGFloat, rise: CGFloat) -> CGPoint {
            let clamped = min(max(length, 0), threadLength - 0.001)
            let row = Int(clamped / usableW)
            let frac = clamped - CGFloat(row) * usableW
            let x = row.isMultiple(of: 2) ? marginX + frac : marginX + usableW - frac
            let y = marginY + CGFloat(row) * rowH - rise
            return CGPoint(x: x, y: y)
        }

        let path = UIBezierPath()
        var cursor: CGFloat = 0
        var started = false
        for run in ordered {
            let span = CGFloat(max(run.distance, 1) / total) * threadLength
            let elev = run.elevationSeries
            // Sample density follows the stretch's drawn length, so a two-mile run occupying
            // twenty points of thread gets three gentle kinks rather than forty-eight — the
            // jaggedness in the first render came almost entirely from oversampling short
            // stretches.
            let samples = max(3, min(24, Int(span / 16)))
            let minV = elev.min() ?? 0
            let spanV = max((elev.max() ?? 0) - minV, 1)
            var rises: [CGFloat] = (0 ..< samples).map { i in
                guard elev.count > 4 else { return 0 }
                let t = CGFloat(i) / CGFloat(samples - 1)
                let v = elev[min(Int(t * CGFloat(elev.count - 1)), elev.count - 1)]
                return (CGFloat((v - minV) / spanV) - 0.5) * 2 * amplitude
            }
            // A three-point average — terrain, not telemetry.
            if rises.count > 2 {
                rises = rises.indices.map { i in
                    (rises[max(0, i-1)] + rises[i] + rises[min(rises.count-1, i+1)]) / 3
                }
            }
            for (i, rise) in rises.enumerated() {
                let t = CGFloat(i) / CGFloat(samples - 1)
                let p = point(at: cursor + t * span, rise: rise)
                if started { path.addLine(to: p) } else { path.move(to: p); started = true }
            }
            cursor += span
        }

        line.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 2.0 * unit * weight
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    // MARK: Strata — the years as sediment layers

    /// One horizontal band per year, oldest at the top, every activity a vertical bar at its day
    /// of the year with height proportional to distance — the record reads as strata: thick
    /// seasons, thin seasons, the marathon block visible as a ridge in its layer. Races strike
    /// at full strength, the same convention Rings uses.
    private static func drawStrata(_ runs: [Run], size: CGSize, line: UIColor, unit: CGFloat, weight: CGFloat) {
        let calendar = Calendar.current
        let byYear = Dictionary(grouping: runs) { calendar.component(.year, from: $0.startDate) }
        let years = byYear.keys.sorted()
        guard !years.isEmpty, let maxDistance = runs.map(\.distance).max(), maxDistance > 0 else { return }

        let marginX = size.width * 0.10
        let marginY = size.height * 0.12
        let usableW = size.width - marginX * 2
        let bandH = (size.height - marginY * 2) / CGFloat(years.count)
        // Square-root scaling, or the marathon owns the ceiling and every daily run becomes a
        // stub at the floor — which is exactly how the first render read. The root compresses
        // the outliers and lets an ordinary week stand at half height.
        let barMax = bandH * 0.82
        let barWidth = 2.6 * unit * weight

        for (index, year) in years.enumerated() {
            let baseline = marginY + CGFloat(index + 1) * bandH - bandH * 0.10

            // The layer's floor — faint, so the bars sit on something without the rule
            // competing with them.
            let rule = UIBezierPath()
            rule.move(to: CGPoint(x: marginX, y: baseline))
            rule.addLine(to: CGPoint(x: marginX + usableW, y: baseline))
            line.withAlphaComponent(0.15).setStroke()
            rule.lineWidth = 1.0 * unit
            rule.stroke()

            for run in byYear[year] ?? [] {
                let day = calendar.ordinality(of: .day, in: .year, for: run.startDate) ?? 1
                let x = marginX + usableW * CGFloat(day - 1) / 365.0
                let height = max(3 * unit, barMax * CGFloat((run.distance / maxDistance).squareRoot()))
                let bar = UIBezierPath()
                bar.move(to: CGPoint(x: x, y: baseline))
                bar.addLine(to: CGPoint(x: x, y: baseline - height))
                line.withAlphaComponent(run.isRace ? 1.0 : 0.72).setStroke()
                bar.lineWidth = run.isRace ? barWidth * 1.4 : barWidth
                bar.lineCapStyle = .round
                bar.stroke()
            }
        }
    }


    // MARK: The City Index — every city, as type

    /// The cities piece as a typographic index: every city the history touches, ranked by
    /// visits, set in columns on the art palette's ground. No map, no pins — which is exactly
    /// what makes it printable, where the pinned form (an Apple snapshot) is licensed for
    /// screens only.
    ///
    /// The count trails each name as a thin figure rather than a bar or a dot: the piece is a
    /// record, and a record is read, not measured.
    static func cityIndexImage(for request: MapPrintRequest, scale: CGFloat) -> UIImage? {
        let size = request.posterIndexSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawCityIndex(request, size: size)
        }
    }

    private static func drawCityIndex(_ request: MapPrintRequest, size: CGSize) {
        let palette = request.artPalette
        UIColor(palette.ground).setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        var counts: [String: Int] = [:]
        var metres: [String: Double] = [:]
        for run in request.runs {
            guard let city = run.city, !city.isEmpty else { continue }
            counts[city, default: 0] += 1
            metres[city, default: 0] += run.distance
        }
        let cities = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        guard !cities.isEmpty else { return }

        let ink = UIColor(palette.line)
        let marginX = size.width * 0.10
        var marginY = size.height * 0.11
        var usableH = size.height - marginY * 2
        let usableW = size.width - marginX * 2

        // The tour-poster layout: a hero across the top of the sheet — the cities as a dot map
        // in the piece's own ink, or the buyer's photograph — with the list set beneath it the
        // way a tour bill lists its dates. The hero takes the top 42%; the type keeps the rest.
        if request.cityIndexHero != .none {
            let heroRect = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.42)
            drawCityIndexHero(request, in: heroRect, ink: ink, sheet: size)
            marginY = size.height * 0.05
            usableH = size.height - heroRect.height - marginY - size.height * 0.09
        }
        let listTop = request.cityIndexHero == .none ? marginY : size.height * 0.42 + marginY

        // Fit by search: the largest type size at which every city fits the sheet, in one
        // column when the list is short and in two or three when it is long. Auto-fitting is
        // what keeps ten cities monumental and two hundred still legible — the same promise
        // the Grid makes about run counts.
        func detail(for city: String, count: Int) -> String {
            guard request.cityIndexTotals else { return "\(count)" }
            let miles = Format.distance(metres[city] ?? 0, decimals: 0)
            return "\(count) · \(miles)"
        }

        // Each column count admits a largest type size, bounded two ways at once: the rows
        // must share the column's height, and the widest entry must fit the column's width.
        // Type width scales with point size, so the widest entry is measured once at a
        // reference size and the horizontal bound follows by ratio. The winning layout is
        // whichever column count admits the biggest type — adding a column halves the width
        // available to a name but can still win when the list is long enough that height,
        // not width, is what pinches. Nothing can overlap, because overlap was only ever a
        // constraint this search declined to apply.
        let referenceSize: CGFloat = 100
        let referenceName = UIFont.systemFont(ofSize: referenceSize, weight: .semibold)
        let referenceDetail = UIFont.systemFont(ofSize: referenceSize * 0.55, weight: .regular)
        let widestAtReference = cities.map { city, count in
            (city.uppercased() as NSString).size(withAttributes: [.font: referenceName]).width
                + referenceSize * 0.35
                + (detail(for: city, count: count) as NSString)
                    .size(withAttributes: [.font: referenceDetail]).width
        }.max() ?? referenceSize

        var best: (columns: Int, rows: Int, rowH: CGFloat, colW: CGFloat, pointSize: CGFloat)?
        for columns in [1, 2, 3] {
            let rows = Int(ceil(Double(cities.count) / Double(columns)))
            let rowH = usableH / CGFloat(rows)
            let colW = (usableW - CGFloat(columns - 1) * usableW * 0.06) / CGFloat(columns)
            let pointSize = min(rowH * 0.62, referenceSize * colW / widestAtReference)
            if best == nil || pointSize > best!.pointSize {
                best = (columns, rows, rowH, colW, pointSize)
            }
        }
        guard let layout = best else { return }

        let font = UIFont.systemFont(ofSize: layout.pointSize, weight: .semibold)
        let countFont = UIFont.systemFont(ofSize: layout.pointSize * 0.55, weight: .regular)
        for (i, entry) in cities.enumerated() {
            let column = i / layout.rows
            let row = i % layout.rows
            let x = marginX + CGFloat(column) * (layout.colW + usableW * 0.06)
            let y = listTop + CGFloat(row) * layout.rowH + (layout.rowH - layout.pointSize) / 2
            let name = entry.key.uppercased() as NSString
            name.draw(at: CGPoint(x: x, y: y),
                      withAttributes: [.font: font, .foregroundColor: ink])
            let nameW = name.size(withAttributes: [.font: font]).width
            (detail(for: entry.key, count: entry.value) as NSString).draw(
                at: CGPoint(x: x + nameW + layout.pointSize * 0.35, y: y + layout.pointSize * 0.34),
                withAttributes: [.font: countFont,
                                 .foregroundColor: ink.withAlphaComponent(0.45)])
        }
    }

    /// The hero above the list: the buyer's photograph aspect-filled, or every city as a dot
    /// placed by geography in the piece's own ink — sized by visits, our ground, our ink,
    /// printable. The photograph is drawn as supplied; the dot map is drawn like everything
    /// else in the Anthology.
    private static func drawCityIndexHero(_ request: MapPrintRequest, in rect: CGRect,
                                          ink: UIColor, sheet: CGSize) {
        let unit = sheet.width / 1000
        switch request.cityIndexHero {
        case .photo:
            guard let photo = request.cityIndexPhoto, photo.size.width > 0 else { break }
            let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
            let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            if let cg = UIGraphicsGetCurrentContext() {
                cg.saveGState()
                cg.clip(to: rect)
                photo.draw(in: CGRect(x: rect.midX - drawn.width / 2,
                                      y: rect.midY - drawn.height / 2,
                                      width: drawn.width, height: drawn.height))
                cg.restoreGState()
            }
        case .map:
            // One dot per city at its centroid, area by visits. A dot map, not a road map —
            // which is what keeps it ours to sell.
            var cityPoints: [String: (lat: Double, lon: Double, n: Int)] = [:]
            for run in request.runs {
                guard let city = run.city, !city.isEmpty, let c = run.startCoordinate else { continue }
                var entry = cityPoints[city] ?? (0, 0, 0)
                entry.lat += c.latitude; entry.lon += c.longitude; entry.n += 1
                cityPoints[city] = entry
            }
            guard !cityPoints.isEmpty else { break }
            let coords = cityPoints.mapValues { CLLocationCoordinate2D(latitude: $0.lat / Double($0.n),
                                                                       longitude: $0.lon / Double($0.n)) }
            let lats = coords.values.map(\.latitude), lons = coords.values.map(\.longitude)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                               longitude: (lons.min()! + lons.max()!) / 2),
                span: MKCoordinateSpan(latitudeDelta: max(lats.max()! - lats.min()!, 0.5) * 1.5,
                                       longitudeDelta: max(lons.max()! - lons.min()!, 0.5) * 1.5))
            let project = geoProjector(region: region, size: rect.size, margin: 0.8)
            let maxN = cityPoints.values.map(\.n).max() ?? 1
            for (city, coordinate) in coords {
                let p = project(coordinate)
                let n = cityPoints[city]?.n ?? 1
                let radius = (6 + 16 * CGFloat(Double(n) / Double(maxN)).squareRoot()) * unit
                let dot = UIBezierPath(ovalIn: CGRect(x: rect.minX + p.x - radius,
                                                      y: rect.minY + p.y - radius,
                                                      width: radius * 2, height: radius * 2))
                ink.withAlphaComponent(0.85).setFill()
                dot.fill()
            }
        case .none:
            break
        }
    }

    // MARK: The print file — banded, for the pieces made of our own ink

    /// Streams a print-resolution sheet to disk for the compositions that are safe to sell:
    /// the Anthology styles and the City Index, which draw nothing but our own ink on our own
    /// ground. The map-based prints stay off this path — their base layer is an Apple
    /// snapshot, licensed for screens and not for merchandise.
    ///
    /// Banded the same way every large sheet in this app is: a 16 × 24 is 4800 × 7200 pixels
    /// and a 24 × 36 is 7200 × 10800, and neither is ever held as one allocation. Each band
    /// re-draws the full composition with the context translated — the composition functions
    /// draw absolutely, so a band is just a window onto the same drawing.
    static func printFile(for request: MapPrintRequest, geometry: PrintGeometry) async throws -> URL {
        let width = Int(geometry.trimPixels.width)
        let height = Int(geometry.trimPixels.height)
        let full = CGSize(width: CGFloat(width), height: CGFloat(height))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("etch-anthology-\(UUID().uuidString).png")
        let writer = try PrintFileWriter(width: width, height: height, url: url)

        let bandHeight = 900
        var top = 0
        while top < height {
            try Task.checkCancellation()
            let rows = min(bandHeight, height - top)
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = 1
            let band = UIGraphicsImageRenderer(
                size: CGSize(width: width, height: rows), format: format
            ).image { context in
                context.cgContext.translateBy(x: 0, y: CGFloat(-top))
                if request.kind == .cities && request.cityIndex {
                    drawCityIndex(request, size: full)
                } else {
                    drawArt(request, size: full)
                }
            }
            guard let cgImage = band.cgImage else {
                try? FileManager.default.removeItem(at: url)
                throw PrintFileWriter.WriteError.compressionFailed
            }
            try writer.append(band: cgImage, rows: rows)
            top += rows
            await Task.yield()
        }
        return try writer.finish()
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
