import Foundation
import Observation
import SwiftData
import CoreLocation

/// Imports runs from Strava into the local SwiftData store.
///
/// The first sync pages through the entire history; subsequent syncs pass the most
/// recent stored `startDate` as an `after` cursor so only new activities are fetched.
@MainActor
@Observable
final class SyncService {

    enum Status: Equatable {
        case idle
        case syncing(imported: Int)
        case finished(imported: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncDate: Date? {
        didSet {
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
            }
        }
    }

    private let auth: StravaAuthService
    private let client: StravaAPIClient
    private let context: ModelContext

    init(auth: StravaAuthService, context: ModelContext) {
        self.auth = auth
        self.client = StravaAPIClient(auth: auth)
        self.context = context
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }

    var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    /// Runs an incremental sync (or a full import on first run).
    func sync(enrichLocations: Bool = true) async {
        guard auth.isAuthenticated, !isSyncing else { return }
        status = .syncing(imported: 0)

        do {
            let after = try mostRecentStartDate()?.timeIntervalSince1970
            var page = 1
            var importedCount = 0

            while true {
                let activities = try await client.activities(page: page, perPage: 100, after: after)
                if activities.isEmpty { break }

                for activity in activities where activity.isRunLike {
                    if try await upsert(activity, enrichLocations: enrichLocations) {
                        importedCount += 1
                        status = .syncing(imported: importedCount)
                    }
                }
                try context.save()
                if activities.count < 100 { break }
                page += 1
            }

            lastSyncDate = Date()
            status = .finished(imported: importedCount)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Helpers

    private func mostRecentStartDate() throws -> Date? {
        var descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.startDate
    }

    /// Inserts an activity if not already stored. Returns true when a new run was added.
    private func upsert(_ activity: StravaActivity, enrichLocations: Bool) async throws -> Bool {
        let id = activity.id
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.activityID == id })
        descriptor.fetchLimit = 1
        if try !context.fetch(descriptor).isEmpty { return false }

        let polyline = activity.map?.bestPolyline ?? ""
        let coords = PolylineDecoder.decode(polyline)
        let box = boundingBox(of: coords, fallback: activity.startLatlng)

        let run = Run(
            activityID: id,
            name: activity.name,
            startDate: activity.startDate,
            distance: activity.distance,
            movingTime: activity.movingTime,
            elapsedTime: activity.elapsedTime,
            elevationGain: activity.totalElevationGain,
            summaryPolyline: polyline,
            sportType: activity.sportType ?? activity.type,
            isRace: activity.resolvedIsRace,
            isCommute: activity.commute ?? false,
            isTrail: activity.isTrail,
            startLatitude: activity.startLatlng?.first ?? coords.first?.latitude,
            startLongitude: activity.startLatlng?.last ?? coords.first?.longitude,
            minLatitude: box.minLat,
            maxLatitude: box.maxLat,
            minLongitude: box.minLon,
            maxLongitude: box.maxLon
        )
        context.insert(run)

        if enrichLocations {
            // Best-effort location enrichment; failures shouldn't abort the import.
            if let detail = try? await client.activityDetail(id: id) {
                run.city = detail.locationCity
                run.state = detail.locationState
                run.country = detail.locationCountry
            }
        }
        return true
    }

    private func boundingBox(
        of coords: [CLLocationCoordinate2D],
        fallback: [Double]?
    ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        if coords.isEmpty {
            let lat = fallback?.first ?? 0
            let lon = fallback?.last ?? 0
            return (lat, lat, lon, lon)
        }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        return (minLat, maxLat, minLon, maxLon)
    }
}
