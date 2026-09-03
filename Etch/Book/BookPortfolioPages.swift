import SwiftUI
import MapKit

/// The portfolio pages — the book's closing act. After the review has said what the span
/// meant, these place it inside a life: every year on record, the résumé of start lines,
/// and everywhere the whole history has ever been. All three read `plan.history`, not
/// `plan.runs` — the point is the career, not the covers' span.
extension BookPageView {

    // MARK: THE YEARS — every year on record

    var yearsPage: some View {
        let calendar = Calendar.current
        let byYear = Dictionary(grouping: plan.history) {
            calendar.component(.year, from: $0.startDate)
        }
        let years = byYear.keys.sorted()
        let subjectYears = Set(plan.runs.map { calendar.component(.year, from: $0.startDate) })
        let unit = UnitSystem.current.label.uppercased()

        return VStack(spacing: 36) {
            pageHeader("THE RECORD SO FAR", subtitle: "THE YEARS")

            VStack(spacing: 0) {
                // The ledger's column heads, once.
                HStack {
                    Text("YEAR").frame(width: 130, alignment: .leading)
                    Spacer()
                    Text("ACTIVITIES").frame(width: 150, alignment: .trailing)
                    Text(unit).frame(width: 130, alignment: .trailing)
                    Text("RACES").frame(width: 110, alignment: .trailing)
                    Text("STATES").frame(width: 110, alignment: .trailing)
                }
                .font(.etch(size: 11.5, weight: .semibold)).tracking(2)
                .foregroundStyle(subtle)
                .padding(.bottom, 12)
                Rectangle().fill(subtle.opacity(0.35)).frame(height: 1.5)

                ForEach(years.suffix(12), id: \.self) { year in
                    let runs = byYear[year] ?? []
                    let miles = Format.distanceValue(runs.reduce(0.0) { $0 + $1.distance })
                        .formatted(.number.precision(.fractionLength(0)))
                    let states = Set(runs.compactMap { PlaceNames.canonicalState($0.state) }
                        .filter { !$0.isEmpty }).count
                    let isSubject = subjectYears.contains(year)

                    HStack {
                        Text(String(year))
                            .font(.etchSerif(size: 26, weight: .regular)).tracking(1)
                            .foregroundStyle(isSubject ? accent : ink)
                            .frame(width: 130, alignment: .leading)
                        if isSubject {
                            Text("THIS BOOK")
                                .font(.etch(size: 10, weight: .semibold)).tracking(2.5)
                                .foregroundStyle(accent)
                        }
                        Spacer()
                        Text(runs.count.formatted()).frame(width: 150, alignment: .trailing)
                        Text(miles).frame(width: 130, alignment: .trailing)
                        Text("\(runs.filter(\.isRace).count)").frame(width: 110, alignment: .trailing)
                        Text("\(states)").frame(width: 110, alignment: .trailing)
                    }
                    .font(.etch(size: 17, weight: .semibold))
                    .foregroundStyle(isSubject ? accent : ink)
                    .monospacedDigit()
                    .padding(.vertical, 13)

                    Rectangle().fill(subtle.opacity(0.16)).frame(height: 1)
                }
            }
            Spacer(minLength: 0)

            // The lifetime line under the ledger.
            let lifetimeMiles = Format.distanceValue(plan.history.reduce(0.0) { $0 + $1.distance })
                .formatted(.number.precision(.fractionLength(0)))
            Text("\(plan.history.count.formatted()) ACTIVITIES · \(lifetimeMiles) \(unit) · SINCE \(years.first.map(String.init) ?? "")")
                .font(.etch(size: 14, weight: .semibold)).tracking(3)
                .foregroundStyle(subtle)
        }
        .padding(margin)
    }

    // MARK: RACE HISTORY — the résumé of start lines

    var raceHistoryPage: some View {
        let races = plan.history.filter(\.isRace).sorted { $0.startDate > $1.startDate }
        let shown = Array(races.prefix(14))
        let unshown = races.count - shown.count

        return VStack(spacing: 30) {
            pageHeader("EVERY START LINE", subtitle: "RACE HISTORY")

            VStack(spacing: 0) {
                ForEach(shown, id: \.id) { race in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(raceDate(race.startDate))
                            .font(.etch(size: 12, weight: .semibold)).tracking(1.5)
                            .foregroundStyle(subtle)
                            .frame(width: 120, alignment: .leading)
                        Text(race.name.uppercased())
                            .font(.etch(size: 15, weight: .semibold)).tracking(1)
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 10)
                        if !race.finishPlace.isEmpty {
                            Text("№ \(race.finishPlace)")
                                .font(.etch(size: 13, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        Text(StatMetric.distance.value(for: race) ?? "")
                            .font(.etch(size: 14, weight: .medium))
                            .foregroundStyle(subtle)
                            .frame(width: 110, alignment: .trailing)
                        Text(StatMetric.time.value(for: race) ?? "")
                            .font(.etch(size: 15, weight: .bold))
                            .foregroundStyle(ink)
                            .monospacedDigit()
                            .frame(width: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    Rectangle().fill(subtle.opacity(0.16)).frame(height: 1)
                }
            }
            Spacer(minLength: 0)
            if unshown > 0 {
                Text("+ \(unshown) MORE START \(unshown == 1 ? "LINE" : "LINES") BEFORE THESE")
                    .font(.etch(size: 11.5, weight: .semibold)).tracking(2.5)
                    .foregroundStyle(subtle)
            }
        }
        .padding(margin)
    }

    private func raceDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date).uppercased()
    }

    // MARK: THE ATLAS — everywhere, ever

    var atlasPage: some View {
        let stats = RunStatistics(plan.history)
        let places = stats.travelPlaces
        let figure = atlasFigure(places: places)

        let countries = Set(places.compactMap {
            WorldCountryBoundaries.shared.region(containing: $0.coordinate)
        })
        let states = Set(plan.history.compactMap { PlaceNames.canonicalState($0.state) }
            .filter { !$0.isEmpty })
        let miles = Format.distanceValue(plan.history.reduce(0.0) { $0 + $1.distance })
            .formatted(.number.precision(.fractionLength(0)))

        return VStack(spacing: 30) {
            pageHeader("EVERYWHERE, EVER", subtitle: "THE ATLAS")

            if let figure {
                atlasCanvas(figure)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // The lifetime line: what all the pins add up to.
            HStack(spacing: 30) {
                atlasStat("\(places.count)", places.count == 1 ? "CITY" : "CITIES")
                atlasStat("\(states.count)", states.count == 1 ? "STATE" : "STATES")
                if countries.count > 1 { atlasStat("\(countries.count)", "COUNTRIES") }
                atlasStat(miles, UnitSystem.current.label.uppercased())
            }
        }
        .padding(margin)
    }

    private func atlasStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(value)
                .font(.etch(size: 22, weight: .bold))
                .foregroundStyle(ink)
                .monospacedDigit()
            Text(label)
                .font(.etch(size: 12, weight: .semibold)).tracking(2.5)
                .foregroundStyle(subtle)
        }
    }

    private func atlasCanvas(_ figure: BookMapFigure) -> some View {
        Canvas { context, size in
            let scale = min(size.width, size.height * figure.aspect)
            let drawn = CGSize(width: scale, height: scale / figure.aspect)
            let origin = CGPoint(x: (size.width - drawn.width) / 2,
                                 y: (size.height - drawn.height) / 2)
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + p.x * drawn.width, y: origin.y + p.y * drawn.height)
            }

            for shape in figure.states {
                var path = Path()
                for ring in shape.rings where ring.count > 2 {
                    path.move(to: point(ring[0]))
                    for p in ring.dropFirst() { path.addLine(to: point(p)) }
                    path.closeSubpath()
                }
                if shape.tint != nil {
                    context.fill(path, with: .color(accent.opacity(0.1)))
                    context.stroke(path, with: .color(accent.opacity(0.6)), lineWidth: 1.1)
                } else {
                    context.stroke(path, with: .color(subtle.opacity(0.35)), lineWidth: 0.7)
                }
            }
            for city in figure.cities {
                let c = point(city.point)
                let r = city.weight
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                             with: .color(ground.opacity(0.9)))
                context.fill(Path(ellipseIn: rect), with: .color(accent))
            }
        }
    }

    /// The world framed to where the history has actually been: visited countries carry a
    /// wash and their outline, neighbours inside the frame come along as hairlines, and every
    /// city ever gets an accent pin sized by how often it was run.
    private func atlasFigure(places: [RunStatistics.TravelPlace]) -> BookMapFigure? {
        guard !places.isEmpty else { return nil }
        let boundaries = WorldCountryBoundaries.shared.boundaries
        // Visited countries matched by the pins themselves (point-in-polygon), so the wash
        // always agrees with the boundary data's own names, however a run was geocoded.
        let visited = Set(places.compactMap {
            WorldCountryBoundaries.shared.region(containing: $0.coordinate)
        })

        var frame = boundaries
            .filter { visited.contains($0.name) }
            .reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        for place in places {
            frame = frame.union(MKMapRect(origin: MKMapPoint(place.coordinate), size: MKMapSize()))
        }
        guard !frame.isNull else { return nil }
        frame = frame.insetBy(dx: -frame.width * 0.06, dy: -frame.height * 0.10)

        func normalized(_ p: MKMapPoint) -> CGPoint {
            CGPoint(x: (p.x - frame.minX) / frame.width,
                    y: (p.y - frame.minY) / frame.height)
        }

        var shapes: [BookMapFigure.StateShape] = []
        for boundary in boundaries {
            guard boundary.boundingMapRect.intersects(frame) else { continue }
            var rings: [[CGPoint]] = []
            for polygon in boundary.polygons {
                let pts = polygon.points()
                var ring: [CGPoint] = []
                ring.reserveCapacity(polygon.pointCount)
                for i in 0..<polygon.pointCount { ring.append(normalized(pts[i])) }
                rings.append(ring)
            }
            shapes.append(.init(rings: rings, tint: visited.contains(boundary.name) ? 1 : nil))
        }

        let cities = places.map { place -> (point: CGPoint, weight: CGFloat) in
            let weight = min(10, 3.5 + CGFloat(Double(place.runs.count).squareRoot()) * 1.4)
            return (normalized(MKMapPoint(place.coordinate)), weight)
        }

        return BookMapFigure(states: shapes, cities: cities, races: [],
                             aspect: frame.width / frame.height)
    }
}
