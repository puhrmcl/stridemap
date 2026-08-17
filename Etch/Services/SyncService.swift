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
    /// Guards against overlapping landmark-detection passes.
    private var isDetectingLandmarks = false
    /// Short human-readable result of the last sync (e.g. "Health: 0 workouts"), shown on the
    /// empty/importing screen so it's obvious *why* there are no runs.
    private(set) var lastDiagnostic = ""
    private(set) var lastSyncDate: Date? {
        didSet {
            if let lastSyncDate {
                UserDefaults.standard.set(lastSyncDate, forKey: "lastSyncDate")
            }
        }
    }
    /// Strava's own high-water mark, independent of HealthKit's. Nil until Strava has been
    /// synced once — so the *first* Strava sync backfills the full history and can enrich
    /// runs (and supply routes for Nike/others) recorded long before Strava was connected.
    /// Using the shared `lastSyncDate` here would ask Strava only for brand-new activities.
    private(set) var lastStravaSyncDate: Date? {
        didSet {
            if let lastStravaSyncDate {
                UserDefaults.standard.set(lastStravaSyncDate, forKey: "lastStravaSyncDate")
            }
        }
    }

    private let context: ModelContext
    private let healthKit: HealthKitService
    private let auth: StravaAuthService

    private let healthKitProvider: HealthKitProvider
    private let stravaProvider: StravaProvider
    private let locationEnricher = LocationEnricher()
    /// Shared de-duplication / merge / run-construction. Every ingestion path (sync here,
    /// file import later) commits through this one type so runs are never duplicated.
    private let ingestor: ActivityIngestor

    init(healthKit: HealthKitService, auth: StravaAuthService, context: ModelContext) {
        self.healthKit = healthKit
        self.auth = auth
        self.context = context
        self.healthKitProvider = HealthKitProvider(store: healthKit.store)
        self.stravaProvider = StravaProvider(auth: auth)
        self.ingestor = ActivityIngestor(context: context)
        self.lastSyncDate = UserDefaults.standard.object(forKey: "lastSyncDate") as? Date
        self.lastStravaSyncDate = UserDefaults.standard.object(forKey: "lastStravaSyncDate") as? Date
    }

    var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    /// Whether there is anything to sync from (HealthKit available or Strava connected).
    var hasAnySource: Bool {
        healthKitProvider.isAvailable || stravaProvider.isAvailable
    }

    /// True when Strava is connected but has never completed its first full-history pull.
    /// Lets the app auto-run the backfill on launch even when runs already exist, so the
    /// maps for pre-existing runs appear without the user tapping "Sync Now".
    var needsStravaBackfill: Bool {
        stravaProvider.isAvailable && lastStravaSyncDate == nil
    }

    // MARK: Sync

    func sync() async {
        guard !isSyncing, hasAnySource else { return }
        status = .syncing(imported: 0)
        var imported = 0

        do {
            let since = lastSyncDate

            // 1. Primary: HealthKit (and any future primary providers). Time-boxed so a
            // slow/unresponsive HealthKit store can never leave the import spinner up forever.
            if healthKitProvider.isAvailable {
                let activities = await healthKitActivities(since: since, timeout: 15)
                for activity in activities {
                    if try ingestor.ingestPrimary(activity) == .inserted {
                        imported += 1
                        status = .syncing(imported: imported)
                    }
                }
                try context.save()

                if activities.isEmpty {
                    // Nothing imported — say why: how many workouts of any type exist vs runs.
                    let provider = healthKitProvider
                    let summary = await withTimeout(10, fallback: "query timed out") {
                        await provider.workoutSummary()
                    }
                    lastDiagnostic = "Health: \(summary)"
                } else {
                    lastDiagnostic = "Health: \(activities.count) runs imported"
                }
            } else {
                lastDiagnostic = "Apple Health unavailable"
            }

            // 2. Enrichment: Strava merges into primary runs or adds its own. Time-boxed too.
            if stravaProvider.isAvailable {
                // Strava has its own high-water mark: nil on first connect → pull the FULL
                // history so routes/metadata can attach to runs recorded before Strava was
                // linked (this is what puts maps on historical Nike runs). Incremental after.
                let stravaSince = lastStravaSyncDate
                let activities = await withTimeout(45, fallback: [ImportedActivity]()) { [stravaProvider] in
                    (try? await stravaProvider.fetchActivities(since: stravaSince)) ?? []
                }
                // Detail fetches (city/state) cost one API call each; cap them so a large
                // first-time backfill stays well under Strava's rate limit. Routes and titles
                // come from the activity *list* and are applied to every activity regardless;
                // missing place names are filled by reverse-geocoding below.
                var detailBudget = 40
                var mergedCount = 0, newCount = 0
                for activity in activities {
                    var activity = activity
                    let fetchDetail = detailBudget > 0
                    // Strava's per-activity detail (city/state/country) is a provider-specific
                    // network call, so it happens here — before the provider-agnostic ingestor.
                    if fetchDetail { await stravaProvider.enrich(&activity) }
                    switch try ingestor.ingestEnrichment(activity) {
                    case .inserted:
                        imported += 1
                        newCount += 1
                        status = .syncing(imported: imported)
                    case .merged:
                        mergedCount += 1
                    }
                    if fetchDetail { detailBudget -= 1 }
                }
                try context.save()
                lastStravaSyncDate = Date()
                lastDiagnostic += " · Strava: \(activities.count) activities (\(mergedCount) merged, \(newCount) new)"
            } else {
                lastDiagnostic += " · Strava not connected"
            }

            // Offline: derive US state + country for the whole library at once (point-in-polygon,
            // no network), so the states/countries counts reflect every located run immediately
            // rather than trickling in behind the rate-limited city geocoder below.
            await enrichStatesOffline()
            // Best-effort: fill in city names for runs that arrived without them
            // (HealthKit doesn't geocode). Bounded so we never hit CLGeocoder limits.
            await enrichMissingLocations(limit: 40)

            lastSyncDate = Date()
            status = .finished(imported: imported)

            // Import is intentionally route-free so runs appear immediately; hydrate maps in
            // the background afterwards, off the sync spinner. Bounded + progressive.
            Task { await recoverMissingRoutes(limit: 400) }
            // Attribute runs to nearby landmarks in the background too (bounded; fills over time).
            Task { await detectLandmarks(limit: 30) }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Fetches HealthKit activities with a hard timeout, returning whatever's available (or
    /// an empty list) rather than hanging the whole import if the query never comes back.
    private func healthKitActivities(since: Date?, timeout seconds: Double) async -> [ImportedActivity] {
        let provider = healthKitProvider
        return await withTimeout(seconds, fallback: [ImportedActivity]()) {
            (try? await provider.fetchActivities(since: since)) ?? []
        }
    }

    /// Fills place names after an import that doesn't go through a full sync (e.g. a file/ZIP
    /// import): offline state/country for the whole library at once, then a bounded city pass.
    func enrichLocations() async {
        await enrichStatesOffline()
        await enrichMissingLocations(limit: 40)
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
                // Don't clobber a state/country the offline pass already set from boundaries.
                if run.state == nil { run.state = place.state }
                if run.country == nil { run.country = place.country }
            }
        }
        try? context.save()
    }

    /// Fills `state` (and `country`) for every located run that lacks them, using the offline US
    /// state boundaries — instant and unbounded, unlike the CLGeocoder city pass. This is why the
    /// states/countries counts (which tally `run.state`) can lag a big import: state was previously
    /// only set by the rate-limited geocoder. Runs outside the US (no boundary match) are left for
    /// the geocoder to place.
    private func enrichStatesOffline() async {
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.state == nil && $0.startLatitude != nil }
        )
        guard let candidates = try? context.fetch(descriptor), !candidates.isEmpty else { return }
        let boundaries = USStateBoundaries.shared
        guard !boundaries.boundaries.isEmpty else { return }

        var changed = false
        for run in candidates {
            guard let coordinate = run.startCoordinate,
                  let stateName = boundaries.region(containing: coordinate) else { continue }
            run.state = stateName
            if run.country == nil { run.country = "United States" }
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: Landmark detection

    /// Attributes located runs to a nearby point of interest (park, university, museum, …) for
    /// the Landmarks overlay. Runs are clustered to a ~1km cell so one POI query covers all the
    /// runs that started there. Bounded per pass and safe to call repeatedly — it fills in over
    /// time; a failed search backs off (leaves runs unchecked) rather than marking them
    /// landmark-less. Safe to run alongside sync/route recovery.
    func detectLandmarks(limit: Int = 20) async {
        guard !isDetectingLandmarks else { return }
        isDetectingLandmarks = true
        defer { isDetectingLandmarks = false }

        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.landmarkChecked == false && $0.startLatitude != nil }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        // Group the unchecked runs into ~1km cells; query each cell once.
        let clusters = Dictionary(grouping: pending) { landmarkCell($0) }
        var processed = 0
        for (_, clusterRuns) in clusters {
            if processed >= limit { break }
            guard let coordinate = clusterRuns.first?.startCoordinate else { continue }
            do {
                let name = try await LandmarkFinder.nearest(to: coordinate)
                for run in clusterRuns {
                    run.landmarkName = name
                    run.landmarkChecked = true
                }
            } catch {
                // Search failed (throttled / offline) — stop and back off; retry next pass.
                break
            }
            processed += 1
            if processed % 5 == 0 { try? context.save() }
        }
        try? context.save()
        // Space successive passes so the auto-refill doesn't hammer the POI service.
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    /// A ~1km grid cell for a run's start, so nearby runs share one landmark query.
    private func landmarkCell(_ run: Run) -> String {
        guard let c = run.startCoordinate else { return "?" }
        let lat = (c.latitude * 100).rounded() / 100
        let lon = (c.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
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
    /// Hard cap on how long a single hydration pass runs, so the recovery spinner can never
    /// hang even if HealthKit is slow. Remaining runs stay pending and are retried later.
    private let hydrationDeadline: TimeInterval = 90

    /// Hydrates maps for HealthKit runs that don't have one yet, streaming routes in and
    /// saving progressively so the map fills in as it goes. Safe to run repeatedly; recent
    /// runs keep retrying, older route-less runs are marked `.unavailable` so history isn't
    /// rescanned forever.
    func recoverMissingRoutes(limit: Int = 150) async {
        guard !isRecoveringRoutes, healthKitProvider.isAvailable else { return }
        isRecoveringRoutes = true
        defer { isRecoveringRoutes = false }
        await hydratePendingRoutes(limit: limit)
    }

    /// Manual "Recover Missing Maps" entry point. Re-opens runs previously written off, then
    /// hydrates. Exposed for a Settings action; idempotent and safe to invoke anytime.
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

        await hydratePendingRoutes(limit: 2000)
    }

    /// Core hydration. Callers own the `isRecoveringRoutes` flag so it always resets.
    private func hydratePendingRoutes(limit: Int) async {
        let unavailable = RouteSyncStatus.unavailable.rawValue
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate {
                $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw != unavailable
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        let runsByID = Dictionary(
            pending.compactMap { run in run.healthKitID.map { ($0, run) } },
            uniquingKeysWith: { first, _ in first }
        )
        // Fetch workouts only from the window the pending runs fall in.
        let since = pending.map(\.startDate).min()?.addingTimeInterval(-24 * 60 * 60)
        let deadline = Date().addingTimeInterval(hydrationDeadline)

        var processed = 0, recovered = 0, noRoute = 0, failed = 0
        for await item in healthKitProvider.routeStream(forWorkoutUUIDs: Set(runsByID.keys), since: since) {
            if let run = runsByID[item.id] {
                run.routeCheckedAt = Date()
                run.routeCheckCount += 1
                switch item.outcome {
                case .coordinates(let coordinates, let elevations):
                    ingestor.applyRoute(coordinates, source: .healthKit, to: run, elevations: elevations)
                    recovered += 1
                case .noRoute:
                    // The source wrote no route. Retry recent runs a few times, then mark
                    // genuinely unavailable so history isn't rescanned forever.
                    noRoute += 1
                    let age = Date().timeIntervalSince(run.startDate)
                    if age > routePendingWindow || run.routeCheckCount >= maxRouteChecks {
                        run.routeStatus = .unavailable
                    } else {
                        run.routeStatus = .pending
                    }
                case .failed:
                    // Query error — keep retriable (not the terminal `.unavailable`).
                    failed += 1
                    run.routeStatus = .failed
                }
            }
            processed += 1
            if processed % 20 == 0 { try? context.save() }   // let the map fill in as we go
            if Date() > deadline { break }
        }

        try? context.save()
        HealthKitLog.route("[Etch HealthKit] Route pass: \(recovered) recovered · \(noRoute) no-route · \(failed) failed · of \(processed)")
    }
}
