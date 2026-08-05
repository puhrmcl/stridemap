import Foundation

/// The OAuth token set returned by Strava's `/oauth/token` endpoint.
struct StravaToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Unix epoch seconds at which the access token expires.
    var expiresAt: TimeInterval
    var athlete: StravaAthlete?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }

    var isExpired: Bool {
        // Refresh a minute early to avoid racing the boundary.
        Date().timeIntervalSince1970 >= (expiresAt - 60)
    }
}

struct StravaAthlete: Codable, Equatable {
    var id: Int64
    var firstname: String?
    var lastname: String?
    var profile: String?

    var displayName: String {
        [firstname, lastname].compactMap { $0 }.joined(separator: " ")
    }
}

/// A summary activity from `/athlete/activities`.
struct StravaActivity: Decodable {
    var id: Int64
    var name: String
    var distance: Double
    var movingTime: Int
    var elapsedTime: Int
    var totalElevationGain: Double
    var type: String
    var sportType: String?
    var startDate: Date
    var map: StravaMap?
    var isRace: Bool?          // work_type == 1 historically; modern API uses `workout_type`
    var workoutType: Int?
    var commute: Bool?
    var startLatlng: [Double]?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, type, commute, map
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case sportType = "sport_type"
        case startDate = "start_date"
        case workoutType = "workout_type"
        case startLatlng = "start_latlng"
        case isRace
    }

    /// Strava marks races via `workout_type == 1` for runs.
    var resolvedIsRace: Bool {
        workoutType == 1 || (isRace ?? false)
    }

    var isRunLike: Bool {
        let t = (sportType ?? type).lowercased()
        return t.contains("run") || t == "trailrun" || t == "virtualrun"
    }

    var isTrail: Bool {
        (sportType ?? type).lowercased().contains("trail")
    }
}

struct StravaMap: Decodable {
    var id: String?
    var summaryPolyline: String?
    var polyline: String?

    enum CodingKeys: String, CodingKey {
        case id
        case summaryPolyline = "summary_polyline"
        case polyline
    }

    var bestPolyline: String {
        polyline ?? summaryPolyline ?? ""
    }
}

/// Detail payload (`/activities/{id}`) — used to enrich location metadata.
struct StravaActivityDetail: Decodable {
    var id: Int64
    var locationCity: String?
    var locationState: String?
    var locationCountry: String?
    var map: StravaMap?

    enum CodingKeys: String, CodingKey {
        case id, map
        case locationCity = "location_city"
        case locationState = "location_state"
        case locationCountry = "location_country"
    }
}
