import Foundation
import CoreLocation

/// Trips, and what makes an activity worth a bigger tile.
///
/// The Timeline answers *when* well and *where* not at all — there is not one reference to a city,
/// a region or a coordinate anywhere in it, in an app whose whole subject is maps. This supplies
/// the missing axis.
///
/// The insight is that a history of GPS activities knows something a photo library does not: when
/// you were somewhere you do not normally go. That is derivable, with no new input, no new
/// permission and no effort from the reader — and it is almost always the stretch of history worth
/// re-living, because it is where the photographs are.
///
/// All of it is pure: values in, values out, so the behavioural check drives the same functions
/// the Timeline draws from rather than a restatement of them.
enum TimelineJourneys {

    // MARK: Tuning
    //
    // Deliberately conservative. A false trip — "Scotland" for a long Sunday ride — is far worse
    // than a missed one: it puts a chapter heading on an ordinary week and the reader stops
    // trusting the whole section.

    /// How far from home an activity has to start before it counts as away. Comfortably beyond a
    /// long training ride from the door, short enough to catch a weekend two counties over.
    static let awayMetres: Double = 150_000

    /// A single activity this far out is a trip on its own — a destination race is still a trip
    /// even if you only ran once while you were there.
    static let farAloneMetres: Double = 300_000

    /// Days of quiet that still belong to the same trip. Most people do not move every day they
    /// are away, and a rest day should not split Scotland into two chapters.
    static let maxGapDays = 4

    // MARK: Home

    /// Where the reader's ordinary life happens.
    ///
    /// The busiest coarse cell, then the median inside it — not the mean of everything, which on a
    /// history split between two places lands in the sea between them and makes both of them look
    /// like trips.
    ///
    /// One known limit: this is a single home for the whole history, so activities before a house
    /// move are measured against the current one. That misreports an old life as travel. Living
    /// with it for now because the alternative — a home per period — needs a judgement about what
    /// counts as moving, and getting *that* wrong is worse.
    static func home(_ runs: [Run]) -> CLLocationCoordinate2D? {
        let starts = runs.compactMap(\.startCoordinate)
        guard !starts.isEmpty else { return nil }

        // ~0.5° — roughly 55 km of latitude, so one cell is "the area you live in".
        func cell(_ c: CLLocationCoordinate2D) -> String {
            "\(Int((c.latitude * 2).rounded()))_\(Int((c.longitude * 2).rounded()))"
        }
        let grouped = Dictionary(grouping: starts, by: cell)
        guard let busiest = grouped.max(by: { $0.value.count < $1.value.count })?.value,
              !busiest.isEmpty else { return nil }
        let lats = busiest.map(\.latitude).sorted()
        let lons = busiest.map(\.longitude).sorted()
        return CLLocationCoordinate2D(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
    }

    static func metres(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // MARK: Trips

    struct Trip: Identifiable, Equatable {
        /// Stable across rebuilds: the first activity's id. A UUID minted per detection would make
        /// every refresh a brand-new chapter as far as SwiftUI is concerned.
        let id: String
        let runs: [Run]
        /// Where it was — a country when abroad, otherwise the region or town.
        let title: String
        let start: Date
        let end: Date
        let distanceMetres: Double
        let photoCount: Int
        /// How far out the furthest activity started, for ordering and for the caption.
        let reachMetres: Double

        static func == (a: Trip, b: Trip) -> Bool {
            a.id == b.id && a.runs.count == b.runs.count && a.title == b.title
        }

        var days: Int {
            let calendar = Calendar.current
            let span = calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: start),
                                               to: calendar.startOfDay(for: end)).day ?? 0
            return max(1, span + 1)
        }

        /// "6 days · 4 activities · 38 photos" — the photo count only when there are any, because
        /// "0 photos" is a reproach rather than a fact.
        var subtitle: String {
            var parts = ["\(days) \(days == 1 ? "day" : "days")",
                         "\(runs.count) \(runs.count == 1 ? "activity" : "activities")"]
            if photoCount > 0 {
                parts.append("\(photoCount) \(photoCount == 1 ? "photo" : "photos")")
            }
            return parts.joined(separator: "  ·  ")
        }

        var dateLine: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM yyyy"
            let from = formatter.string(from: start)
            guard days > 1 else { return from }
            return "\(from) – \(formatter.string(from: end))"
        }

        /// Every mapped route in the trip, for the chapter's artwork.
        var routes: [[CLLocationCoordinate2D]] {
            runs.compactMap { $0.coordinates.count > 1 ? $0.coordinates : nil }
        }
    }

    /// The activities a trip may be built from: counted, visible, and actually located.
    private static func admitted(_ runs: [Run]) -> [Run] {
        runs.filter { !$0.isHidden && !$0.excludedFromTotals && $0.startCoordinate != nil }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Every trip in the history, oldest first — the order the Timeline reads in, which opens at
    /// its foot on the most recent thing.
    static func trips(in runs: [Run], calendar: Calendar = .current) -> [Trip] {
        let located = admitted(runs)
        guard located.count >= 2, let home = home(located) else { return [] }

        let homeCountry = dominantCountry(located.filter {
            guard let c = $0.startCoordinate else { return false }
            return metres(from: c, to: home) < awayMetres
        })

        // Consecutive away activities, split on a long enough quiet gap.
        var clusters: [[Run]] = []
        var current: [Run] = []
        for run in located {
            guard let coordinate = run.startCoordinate,
                  metres(from: coordinate, to: home) >= awayMetres else { continue }
            if let last = current.last {
                let gap = calendar.dateComponents([.day],
                                                  from: calendar.startOfDay(for: last.startDate),
                                                  to: calendar.startOfDay(for: run.startDate)).day ?? 0
                if gap > maxGapDays {
                    clusters.append(current)
                    current = []
                }
            }
            current.append(run)
        }
        if !current.isEmpty { clusters.append(current) }

        return clusters.compactMap { cluster -> Trip? in
            let reach = cluster.compactMap(\.startCoordinate)
                .map { metres(from: $0, to: home) }.max() ?? 0
            // Two activities away, or one far enough out that it cannot be anything else.
            guard cluster.count >= 2 || reach >= farAloneMetres else { return nil }
            guard let first = cluster.first, let last = cluster.last else { return nil }
            return Trip(
                id: "trip-\(first.id.uuidString)",
                runs: cluster,
                title: title(for: cluster, homeCountry: homeCountry),
                start: first.startDate,
                end: last.startDate,
                distanceMetres: cluster.reduce(0) { $0 + $1.distance },
                photoCount: cluster.reduce(0) { $0 + $1.photoReferences.count },
                reachMetres: reach
            )
        }
    }

    private static func dominantCountry(_ runs: [Run]) -> String? {
        dominant(runs.compactMap { PlaceNames.canonicalCountry($0.country) })
    }

    private static func dominant(_ values: [String]) -> String? {
        let cleaned = values.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for value in cleaned { counts[value, default: 0] += 1 }
        // Ties break alphabetically so the same history always names a place the same way.
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// What to call it. Abroad is named by the country — "Scotland" is the thing the reader
    /// remembers, not the town they happened to start in. At home it is the region, or the town
    /// when the whole trip sat in one.
    static func title(for cluster: [Run], homeCountry: String?) -> String {
        let country = dominantCountry(cluster)
        if let country, country != homeCountry { return country }

        let states = cluster.compactMap { PlaceNames.canonicalState($0.state) }.filter { !$0.isEmpty }
        let cities = cluster.compactMap(\.city).filter { !$0.isEmpty }
        if let city = dominant(cities), Set(cities).count == 1 {
            if let state = dominant(states), state != city { return "\(city), \(state)" }
            return city
        }
        if let state = dominant(states) { return state }
        if let city = dominant(cities) { return city }
        return country ?? "Away"
    }

    // MARK: Significance

    /// Why an activity is worth more room than its neighbours. Ordered: the first reason that
    /// applies is the one shown, so a race that is also a personal best reads as a race.
    enum Significance: Equatable {
        case race
        case personalBest
        case longest
        case photographed
        case ordinary

        var isFeatured: Bool { self != .ordinary }

        var label: String? {
            switch self {
            case .race:         return "Race"
            case .personalBest: return "Personal best"
            case .longest:      return "Longest"
            case .photographed: return nil
            case .ordinary:     return nil
            }
        }
    }

    /// Grades a set of activities against each other.
    ///
    /// The Timeline laid every activity out as the same square, which is the page asserting that a
    /// first marathon and a Tuesday shakeout matter equally. The signals to say otherwise were
    /// already computed elsewhere in the app and simply never reached this surface.
    static func significance(in runs: [Run]) -> [UUID: Significance] {
        guard !runs.isEmpty else { return [:] }
        let counted = runs.filter { !$0.excludedFromTotals }
        let bests = RunStatistics(counted).milestoneRunIDs
        let longest = counted.max { $0.distance < $1.distance }?.id

        var out: [UUID: Significance] = [:]
        for run in runs {
            if run.isRace {
                out[run.id] = .race
            } else if bests.contains(run.id) {
                out[run.id] = .personalBest
            } else if run.id == longest {
                out[run.id] = .longest
            } else if run.photoReferences.count >= 3 {
                out[run.id] = .photographed
            } else {
                out[run.id] = .ordinary
            }
        }
        return out
    }

    // MARK: Rows

    /// One band of the Timeline: a single activity given the full width, or a strip of three.
    ///
    /// SwiftUI's grids cannot span cells, so hierarchy is built out of rows instead. The effect is
    /// the one that matters: scanning a month, the eye lands on what was actually significant
    /// rather than sweeping a uniform wall.
    enum Row: Identifiable, Equatable {
        case hero(Run, Significance)
        case strip([Run])

        var id: String {
            switch self {
            case .hero(let run, _): return "hero-\(run.id.uuidString)"
            case .strip(let runs):  return "strip-" + (runs.first?.id.uuidString ?? "empty")
            }
        }

        static func == (a: Row, b: Row) -> Bool { a.id == b.id }
    }

    /// At most this many activities in a month get the full width. Beyond that the page is all
    /// hero and nothing is emphasised — a race-heavy month would otherwise become a list of
    /// full-width tiles with no rhythm at all.
    static let heroBudget = 3

    static func rows(for runs: [Run], significance: [UUID: Significance]) -> [Row] {
        var out: [Row] = []
        var buffer: [Run] = []
        var heroesUsed = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            out.append(.strip(buffer))
            buffer = []
        }

        for run in runs {
            let grade = significance[run.id] ?? .ordinary
            if grade.isFeatured && heroesUsed < heroBudget {
                flush()
                out.append(.hero(run, grade))
                heroesUsed += 1
            } else {
                buffer.append(run)
                if buffer.count == 3 { flush() }
            }
        }
        flush()
        return out
    }
}
