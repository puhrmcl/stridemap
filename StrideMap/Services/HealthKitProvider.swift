import Foundation
import HealthKit
import CoreLocation

/// Primary `ActivityProvider` backed by Apple Health. Reads running workouts written by
/// *any* app (Apple Workouts, Nike Run Club, Strava, Garmin, COROS, …), along with their
/// GPS routes and available metrics, and normalises them into `ImportedActivity`.
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
            results.append(makeActivity(from: workout, coordinates: coordinates))
        }
        return results
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

        var coordinates: [CLLocationCoordinate2D] = []
        for route in routes {
            let locations = try await locations(for: route)
            coordinates.append(contentsOf: locations.map(\.coordinate))
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
