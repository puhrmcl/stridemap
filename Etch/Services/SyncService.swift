import Foundation
import Observation
import SwiftData
import CoreLocation

/// Orchestrates importing runs from every configured `ActivityProvider` into the local
/// SwiftData store, merging duplicates so the map never shows the same run twice.
///
/// HealthKit is the primary source. Strava (when connected) enriches matching runs and
/// contributes any runs HealthKit doesn't have. Additional providers can be slotted in by
/// adding them to `primaryProviders` / `enrichmentProviders` — nothing else changes.
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
    /// True while a manual "recover missing maps" pass is running (drives the Settings UI).
    private(set) var isRecoveringRoutes = false
    private(set) var lastSyncDate: Date? {
        didSet {
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
            }
        }
    }

    private let context: ModelContext
    private let healthKit: HealthKitService
    private let auth: StravaAuthService

    private let healthKitProvider: HealthKitProvider
    private let stravaProvider: StravaProvider
    private let locationEnricher = LocationEnricher()

    init(healthKit: HealthKitService, auth: StravaAuthService, context: ModelContext) {
        self.healthKit = healthKit
        self.auth = auth
        self.context = context
        self.healthKitProvider = HealthKitProvider(store: healthKit.store)
        self.stravaProvider = StravaProvider(auth: auth)
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
    }

    var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    /// Whether there is anything to sync from (HealthKit available or Strava connected).
    var hasAnySource: Bool {
        healthKitProvider.isAvailable || stravaProvider.isAvailable
    }

    // MARK: Sync

    func sync() async {
        guard !isSyncing, hasAnySource else { return }
        status = .syncing(imported: 0)
        var imported = 0

        do {
            let since = lastSyncDate

            // 1. Primary: HealthKit (and any future primary providers).
            if healthKitProvider.isAvailable {
                let activities = try await healthKitProvider.fetchActivities(since: since)
                for activity in activities {
                    if try importPrimary(activity) {
                        imported += 1
                        status = .syncing(imported: imported)
                    }
                }
                try context.save()
            }

            // 2. Enrichment: Strava merges into primary runs or adds its own.
            if stravaProvider.isAvailable {
                let activities = try await stravaProvider.fetchActivities(since: since)
                for activity in activities {
                    var activity = activity
                    if try await importEnrichment(&activity) {
                        imported += 1
                        status = .syncing(imported: imported)
                    }
                }
                try context.save()
            }

            // Recover routes for HealthKit runs whose route arrived after the workout, or
            // that were imported before route tracking existed. Bounded + idempotent.
            await recoverMissingRoutes(limit: 40)

            // Best-effort: fill in place names for runs that arrived without them
            // (HealthKit doesn't geocode). Bounded so we never hit CLGeocoder limits.
            await enrichMissingLocations(limit: 40)

            lastSyncDate = Date()
            status = .finished(imported: imported)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Reverse-geocodes up to `limit` runs that have a start coordinate but no city.
    private func enrichMissingLocations(limit: Int) async {
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.city == nil && $0.startLatitude != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return }

        for run in candidates {
            guard let coordinate = run.startCoordinate else { continue }
            if let place = await locationEnricher.place(for: coordinate) {
                run.city = place.city
                run.state = place.state
                run.country = place.country
            }
        }
        try? context.save()
    }

    // MARK: Route recovery (late-arriving HealthKit routes)

    /// A run is old enough that a route is very unlikely to still be syncing in.
    private let routePendingWindow: TimeInterval = 14 * 24 * 60 * 60   // 14 days
    /// Give up after this many fruitless checks even for recent runs.
    private let maxRouteChecks = 6

    /// Re-queries HealthKit for routes of runs that are missing one, and attaches any that
    /// have since become available. Safe to run repeatedly.
    ///
    /// Performance: bounded to `limit` runs per pass, newest first, and never touches runs
    /// already ruled `.unavailable`. Recent runs keep retrying; older runs get a single
    /// check and are then marked `.unavailable`, so history is never rescanned on every
    /// launch.
    func recoverMissingRoutes(limit: Int = 40) async {
        guard healthKitProvider.isAvailable else { return }

        let unavailable = RouteSyncStatus.unavailable.rawValue
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate {
                $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw != unavailable
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return }

        var recovered = 0
        var changed = false
        for run in candidates {
            guard let hkID = run.healthKitID else { continue }
            let coordinates = await healthKitProvider.recoverRoute(forWorkoutUUID: hkID)
            run.routeCheckedAt = Date()
            run.routeCheckCount += 1
            changed = true

            switch coordinates {
            case .some(let coords) where !coords.isEmpty:
                applyRoute(coords, source: .healthKit, to: run)
                recovered += 1
                HealthKitLog.route("Updated Etch run \(run.id) with recovered route")
            case .some:
                // Workout found but still no route. Keep retrying only for recent runs.
                let age = Date().timeIntervalSince(run.startDate)
                if age > routePendingWindow || run.routeCheckCount >= maxRouteChecks {
                    run.routeStatus = .unavailable
                } else {
                    run.routeStatus = .pending
                }
            case .none:
                // Couldn't locate the workout right now — leave state, try again later.
                break
            }
        }

        if changed { try? context.save() }
        if recovered > 0 {
            HealthKitLog.route("Route recovery pass attached \(recovered) map(s)")
        }
    }

    /// Manual "Recover Missing Maps" entry point. Re-opens runs previously marked
    /// `.unavailable` for one more attempt, then runs a large recovery pass. Exposed for a
    /// Settings action; idempotent and safe to invoke anytime.
    func resyncHealthKitRoutes() async {
        guard !isRecoveringRoutes, healthKitProvider.isAvailable else { return }
        isRecoveringRoutes = true
        defer { isRecoveringRoutes = false }

        // Reset write-offs so the user's explicit request re-checks everything once more.
        let unavailable = RouteSyncStatus.unavailable.rawValue
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw == unavailable }
        )
        if let stale = try? context.fetch(descriptor) {
            for run in stale {
                run.routeStatus = .unknown
                run.routeCheckCount = 0
            }
            try? context.save()
        }

        await recoverMissingRoutes(limit: 500)
    }

    /// Attaches a recovered route to a run and records provenance/state. Central so every
    /// path (initial import, enrichment merge, backfill) writes route state consistently.
    private func applyRoute(
        _ coordinates: [CLLocationCoordinate2D],
        source: RouteSource,
        to run: Run,
        encoded: String? = nil
    ) {
        guard !coordinates.isEmpty else { return }
        run.summaryPolyline = encoded ?? PolylineDecoder.encode(coordinates)
        applyGeometry(coordinates, to: run)
        run.routeStatus = .available
        run.routeSource = source
        run.updatedAt = Date()
    }

    // MARK: Primary import (HealthKit)

    /// Creates a run from a primary provider activity. De-duplicates on the HealthKit id,
    /// and — so ordering never matters — merges into a matching run that some other
    /// provider (e.g. Strava) created first. Returns true only when a new run was inserted.
    private func importPrimary(_ activity: ImportedActivity) throws -> Bool {
        let hkID = activity.externalID
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.healthKitID == hkID })
        descriptor.fetchLimit = 1
        if try !context.fetch(descriptor).isEmpty { return false }

        // A provider-created run without a HealthKit id may be this same activity.
        if let match = try bestMatch(for: activity), match.healthKitID == nil {
            mergeHealthKit(activity, into: match)
            return false
        }

        let run = makeRun(from: activity)
        run.healthKitID = activity.externalID
        run.routeCheckedAt = Date()
        run.routeCheckCount = 1
        if run.hasRoute {
            run.routeStatus = .available
            run.routeSource = .healthKit
        } else {
            // The workout arrived; its route may still be syncing (Nike Run Club). Mark it
            // pending so recovery keeps looking rather than treating this as route-less.
            run.routeStatus = .pending
        }
        context.insert(run)
        return true
    }

    /// Fills a run with HealthKit-specific data (rich metrics + route) without clobbering
    /// existing metadata from another provider.
    private func mergeHealthKit(_ activity: ImportedActivity, into run: Run) {
        run.healthKitID = activity.externalID
        if run.originApp == nil { run.originApp = activity.originApp }
        if run.averageHeartRate == nil { run.averageHeartRate = activity.averageHeartRate }
        if run.maxHeartRate == nil { run.maxHeartRate = activity.maxHeartRate }
        if run.activeEnergy == nil { run.activeEnergy = activity.activeEnergy }
        if run.averageCadence == nil { run.averageCadence = activity.averageCadence }
        if !run.hasRoute, !activity.coordinates.isEmpty {
            applyRoute(activity.coordinates, source: .healthKit, to: run,
                       encoded: activity.encodedPolyline)
        }
        if run.elevationGain == 0, let gain = activity.elevationGain { run.elevationGain = gain }
        run.updatedAt = Date()
    }

    // MARK: Enrichment import (Strava)

    /// Merges a Strava activity into a matching run, or creates a standalone run when no
    /// HealthKit counterpart exists. Returns true only when a *new* run was inserted.
    private func importEnrichment(_ activity: inout ImportedActivity) async throws -> Bool {
        // Already linked to a run from a previous sync? Refresh lightweight metadata only.
        if let stravaID = Int64(activity.externalID),
           let existing = try runLinkedToStrava(stravaID) {
            await stravaProvider.enrich(&activity)
            merge(activity, into: existing)
            return false
        }

        // Try to match an existing (HealthKit) run that isn't yet Strava-linked.
        if let match = try bestMatch(for: activity), match.stravaActivityID == nil {
            await stravaProvider.enrich(&activity)
            merge(activity, into: match)
            return false
        }

        // No match — this is a Strava-only run. Create it.
        await stravaProvider.enrich(&activity)
        let run = makeRun(from: activity)
        run.stravaActivityID = Int64(activity.externalID)
        if run.hasRoute {
            run.routeStatus = .available
            run.routeSource = .strava
        }
        context.insert(run)
        return true
    }

    private func runLinkedToStrava(_ stravaID: Int64) throws -> Run? {
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.stravaActivityID == stravaID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Finds the best-scoring existing run within a time window around the activity.
    private func bestMatch(for activity: ImportedActivity) throws -> Run? {
        let window: TimeInterval = 20 * 60
        let start = activity.startDate.addingTimeInterval(-window)
        let end = activity.startDate.addingTimeInterval(window)
        let candidates = try context.fetch(
            FetchDescriptor<Run>(predicate: #Predicate { $0.startDate >= start && $0.startDate <= end })
        )
        return candidates
            .map { ($0, ActivityMatcher.confidence($0, activity)) }
            .filter { $0.1 >= ActivityMatcher.matchThreshold }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Merges Strava metadata into an existing run, keeping the richest available value
    /// for each field and never overwriting good data with nil.
    private func merge(_ activity: ImportedActivity, into run: Run) {
        if let stravaID = Int64(activity.externalID) { run.stravaActivityID = stravaID }

        // Strava titles are almost always more descriptive than HealthKit's.
        if let name = activity.name, !name.isEmpty { run.name = name }
        if let gear = activity.gear { run.gear = gear }
        if let notes = activity.notes, run.notes == nil { run.notes = notes }
        if activity.isRace == true { run.isRace = true }
        if let trail = activity.isTrail { run.isTrail = run.isTrail || trail }
        if let commute = activity.isCommute { run.isCommute = run.isCommute || commute }

        if run.city == nil { run.city = activity.city }
        if run.state == nil { run.state = activity.state }
        if run.country == nil { run.country = activity.country }

        // Fill route/elevation only if HealthKit didn't provide them.
        if !run.hasRoute, let polyline = activity.encodedPolyline, !polyline.isEmpty {
            applyRoute(activity.coordinates, source: .strava, to: run, encoded: polyline)
        }
        if run.elevationGain == 0, let gain = activity.elevationGain { run.elevationGain = gain }
        run.updatedAt = Date()
    }

    // MARK: Run construction

    private func makeRun(from activity: ImportedActivity) -> Run {
        let polyline = activity.encodedPolyline ?? PolylineDecoder.encode(activity.coordinates)
        let run = Run(
            provider: activity.provider,
            originApp: activity.originApp,
            name: resolvedName(activity),
            startDate: activity.startDate,
            distance: activity.distance,
            movingTime: activity.movingTime,
            elapsedTime: activity.elapsedTime,
            elevationGain: activity.elevationGain ?? 0,
            summaryPolyline: polyline,
            averageHeartRate: activity.averageHeartRate,
            maxHeartRate: activity.maxHeartRate,
            activeEnergy: activity.activeEnergy,
            averageCadence: activity.averageCadence,
            city: activity.city,
            state: activity.state,
            country: activity.country,
            sportType: activity.sportType ?? "Run",
            isRace: activity.isRace ?? false,
            isCommute: activity.isCommute ?? false,
            isTrail: activity.isTrail ?? false
        )
        applyGeometry(activity.coordinates, to: run)
        return run
    }

    private func applyGeometry(_ coordinates: [CLLocationCoordinate2D], to run: Run) {
        let box = RouteGeometry.boundingBox(of: coordinates, fallbackStart: coordinates.first)
        run.startLatitude = coordinates.first?.latitude ?? run.startLatitude
        run.startLongitude = coordinates.first?.longitude ?? run.startLongitude
        run.minLatitude = box.minLat
        run.maxLatitude = box.maxLat
        run.minLongitude = box.minLon
        run.maxLongitude = box.maxLon
    }

    /// Uses the provider's title when present; otherwise a calm time-of-day name.
    private func resolvedName(_ activity: ImportedActivity) -> String {
        if let name = activity.name, !name.isEmpty { return name }
        let hour = Calendar.current.component(.hour, from: activity.startDate)
        let part: String
        switch hour {
        case 5..<12: part = "Morning"
        case 12..<17: part = "Afternoon"
        case 17..<21: part = "Evening"
        default: part = "Night"
        }
        return "\(part) Run"
    }
}
