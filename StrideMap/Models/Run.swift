import Foundation
import SwiftData
import CoreLocation

/// A single run imported from Strava, persisted locally with SwiftData.
///
/// Only new activities are fetched on subsequent syncs (see `SyncService`), so this
/// is the durable local cache of a user's entire running history.
@Model
final class Run {

    /// Strava activity identifier. Unique — used to de-duplicate on incremental sync.
    @Attribute(.unique) var activityID: Int64

    var name: String
    var startDate: Date

    /// Metres.
    var distance: Double
    /// Seconds (moving time).
    var movingTime: Int
    /// Seconds (elapsed time).
    var elapsedTime: Int
    /// Metres of total elevation gain.
    var elevationGain: Double

    /// The encoded (Google-format) summary polyline, stored verbatim from Strava.
    var summaryPolyline: String

    // Reverse-geocoded location metadata (Strava provides these on the detail payload).
    var city: String?
    var state: String?
    var country: String?

    var sportType: String
    var isRace: Bool
    var isCommute: Bool

    /// Whether the activity was recorded on a trail. Derived heuristically at import.
    var isTrail: Bool

    /// Bounding box + start of the decoded route, cached so the map layer and search
    /// can operate without decoding every polyline up front.
    var startLatitude: Double?
    var startLongitude: Double?
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    var importedAt: Date

    init(
        activityID: Int64,
        name: String,
        startDate: Date,
        distance: Double,
        movingTime: Int,
        elapsedTime: Int,
        elevationGain: Double,
        summaryPolyline: String,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        sportType: String,
        isRace: Bool = false,
        isCommute: Bool = false,
        isTrail: Bool = false,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        minLatitude: Double = 0,
        maxLatitude: Double = 0,
        minLongitude: Double = 0,
        maxLongitude: Double = 0
    ) {
        self.activityID = activityID
        self.name = name
        self.startDate = startDate
        self.distance = distance
        self.movingTime = movingTime
        self.elapsedTime = elapsedTime
        self.elevationGain = elevationGain
        self.summaryPolyline = summaryPolyline
        self.city = city
        self.state = state
        self.country = country
        self.sportType = sportType
        self.isRace = isRace
        self.isCommute = isCommute
        self.isTrail = isTrail
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.importedAt = Date()
    }
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

    /// A human place label, e.g. "Scottsdale, AZ".
    var placeLabel: String {
        [city, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Age of the run in days, used to fade older routes on the map.
    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }
}
