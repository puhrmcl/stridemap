import Foundation
import HealthKit
import CoreLocation

/// Primary `ActivityProvider` backed by Apple Health. Reads running workouts written by
/// *any* app (Apple Workouts, Nike Run Club, Strava, Garmin, COROS, …), along with their
/// GPS routes and available metrics, and normalises them into `ImportedActivity`.
@MainActor
final class HealthKitProvider: ActivityProvider {

    let store: HKHealthStore
    let source: ActivitySource = .healthKit
    let role: ProviderRole = .primary

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    init(store: HKHealthStore) {
        self.store = store
    }

    func fetchActivities(since: Date?) async throws -> [ImportedActivity] {
        // Metadata only. Routes are hydrated separately (`routeStream`) so a large first
        // import isn't blocked fetching a GPS trace for every workout before any run appears.
        let workouts = try await runningWorkouts(since: since)
        return workouts.map { makeActivity(from: $0, coordinates: []) }
    }

    /// Diagnostic summary: total workouts of *any* type vs. running workouts. Distinguishes
    /// "no read permission / no data" (0 workouts) from "workouts exist but none are typed as
    /// runs" (>0 workouts, 0 runs) — the two reasons an import can find nothing.
    func workoutSummary() async -> String {
        let all = await allWorkouts()
        let running = all.reduce(0) { $0 + ($1.workoutActivityType == .running ? 1 : 0) }
        let hiking = all.reduce(0) { $0 + ($1.workoutActivityType == .hiking ? 1 : 0) }
        let walking = all.reduce(0) { $0 + ($1.workoutActivityType == .walking ? 1 : 0) }
        return "\(all.count) workouts · \(running) runs · \(hiking) hikes · \(walking) walks"
    }

    private func allWorkouts() async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: Route hydration

    /// The result of trying to fetch a workout's GPS route — kept distinct so callers (and
    /// logs) can tell "the source wrote no route" from "the query failed".
    enum RouteOutcome: Sendable {
        case coordinates([CLLocationCoordinate2D]) // route present
        case noRoute                                // 0 HKWorkoutRoute objects (Scenario B)
        case failed                                 // query errored (Scenario C)
    }

    /// Streams route outcomes for already-imported workouts one at a time: a single workout
    /// query (bounded to `since`), then a route query per matched workout, yielding as each
    /// resolves. Keeps `HKWorkout` (non-Sendable) inside the provider and hands out only
    /// Sendable values, so the caller can attach and save progressively.
    func routeStream(
        forWorkoutUUIDs uuids: Set<String>,
        since: Date?
    ) -> AsyncStream<(id: String, outcome: RouteOutcome)> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let workouts = (try? await runningWorkouts(since: since)) ?? []
                for workout in workouts {
                    if Task.isCancelled { break }
                    let key = workout.uuid.uuidString
                    guard uuids.contains(key) else { continue }
                    let outcome = await routeOutcome(for: workout)
                    continuation.yield((id: key, outcome: outcome))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Fetches a workout's route and logs a one-line DEBUG diagnostic identifying the source
    /// (name + bundle id), sizes, and the outcome — so device logs make it obvious whether a
    /// missing map is the source writing no route vs. Etch failing to read one.
    func routeOutcome(for workout: HKWorkout) async -> RouteOutcome {
        let source = workout.sourceRevision.source
        let base = "[Etch HealthKit] \(workout.uuid.uuidString.prefix(8))"
            + " src=\"\(source.name)\" [\(source.bundleIdentifier)]"
            + " \(Int(distance(of: workout)))m/\(Int(workout.duration))s"
        do {
            let samples = try await routeSamples(for: workout)
            guard !samples.isEmpty else {
                HealthKitLog.route("\(base) routes=0 gps=0 status=NO_ROUTE_IN_HEALTHKIT")
                return .noRoute
            }
            let coordinates = try await coordinates(from: samples)
            guard !coordinates.isEmpty else {
                HealthKitLog.route("\(base) routes=\(samples.count) gps=0 status=ROUTE_OBJECT_EMPTY")
                return .noRoute
            }
            HealthKitLog.route("\(base) routes=\(samples.count) gps=\(coordinates.count)"
                + " first=\(format(coordinates.first)) last=\(format(coordinates.last)) status=SUCCESS")
            return .coordinates(coordinates)
        } catch {
            HealthKitLog.route("\(base) routes=? gps=0 status=QUERY_FAILURE error=\(error.localizedDescription)")
            return .failed
        }
    }

    private func format(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "-" }
        return String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: Workout query

    /// The activity types we ingest from Apple Health. Running always; hiking unless turned off;
    /// walking only when opted in (Apple Watch auto-logs many short walks, so it's off by default).
    private static var importedWorkoutTypes: [HKWorkoutActivityType] {
        var types: [HKWorkoutActivityType] = [.running]
        if ActivitySettings.includeHikes { types.append(.hiking) }
        if ActivitySettings.includeWalks { types.append(.walking) }
        return types
    }

    private func runningWorkouts(since: Date?) async throws -> [HKWorkout] {
        let typePredicate = NSCompoundPredicate(orPredicateWithSubpredicates:
            Self.importedWorkoutTypes.map { HKQuery.predicateForWorkouts(with: $0) })
        var predicates: [NSPredicate] = [typePredicate]
        if let since {
            predicates.append(HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    // MARK: Route query

    /// The `HKWorkoutRoute` series samples attached to a workout (usually 0 or 1, sometimes
    /// several). An empty result means the source wrote no route.
    private func routeSamples(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// Enumerates the `CLLocation`s of one or more route samples into a clean coordinate
    /// list: chronological across samples, adjacent duplicates dropped, order preserved.
    private func coordinates(from routes: [HKWorkoutRoute]) async throws -> [CLLocationCoordinate2D] {
        let orderedRoutes = routes.sorted { $0.startDate < $1.startDate }
        var coordinates: [CLLocationCoordinate2D] = []
        for route in orderedRoutes {
            let locations = try await locations(for: route)
            for location in locations {
                let coordinate = location.coordinate
                if let last = coordinates.last,
                   last.latitude == coordinate.latitude, last.longitude == coordinate.longitude {
                    continue
                }
                coordinates.append(coordinate)
            }
        }
        return coordinates
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var collected: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let locations {
                    collected.append(contentsOf: locations)
                }
                if done {
                    continuation.resume(returning: collected)
                }
            }
            store.execute(query)
        }
    }

    // MARK: Mapping

    /// Maps a HealthKit workout type to our normalized activity type. We import running and
    /// hiking; anything else (shouldn't occur given the query) falls back to run.
    private static func activityType(for type: HKWorkoutActivityType) -> ActivityType {
        switch type {
        case .running: return .run
        case .hiking:  return .hike
        case .walking: return .walk
        default:       return .run
        }
    }

    private func makeActivity(from workout: HKWorkout, coordinates: [CLLocationCoordinate2D]) -> ImportedActivity {
        let sourceName = workout.sourceRevision.source.name
        let origin = ActivitySource.detect(fromSourceName: sourceName)

        var activity = ImportedActivity(
            provider: .healthKit,
            externalID: workout.uuid.uuidString,
            startDate: workout.startDate,
            distance: distance(of: workout),
            movingTime: Int(workout.duration),
            elapsedTime: Int(workout.endDate.timeIntervalSince(workout.startDate)),
            coordinates: coordinates
        )
        activity.originApp = origin
        activity.importMethod = .healthKit
        activity.endDate = workout.endDate
        activity.elevationGain = elevation(of: workout)
        activity.activeEnergy = energy(of: workout)
        activity.averageHeartRate = heartRate(of: workout, .discreteAverage)
        activity.maxHeartRate = heartRate(of: workout, .discreteMax)
        activity.averageCadence = cadence(of: workout)
        let kind = Self.activityType(for: workout.workoutActivityType)
        activity.activityType = kind
        activity.sportType = kind.rawValue.capitalized   // "Run" / "Hike"
        // Treadmill / indoor: Apple Health flags these; they carry no GPS route.
        activity.isIndoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue
        activity.name = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String
        applyWeather(from: workout, to: &activity)
        return activity
    }

    /// Reads the optional weather Apple Health stores on a workout (temperature + condition).
    private func applyWeather(from workout: HKWorkout, to activity: inout ImportedActivity) {
        if let temp = workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity {
            activity.weatherTemperatureC = temp.doubleValue(for: .degreeCelsius())
        }
        if let raw = workout.metadata?[HKMetadataKeyWeatherCondition] as? NSNumber,
           let condition = WeatherCondition.fromHealthKit(raw.intValue) {
            activity.weatherCondition = condition.rawValue
        }
    }

    private func distance(of workout: HKWorkout) -> Double {
        if let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
           let sum = workout.statistics(for: type)?.sumQuantity() {
            return sum.doubleValue(for: .meter())
        }
        // Many third-party apps populate the workout's total rather than per-quantity
        // statistics; fall back to it so their runs still carry a distance.
        return workout.totalDistance?.doubleValue(for: .meter()) ?? 0
    }

    private func elevation(of workout: HKWorkout) -> Double? {
        guard let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity else {
            return nil
        }
        return quantity.doubleValue(for: .meter())
    }

    private func energy(of workout: HKWorkout) -> Double? {
        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let sum = workout.statistics(for: type)?.sumQuantity() {
            return sum.doubleValue(for: .kilocalorie())
        }
        return workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
    }

    private func heartRate(of workout: HKWorkout, _ option: HKStatisticsOptions) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let stats = workout.statistics(for: type) else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let quantity = option == .discreteMax ? stats.maximumQuantity() : stats.averageQuantity()
        return quantity?.doubleValue(for: unit)
    }

    /// Average cadence in steps/minute, derived from total step count over the workout.
    private func cadence(of workout: HKWorkout) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        let steps = sum.doubleValue(for: .count())
        let minutes = workout.duration / 60
        guard minutes > 0 else { return nil }
        return steps / minutes
    }
}
