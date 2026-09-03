import SwiftUI
import MapKit

/// THE MAP — the year's geography as a spread (strategy §9). Self-rendered vectors only, like
/// every book page: the state polygons come from `USStateBoundaries` (embedded in the binary),
/// visited states are tinted by their share of the miles, cities are dotted by activity count,
/// races are starred in accent, and a callout column names what the figure can only show.
///
/// The page exists only when the history touched at least one US state (the plan gates it), and
/// the figure frames itself to the visited states rather than the whole country — a year run in
/// Arizona and Utah fills the page with Arizona and Utah, with unvisited neighbours as hairlines
/// for bearings.
extension BookPageView {

    var mapPage: some View {
        let miles = mapStateMiles
        let stats = RunStatistics(plan.runs)
        let places = stats.travelPlaces
        let raceCoordinates = plan.runs.filter(\.isRace).compactMap(\.startCoordinate)
        let figure = mapFigure(stateMiles: miles, places: places, races: raceCoordinates)

        return VStack(spacing: 34) {
            pageHeader(plan.subject.kind == .year ? "WHERE THE YEAR WENT" : "WHERE THE MILES WENT",
                       subtitle: "THE MAP")

            HStack(alignment: .top, spacing: 50) {
                VStack(spacing: 18) {
                    if let figure {
                        mapCanvas(figure)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    mapLegend(hasRaces: !raceCoordinates.isEmpty)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                mapCallouts(stateMiles: miles, places: places,
                            raceCount: plan.runs.filter(\.isRace).count)
                    .frame(width: 292)
            }
        }
        .padding(margin)
    }

    // MARK: The figure

    private func mapCanvas(_ figure: BookMapFigure) -> some View {
        Canvas { context, size in
            // Fit the framed map space into the canvas, centred, aspect preserved. Map points
            // are Web Mercator with y growing southward, so normalized y maps straight down.
            let scale = min(size.width, size.height * figure.aspect)
            let drawn = CGSize(width: scale, height: scale / figure.aspect)
            let origin = CGPoint(x: (size.width - drawn.width) / 2,
                                 y: (size.height - drawn.height) / 2)
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + p.x * drawn.width, y: origin.y + p.y * drawn.height)
            }

            // Unvisited first, visited over them, so a shared border reads as the visited
            // state's line.
            for state in figure.states.sorted(by: { ($0.tint == nil ? 0 : 1) < ($1.tint == nil ? 0 : 1) }) {
                var path = Path()
                for ring in state.rings where ring.count > 2 {
                    path.move(to: point(ring[0]))
                    for p in ring.dropFirst() { path.addLine(to: point(p)) }
                    path.closeSubpath()
                }
                if let tint = state.tint {
                    context.fill(path, with: .color(accent.opacity(0.14 + 0.34 * tint)))
                    context.stroke(path, with: .color(accent.opacity(0.85)), lineWidth: 1.6)
                } else {
                    context.stroke(path, with: .color(subtle.opacity(0.4)), lineWidth: 0.8)
                }
            }

            // Cities: an ink dot sized by how often the year came back to it, on a bone halo so
            // it stays legible over a tinted state.
            for city in figure.cities {
                let c = point(city.point)
                let r = city.weight
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                             with: .color(ground.opacity(0.9)))
                context.fill(Path(ellipseIn: rect), with: .color(ink))
            }

            // Race days: starred, in accent, above everything.
            for race in figure.races {
                let c = point(race)
                context.fill(starPath(center: c, radius: 10), with: .color(ground.opacity(0.9)))
                context.fill(starPath(center: c, radius: 8), with: .color(accent))
            }
        }
    }

    /// One quiet line under the figure so the marks don't need decoding.
    private func mapLegend(hasRaces: Bool) -> some View {
        HStack(spacing: 22) {
            HStack(spacing: 5) {
                ForEach([0.14, 0.31, 0.48], id: \.self) { alpha in
                    Rectangle().fill(accent.opacity(alpha)).frame(width: 16, height: 10)
                }
                Text("MILES").padding(.leading, 4)
            }
            HStack(spacing: 7) {
                Circle().fill(ink).frame(width: 8, height: 8)
                Text("CITIES")
            }
            if hasRaces {
                HStack(spacing: 7) {
                    StarShape().fill(accent).frame(width: 12, height: 12)
                    Text("RACE DAYS")
                }
            }
        }
        .font(.etch(size: 11, weight: .semibold)).tracking(2)
        .foregroundStyle(subtle)
    }

    // MARK: The callouts — what the figure can only show, named

    private func mapCallouts(stateMiles: [String: Double],
                             places: [RunStatistics.TravelPlace],
                             raceCount: Int) -> some View {
        let mostState = stateMiles.max { $0.value < $1.value }
        let mostCity = places.max { $0.runs.count < $1.runs.count }
        let range = northSouthRange(places: places)

        return VStack(alignment: .leading, spacing: 30) {
            if stateMiles.count > 1 {
                // Every state named when they fit on the line; a count that says four and a
                // list that shows three reads as an error, not a summary. Only a genuinely
                // long list falls back to the leaders plus an honest remainder.
                let ordered = stateMiles.keys.sorted {
                    (stateMiles[$0] ?? 0) > (stateMiles[$1] ?? 0)
                }
                let listed = ordered.count <= 4
                    ? ordered.joined(separator: " · ")
                    : ordered.prefix(3).joined(separator: " · ") + " · +\(ordered.count - 3) MORE"
                calloutRow("THE GROUND",
                           value: "\(stateMiles.count) STATES",
                           detail: listed)
            }
            if let mostState {
                calloutRow("MOST MILES",
                           value: mostState.key.uppercased(),
                           detail: "\(mostState.value.formatted(.number.precision(.fractionLength(0)))) \(UnitSystem.current.label.uppercased())")
            }
            if let mostCity {
                calloutRow("MOST-RUN CITY",
                           value: cityName(mostCity).uppercased(),
                           detail: "\(mostCity.runs.count) ACTIVITIES")
            }
            if raceCount > 0 {
                calloutRow("RACE DAYS",
                           value: "\(raceCount)",
                           detail: "STARRED ON THE MAP")
            }
            if !plan.story.newStates.isEmpty {
                calloutRow("NEW GROUND",
                           value: plan.story.newStates.count == 1
                               ? plan.story.newStates[0].uppercased()
                               : "\(plan.story.newStates.count) NEW STATES",
                           detail: plan.story.newStates.count == 1
                               ? "FIRST MILES EVER"
                               : plan.story.newStates.prefix(3).joined(separator: " · "))
            }
            if let range {
                calloutRow("THE SPAN",
                           value: range.value,
                           detail: range.detail)
            }
            Spacer(minLength: 0)
        }
    }

    private func calloutRow(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.etch(size: 12, weight: .semibold)).tracking(3)
                .foregroundStyle(accent)
            Text(value)
                .font(.etch(size: 24, weight: .bold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail.uppercased())
                .font(.etch(size: 11, weight: .medium)).tracking(1.2)
                .foregroundStyle(subtle)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    /// Northernmost to southernmost — the year's reach, phrased as a distance.
    private func northSouthRange(places: [RunStatistics.TravelPlace])
        -> (value: String, detail: String)? {
        guard places.count > 1,
              let north = places.max(by: { $0.coordinate.latitude < $1.coordinate.latitude }),
              let south = places.min(by: { $0.coordinate.latitude < $1.coordinate.latitude }),
              north.id != south.id else { return nil }
        let meters = CLLocation(latitude: north.coordinate.latitude,
                                longitude: north.coordinate.longitude)
            .distance(from: CLLocation(latitude: south.coordinate.latitude,
                                       longitude: south.coordinate.longitude))
        // A span under ~30 miles is one metro area, not a story.
        guard meters > 48_000 else { return nil }
        let span = Format.distanceValue(meters).formatted(.number.precision(.fractionLength(0)))
        return ("\(span) \(UnitSystem.current.label.uppercased())",
                "\(cityName(north)) TO \(cityName(south))")
    }

    /// "Phoenix, Arizona, United States" → "Phoenix".
    private func cityName(_ place: RunStatistics.TravelPlace) -> String {
        place.label.components(separatedBy: ", ").first ?? place.label
    }

    // MARK: Derivations

    /// Display-unit distance per visited US state, keyed by the boundary's own name so the
    /// figure and the callouts agree on what "visited" means.
    var mapStateMiles: [String: Double] {
        let names = Set(USStateBoundaries.shared.boundaries.map(\.name))
        var miles: [String: Double] = [:]
        for run in plan.runs {
            guard let state = PlaceNames.canonicalState(run.state), names.contains(state) else { continue }
            miles[state, default: 0] += Format.distanceValue(run.distance)
        }
        return miles
    }

    /// Projects the visited world into normalized figure space (0…1, y down). Framed to the
    /// visited states plus every dot and star, padded; unvisited states that fall inside the
    /// frame come along as hairlines.
    private func mapFigure(stateMiles: [String: Double],
                           places: [RunStatistics.TravelPlace],
                           races: [CLLocationCoordinate2D]) -> BookMapFigure? {
        let boundaries = USStateBoundaries.shared.boundaries
        var frame = boundaries
            .filter { stateMiles[$0.name] != nil }
            .reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        guard !frame.isNull else { return nil }
        for coordinate in places.map(\.coordinate) + races {
            frame = frame.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize()))
        }
        frame = frame.insetBy(dx: -frame.width * 0.07, dy: -frame.height * 0.10)

        func normalized(_ p: MKMapPoint) -> CGPoint {
            CGPoint(x: (p.x - frame.minX) / frame.width,
                    y: (p.y - frame.minY) / frame.height)
        }

        // Tint by tercile of the state's mileage — three steps, not a continuous ramp, so
        // adjacent states read as bands rather than as barely-different washes.
        let ranked = stateMiles.values.sorted()
        func tint(for name: String) -> Double? {
            guard let value = stateMiles[name] else { return nil }
            guard ranked.count > 1 else { return 1 }
            let position = Double(ranked.firstIndex(of: value) ?? 0) / Double(ranked.count - 1)
            return position < 0.34 ? 0 : position < 0.67 ? 0.5 : 1
        }

        var states: [BookMapFigure.StateShape] = []
        for boundary in boundaries {
            // Skip states entirely outside the frame — no point building their paths.
            guard boundary.boundingMapRect.intersects(frame) else { continue }
            var rings: [[CGPoint]] = []
            for polygon in boundary.polygons {
                let pts = polygon.points()
                var ring: [CGPoint] = []
                ring.reserveCapacity(polygon.pointCount)
                for i in 0..<polygon.pointCount { ring.append(normalized(pts[i])) }
                rings.append(ring)
            }
            states.append(.init(rings: rings, tint: tint(for: boundary.name)))
        }

        let cities = places.map { place -> (point: CGPoint, weight: CGFloat) in
            let weight = min(12, 4 + CGFloat(Double(place.runs.count).squareRoot()) * 1.6)
            return (normalized(MKMapPoint(place.coordinate)), weight)
        }
        let raceMarks = races.map { normalized(MKMapPoint($0)) }

        return BookMapFigure(states: states, cities: cities, races: raceMarks,
                             aspect: frame.width / frame.height)
    }

    private func starPath(center: CGPoint, radius: CGFloat) -> Path {
        StarShape.path(center: center, radius: radius)
    }
}

/// The projected figure, ready to draw: everything in normalized 0…1 coordinates.
struct BookMapFigure {
    struct StateShape {
        let rings: [[CGPoint]]
        /// nil = unvisited (hairline only); 0…1 = tercile band of the state's mileage.
        let tint: Double?
    }
    let states: [StateShape]
    let cities: [(point: CGPoint, weight: CGFloat)]
    let races: [CGPoint]
    /// Width over height of the framed map space, for aspect-preserving fit.
    let aspect: CGFloat
}

/// A five-point star, for race days on the map and its legend.
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Self.path(center: CGPoint(x: rect.midX, y: rect.midY),
                  radius: min(rect.width, rect.height) / 2)
    }

    static func path(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let inner = radius * 0.42
        for i in 0..<10 {
            let angle = (Double(i) * .pi / 5) - .pi / 2
            let r = i.isMultiple(of: 2) ? radius : inner
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
