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
        let workouts = try await runningWorkouts(since: since)
        var results: [ImportedActivity] = []
        results.reserveCapacity(workouts.count)
        for workout in workouts {
            let coordinates = (try? await route(for: workout)) ?? []
            HealthKitLog.route("Imported workout \(workout.uuid) — \(coordinates.count) route points")
            results.append(makeActivity(from: workout, coordinates: coordinates))
        }
        return results
    }

    // MARK: Single-workout route recovery

    /// Re-queries HealthKit for the route of a workout we've already imported, identified by
    /// its UUID. Used by the backfill / anchored-query recovery paths to attach routes that
    /// arrived after the workout.
    ///
    /// - Returns: `nil` when the workout itself can't be located (transient — leave state
    ///   untouched and retry later); an empty array when the workout exists but still has no
    ///   route (pending / unavailable); coordinates when a route is now present.
    func recoverRoute(forWorkoutUUID uuidString: String) async -> [CLLocationCoordinate2D]? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        HealthKitLog.route("Searching for route for workout \(uuidString)")
        guard let workout = await workout(uuid: uuid) else {
            HealthKitLog.route("Workout \(uuidString) not found in HealthKit")
            return nil
        }
        let coordinates = (try? await route(for: workout)) ?? []
        if coordinates.isEmpty {
            HealthKitLog.route("No route available yet for workout \(uuidString)")
        } else {
            HealthKitLog.route("Recovered route for workout \(uuidString) — \(coordinates.count) points")
        }
        return coordinates
    }

    /// Fetches a single workout by its HealthKit UUID.
    private func workout(uuid: UUID) async -> HKWorkout? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: uuid)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout])?.first)
            }
            store.execute(query)
        }
    }

    // MARK: Workout query

    private func runningWorkouts(since: Date?) async throws -> [HKWorkout] {
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        var predicates: [NSPredicate] = [runningPredicate]
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

    private func route(for workout: HKWorkout) async throws -> [CLLocationCoordinate2D] {
        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: routePredicate,
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

        // A workout may expose its GPS trace as several route objects; stitch them together
        // in chronological order so the combined line reads start-to-finish.
        let orderedRoutes = routes.sorted { $0.startDate < $1.startDate }
        var coordinates: [CLLocationCoordinate2D] = []
        for route in orderedRoutes {
            let locations = try await locations(for: route)
            for location in locations {
                let coordinate = location.coordinate
                // Skip a point identical to the immediately preceding one (chunk seams can
                // repeat a sample); keeps geometry clean without dropping real detail.
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
        activity.endDate = workout.endDate
        activity.elevationGain = elevation(of: workout)
        activity.activeEnergy = energy(of: workout)
        activity.averageHeartRate = heartRate(of: workout, .discreteAverage)
        activity.maxHeartRate = heartRate(of: workout, .discreteMax)
        activity.averageCadence = cadence(of: workout)
        activity.sportType = "Run"
        activity.name = workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String
        return activity
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
