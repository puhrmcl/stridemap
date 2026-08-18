import Foundation
import CoreLocation

/// Pure, derived analytics computed from a set of runs. Powers Highlights, Year in Review,
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

    /// The fastest recorded top speed across these runs (metres/second), when any source supplied
    /// one (Strava `max_speed`, TCX `MaximumSpeed`). Nil when none of the runs carry it.
    var topSpeed: Double? { runs.compactMap(\.maxSpeed).max() }

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
                // Distance-time benchmarks (5K / 10K / Marathon…) are foot-running events, so a
                // ride at ~26 mi never sets the "Marathon" PR (cycling speeds can slip past the
                // plausibility cap otherwise).
                $0.activityType == .run
                    && $0.movingTime > 0 && $0.distance >= lo && $0.distance <= hi && isPlausibleSpeed($0)
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

    // MARK: Milestones

    /// Runs that count as milestones — the marquee superlatives (furthest, longest, fastest,
    /// highest climb) plus every distance PR. Drives the gold trophy pin on the map and the
    /// milestone badge in run detail, so both agree.
    /// The runs that *currently* hold a record — the marquee superlatives (furthest, longest,
    /// fastest, highest climb) and the benchmark-distance bests (5K, 10K, Marathon, …). One run per
    /// achievement, so the map shows a single milestone pin per record rather than stamping a gold
    /// trophy on every run that ever set a distance progression (which piled up duplicates of the
    /// same kind). `prRunIDs` still powers the PRs map mode, which deliberately shows the full
    /// progression.
    var milestoneRunIDs: Set<UUID> {
        var ids: Set<UUID> = []
        for run in [longestRun, longestDurationRun, fastestRun] {
            if let run { ids.insert(run.id) }
        }
        if let climb = highestClimb, climb.elevationGain > 0 { ids.insert(climb.id) }
        for pr in personalRecords { ids.insert(pr.run.id) }
        return ids
    }

    /// Human labels for the specific milestones a run holds within this set — e.g.
    /// ["Furthest run", "Fastest pace", "5K best"]. Empty when the run holds none. Covers every
    /// reason `milestoneRunIDs` would include the run, so run detail can say *what* the milestone is
    /// rather than just that there is one.
    func milestoneLabels(for run: Run) -> [String] {
        let noun = run.activityType.detailLabel.lowercased()
        var labels: [String] = []
        if longestRun?.id == run.id { labels.append("Furthest \(noun)") }
        if longestDurationRun?.id == run.id { labels.append("Longest time") }
        if fastestRun?.id == run.id { labels.append("Fastest pace") }
        if highestClimb?.id == run.id, run.elevationGain > 0 { labels.append("Most climbing") }
        for pr in personalRecords where pr.run.id == run.id {
            labels.append("\(pr.label) best")
        }
        return labels
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
        // Identity includes the coordinate so two places that share a label (e.g. two landmarks
        // in the same city) stay distinct in lists and on the map.
        var id: String { "\(label)#\(Int(coordinate.latitude * 1000))_\(Int(coordinate.longitude * 1000))" }
        var label: String
        var coordinate: CLLocationCoordinate2D
        var runs: [Run]
        var totalDistance: Double { runs.reduce(0) { $0 + $1.distance } }
    }

    /// One pin per city, positioned at the average start coordinate of its runs.
    var travelPlaces: [TravelPlace] {
        placesGrouped(by: { [$0.city, $0.state, $0.country].compactMap { $0 }.joined(separator: ", ") },
                      include: { $0.city?.isEmpty == false })
    }

    /// One pin per country, at the average start coordinate of that country's runs.
    var countryPlaces: [TravelPlace] {
        placesGrouped(by: { $0.country ?? "" }, include: { $0.country?.isEmpty == false })
    }

    /// Runs that started at or next to a real point of interest — a park, university, museum,
    /// and so on — grouped by that landmark. Populated by `SyncService.detectLandmarks`.
    var landmarkPlaces: [TravelPlace] {
        placesGrouped(by: { $0.landmarkName ?? "" }, include: { $0.landmarkName?.isEmpty == false })
    }

    /// Groups located runs by a label key into pins at each group's average start coordinate.
    private func placesGrouped(by key: (Run) -> String, include: (Run) -> Bool) -> [TravelPlace] {
        let groups = Dictionary(grouping: runs.filter { include($0) && $0.startCoordinate != nil }, by: key)
        return groups.compactMap { label, runs -> TravelPlace? in
            guard !label.isEmpty else { return nil }
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
