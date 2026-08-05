import Foundation
import Observation
import HealthKit

/// Owns the `HKHealthStore`, authorization, and background observation. This is the
/// gateway to Apple Health — the app's primary data source. Strava is layered on top as
/// optional enrichment.
@MainActor
@Observable
final class HealthKitService {

    let store = HKHealthStore()

    /// Whether HealthKit exists on this device (false on iPad without Health, etc.).
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// We can't reliably read *read* authorization status (Apple hides it for privacy),
    /// so we track whether we've asked. Persisted so onboarding only happens once.
    var hasRequestedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: "healthKitRequested") }
        set { UserDefaults.standard.set(newValue, forKey: "healthKitRequested") }
    }

    /// The set of types we read. All optional at point of use — a workout may lack any.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .activeEnergyBurned, .distanceWalkingRunning, .stepCount,
        ]
        for id in quantities {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        return types
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Health isn't available on this device."
            }
        }
    }

    /// Prompts for read access. Safe to call repeatedly; the system only shows the sheet
    /// for types the user hasn't decided on.
    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        hasRequestedAuthorization = true
    }

    // MARK: Background delivery

    private var observerQuery: HKObserverQuery?

    /// Starts observing new running workouts and invokes `onChange` when Health reports
    /// updates. Also enables background delivery so syncs can happen when new workouts
    /// arrive while the app is backgrounded.
    func startObserving(onChange: @escaping () -> Void) {
        guard isAvailable, observerQuery == nil else { return }
        let workoutType = HKObjectType.workoutType()

        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completion, _ in
            onChange()
            completion()
        }
        store.execute(query)
        observerQuery = query

        store.enableBackgroundDelivery(for: workoutType, frequency: .hourly) { _, _ in
            // Best-effort; failures are non-fatal (e.g. entitlement not provisioned).
        }
    }

    func stopObserving() {
        if let observerQuery {
            store.stop(observerQuery)
            self.observerQuery = nil
        }
    }
}
