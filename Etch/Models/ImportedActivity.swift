import Foundation
import CoreLocation

/// A provider-agnostic activity as returned by an `ActivityProvider`. Providers translate
/// their native payloads into this shape; the import service then merges these into the
/// unified `Run` model that the UI consumes. Every enrichable field is optional so no
/// provider is assumed to supply everything.
struct ImportedActivity {

    /// The provider that produced this record (HealthKit, Strava, …).
    var provider: ActivitySource
    /// The provider's own identifier (HKWorkout UUID string, Strava activity id, …).
    var externalID: String
    /// The true originating app when known (e.g. a HealthKit workout written by
    /// "Nike Run Club"). Falls back to `provider` when unavailable.
    var originApp: ActivitySource? = nil

    var name: String? = nil
    var startDate: Date
    var endDate: Date? = nil

    // Core metrics.
    var distance: Double            // metres
    var movingTime: Int             // seconds
    var elapsedTime: Int            // seconds
    var elevationGain: Double? = nil // metres

    // Route.
    var coordinates: [CLLocationCoordinate2D]
    /// Pre-encoded polyline, if the provider already has one (Strava). When nil the
    /// import service encodes `coordinates`.
    var encodedPolyline: String? = nil

    // Rich metrics (HealthKit / device sources).
    var averageHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
    var activeEnergy: Double? = nil       // kcal
    var averageCadence: Double? = nil     // steps per minute

    // Classification & metadata (often Strava-only).
    var sportType: String? = nil
    var isRace: Bool? = nil
    var isCommute: Bool? = nil
    var isTrail: Bool? = nil
    var gear: String? = nil
    var notes: String? = nil

    // Location (usually Strava-provided; HealthKit does not geocode).
    var city: String? = nil
    var state: String? = nil
    var country: String? = nil

    init(
        provider: ActivitySource,
        externalID: String,
        startDate: Date,
        distance: Double,
        movingTime: Int,
        elapsedTime: Int,
        coordinates: [CLLocationCoordinate2D] = []
    ) {
        self.provider = provider
        self.externalID = externalID
        self.startDate = startDate
        self.distance = distance
        self.movingTime = movingTime
        self.elapsedTime = elapsedTime
        self.coordinates = coordinates
    }
}
