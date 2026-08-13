import Foundation
import CoreLocation

/// Strava as an *optional enrichment* provider. It contributes the same run set Strava
/// knows about, but its real value is metadata HealthKit lacks: activity titles, gear,
/// descriptions, race identification, and location names. The import service merges these
/// into HealthKit runs where they match, and only creates standalone runs for Strava
/// activities that have no HealthKit counterpart.
@MainActor
final class StravaProvider: ActivityProvider {

    let auth: StravaAuthService
    private let client: StravaAPIClient

    let source: ActivitySource = .strava
    let role: ProviderRole = .enrichment

    init(auth: StravaAuthService) {
        self.auth = auth
        self.client = StravaAPIClient(auth: auth)
    }

    var isAvailable: Bool { auth.isAuthenticated }

    func fetchActivities(since: Date?) async throws -> [ImportedActivity] {
        guard isAvailable else { return [] }

        var page = 1
        var results: [ImportedActivity] = []
        let after = since?.timeIntervalSince1970

        while true {
            let activities = try await client.activities(page: page, perPage: 100, after: after)
            if activities.isEmpty { break }

            for activity in activities where activity.isRunLike {
                results.append(makeActivity(from: activity))
            }
            if activities.count < 100 { break }
            page += 1
        }
        return results
    }

    /// Enriches a single activity with its detail payload (city/state/country, gear,
    /// description). Kept separate so the orchestrator only pays for details on matched
    /// or newly-created runs.
    func enrich(_ activity: inout ImportedActivity) async {
        guard let id = Int64(activity.externalID),
              let detail = try? await client.activityDetail(id: id) else { return }
        activity.city = detail.locationCity
        activity.state = detail.locationState
        activity.country = detail.locationCountry
    }

    private func makeActivity(from activity: StravaActivity) -> ImportedActivity {
        let polyline = activity.map?.bestPolyline ?? ""
        let coords = PolylineDecoder.decode(polyline)

        var imported = ImportedActivity(
            provider: .strava,
            externalID: String(activity.id),
            startDate: activity.startDate,
            distance: activity.distance,
            movingTime: activity.movingTime,
            elapsedTime: activity.elapsedTime,
            coordinates: coords
        )
        imported.originApp = .strava
        imported.importMethod = .stravaAPI
        imported.name = activity.name
        imported.encodedPolyline = polyline
        imported.elevationGain = activity.totalElevationGain
        imported.sportType = activity.sportType ?? activity.type
        imported.isRace = activity.resolvedIsRace
        imported.isCommute = activity.commute ?? false
        imported.isTrail = activity.isTrail
        imported.weatherTemperatureC = activity.averageTemp
        if let latlng = activity.startLatlng, latlng.count == 2 {
            imported.coordinates = coords.isEmpty
                ? [CLLocationCoordinate2D(latitude: latlng[0], longitude: latlng[1])]
                : coords
        }
        return imported
    }
}
