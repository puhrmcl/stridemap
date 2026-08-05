import Foundation
import SwiftData
import CoreLocation

/// A single run, unified across every provider (HealthKit, Strava, and future
/// integrations). This is the *only* activity model the UI consumes — providers feed
/// `ImportedActivity` values into the import service, which creates or merges `Run`s.
///
/// Fields are intentionally permissive: no provider is assumed to supply everything, so
/// most enrichment fields are optional.
@Model
final class Run {

    /// The app's stable identity, independent of any provider.
    @Attribute(.unique) var id: UUID

    // MARK: Provenance

    /// The primary source this run was imported from (usually `.healthKit`).
    var providerRaw: String
    /// The true originating app when known (e.g. a HealthKit workout authored by Nike
    /// Run Club). Shown, subtly, on the detail screen.
    var originAppRaw: String?

    /// HealthKit workout UUID (string) — the primary de-duplication key.
    var healthKitID: String?
    /// Strava activity id, present once a run has been matched/enriched with Strava.
    var stravaActivityID: Int64?

    // MARK: Core

    var name: String
    var startDate: Date
    var distance: Double        // metres
    var movingTime: Int         // seconds
    var elapsedTime: Int        // seconds
    var elevationGain: Double

    /// Encoded (Google-format) polyline of the route.
    var summaryPolyline: String

    // MARK: Rich metrics (may be absent depending on source)

    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergy: Double?       // kcal
    var averageCadence: Double?     // steps/min

    // MARK: Location metadata

    var city: String?
    var state: String?
    var country: String?

    // MARK: Classification

    var sportType: String
    var isRace: Bool
    var isCommute: Bool
    var isTrail: Bool

    // MARK: User & future-proofing

    var gear: String?
    var notes: String?
    var isFavorite: Bool
    var tags: [String]
    /// Reserved for a future photos feature — stored as opaque references.
    var photoReferences: [String]

    // MARK: Cached geometry

    var startLatitude: Double?
    var startLongitude: Double?
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    var importedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        provider: ActivitySource,
        originApp: ActivitySource? = nil,
        healthKitID: String? = nil,
        stravaActivityID: Int64? = nil,
        name: String,
        startDate: Date,
        distance: Double,
        movingTime: Int,
        elapsedTime: Int,
        elevationGain: Double,
        summaryPolyline: String,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        activeEnergy: Double? = nil,
        averageCadence: Double? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        sportType: String,
        isRace: Bool = false,
        isCommute: Bool = false,
        isTrail: Bool = false,
        gear: String? = nil,
        notes: String? = nil,
        isFavorite: Bool = false,
        tags: [String] = [],
        photoReferences: [String] = [],
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        minLatitude: Double = 0,
        maxLatitude: Double = 0,
        minLongitude: Double = 0,
        maxLongitude: Double = 0
    ) {
        self.id = id
        self.providerRaw = provider.rawValue
        self.originAppRaw = originApp?.rawValue
        self.healthKitID = healthKitID
        self.stravaActivityID = stravaActivityID
        self.name = name
        self.startDate = startDate
        self.distance = distance
        self.movingTime = movingTime
        self.elapsedTime = elapsedTime
        self.elevationGain = elevationGain
        self.summaryPolyline = summaryPolyline
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.activeEnergy = activeEnergy
        self.averageCadence = averageCadence
        self.city = city
        self.state = state
        self.country = country
        self.sportType = sportType
        self.isRace = isRace
        self.isCommute = isCommute
        self.isTrail = isTrail
        self.gear = gear
        self.notes = notes
        self.isFavorite = isFavorite
        self.tags = tags
        self.photoReferences = photoReferences
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.importedAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Provenance helpers

extension Run {

    var provider: ActivitySource {
        get { ActivitySource(rawValue: providerRaw) }
        set { providerRaw = newValue.rawValue }
    }

    var originApp: ActivitySource? {
        get { originAppRaw.map { ActivitySource(rawValue: $0) } }
        set { originAppRaw = newValue?.rawValue }
    }

    /// The source shown to the user: the true origin app when known, otherwise the
    /// importing provider. If the run has been enriched by Strava we still surface the
    /// original recording app, because that's where the run actually came from.
    var displaySource: ActivitySource {
        originApp ?? provider
    }

    var isStravaLinked: Bool { stravaActivityID != nil }
}

// MARK: - Derived values

extension Run {

    /// Average pace in seconds per kilometre.
    var paceSecondsPerKm: Double {
        guard distance > 0 else { return 0 }
        return Double(movingTime) / (distance / 1000)
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = startLatitude, let lon = startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Decodes the summary polyline into coordinates on demand.
    var coordinates: [CLLocationCoordinate2D] {
        PolylineDecoder.decode(summaryPolyline)
    }

    var hasRoute: Bool { !summaryPolyline.isEmpty }

    var placeLabel: String {
        [city, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }
}
