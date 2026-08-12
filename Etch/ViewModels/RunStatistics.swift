import Foundation
import CoreLocation

/// Pure, derived analytics computed from a set of runs. Powers Explore, Year in Review,
/// Travel, and the floating totals. Cheap enough to recompute on demand; callers cache
/// where it matters.
struct RunStatistics {

    let runs: [Run]

    init(_ runs: [Run]) {
        self.runs = runs
    }

    // MARK: Totals

    var totalRuns: Int { runs.count }
    var totalDistanceMeters: Double { runs.reduce(0) { $0 + $1.distance } }
    var totalElevationMeters: Double { runs.reduce(0) { $0 + $1.elevationGain } }
    var totalMovingTime: Int { runs.reduce(0) { $0 + $1.movingTime } }

    // MARK: Geography

    var cities: [String] { unique(runs.compactMap(\.city)) }
    var states: [String] { unique(runs.compactMap(\.state)) }
    var countries: [String] { unique(runs.compactMap(\.country)) }

    private func unique(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.isEmpty })).sorted()
    }

    // MARK: Superlatives

    /// Furthest by distance (the "most miles" run).
    var longestRun: Run? { runs.max { $0.distance < $1.distance } }
    /// Longest by elapsed effort (the "most time on feet" run).
    var longestDurationRun: Run? { runs.max { $0.movingTime < $1.movingTime } }
    var highestClimb: Run? { runs.max { $0.elevationGain < $1.elevationGain } }
    var fastestRun: Run? {
        runs.filter { $0.distance > 1000 && isPlausibleSpeed($0) }
            .min { $0.paceSecondsPerKm < $1.paceSecondsPerKm }
    }

    /// Rejects runs whose average speed exceeds elite pace — those are bad GPS/short-run data
    /// artifacts (e.g. a "0:30 /mi" record), not real efforts.
    private func isPlausibleSpeed(_ run: Run) -> Bool {
        guard run.movingTime > 0 else { return false }
        return run.distance / Double(run.movingTime) <= 6.5   // m/s (~2:33/km, faster than elite)
    }

    // MARK: Distance personal bests

    /// A best time at (approximately) a benchmark distance.
    struct DistancePR: Identifiable {
        let label: String
        let meters: Double
        let run: Run
        var id: String { label }
        var time: Int { run.movingTime }
    }

    private static let prBenchmarks: [(String, Double)] = [
        ("1K", 1_000), ("1 Mile", 1_609.34), ("5K", 5_000), ("10K", 10_000),
        ("Half Marathon", 21_097.5), ("Marathon", 42_195)
    ]

    /// Your fastest actual run at each benchmark distance (within a tolerance band), by moving
    /// time. Note: this is a whole-run best at ~that distance — not a rolling best-effort split
    /// within a longer run (which would need per-point timing we don't store).
    var personalRecords: [DistancePR] {
        Self.prBenchmarks.compactMap { name, meters in
            let lo = meters * 0.98, hi = meters * 1.10
            let best = runs.filter {
                $0.movingTime > 0 && $0.distance >= lo && $0.distance <= hi && isPlausibleSpeed($0)
            }.min { $0.movingTime < $1.movingTime }
            return best.map { DistancePR(label: name, meters: meters, run: $0) }
        }
    }

    var northernmostRun: Run? { runs.max { ($0.startLatitude ?? -91) < ($1.startLatitude ?? -91) } }
    var southernmostRun: Run? { runs.min { ($0.startLatitude ?? 91) < ($1.startLatitude ?? 91) } }

    /// Runs grouped by a coarse start location, used to find the "most visited route".
    var mostVisitedArea: (label: String, count: Int)? {
        let groups = Dictionary(grouping: runs.filter { $0.startCoordinate != nil }) {
            geohashLabel($0)
        }
        guard let best = groups.max(by: { $0.value.count < $1.value.count }) else { return nil }
        let label = best.value.first?.placeLabel.isEmpty == false
            ? best.value.first!.placeLabel
            : "Local loop"
        return (label, best.value.count)
    }

    /// Buckets a run's start into a ~1km grid cell so nearby starts cluster together.
    private func geohashLabel(_ run: Run) -> String {
        guard let c = run.startCoordinate else { return "?" }
        let lat = (c.latitude * 100).rounded() / 100
        let lon = (c.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }

    // MARK: Personal records (PRs)

    /// Activity ids that set a new all-time longest-distance record when they happened.
    /// A run is a "PR" if, in chronological order, it exceeded every prior run's distance.
    var prRunIDs: Set<UUID> {
        var best = 0.0
        var ids: Set<UUID> = []
        for run in runs.sorted(by: { $0.startDate < $1.startDate }) {
            if run.distance > best {
                best = run.distance
                ids.insert(run.id)
            }
        }
        return ids
    }

    // MARK: Travel pins

    struct TravelPlace: Identifiable {
        var id: String { label }
        var label: String
        var coordinate: CLLocationCoordinate2D
        var runs: [Run]
        var totalDistance: Double { runs.reduce(0) { $0 + $1.distance } }
    }

    /// One pin per city, positioned at the average start coordinate of its runs.
    var travelPlaces: [TravelPlace] {
        let groups = Dictionary(grouping: runs.filter { $0.city?.isEmpty == false && $0.startCoordinate != nil }) {
            [$0.city, $0.state, $0.country].compactMap { $0 }.joined(separator: ", ")
        }
        return groups.compactMap { label, runs in
            let coords = runs.compactMap(\.startCoordinate)
            guard !coords.isEmpty else { return nil }
            let lat = coords.map(\.latitude).reduce(0, +) / Double(coords.count)
            let lon = coords.map(\.longitude).reduce(0, +) / Double(coords.count)
            return TravelPlace(
                label: label,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                runs: runs.sorted { $0.startDate > $1.startDate }
            )
        }
        .sorted { $0.runs.count > $1.runs.count }
    }

    // MARK: Timeline grouping

    struct MonthGroup: Identifiable {
        var id: String { "\(year)-\(month)" }
        var year: Int
        var month: Int
        var date: Date
        var runs: [Run]
        var totalDistance: Double { runs.reduce(0) { $0 + $1.distance } }
    }

    /// Runs grouped by month, newest first — the timeline data source.
    var monthGroups: [MonthGroup] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: runs) { run -> DateComponents in
            cal.dateComponents([.year, .month], from: run.startDate)
        }
        return groups.compactMap { comps, runs in
            guard let year = comps.year, let month = comps.month,
                  let date = cal.date(from: comps) else { return nil }
            return MonthGroup(
                year: year, month: month, date: date,
                runs: runs.sorted { $0.startDate > $1.startDate }
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Distinct years represented, newest first — used for year filters & recaps.
    var years: [Int] {
        let cal = Calendar.current
        return Array(Set(runs.map { cal.component(.year, from: $0.startDate) }))
            .sorted(by: >)
    }

    func statistics(forYear year: Int) -> RunStatistics {
        let cal = Calendar.current
        return RunStatistics(runs.filter { cal.component(.year, from: $0.startDate) == year })
    }
}
