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
    /// True while a route-recovery pass is running (drives the Settings UI).
    private(set) var isRecoveringRoutes = false

    /// How far the running route-recovery pass has got. A spinner alone cannot tell a pass that
    /// is working through nine hundred activities from one that is stuck, and on a large library
    /// those look identical for a minute and a half.
    struct RouteProgress: Equatable {
        var checked: Int
        var total: Int
        var recovered: Int
    }
    private(set) var routeProgress: RouteProgress?
    /// What the last finished pass actually did, e.g. "Checked 210 · 14 maps found". Kept so the
    /// row can say something other than nothing once the spinner stops.
    private(set) var lastRouteResult: String?
    /// The pass in flight, so a manual request can take over from an automatic one and so the
    /// deadline has something to cancel.
    private var recoveryTask: Task<Void, Never>?
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

    /// Set when a sync is requested while one is already running — the HealthKit observer
    /// firing mid-import, say. Dropping that request would leave the workout that triggered it
    /// unimported until something else happened to kick a sync off, so it's remembered and
    /// drained instead.
    private var syncAgainWhenIdle = false

    func sync() async {
        guard hasAnySource else { return }
        if isSyncing {
            syncAgainWhenIdle = true
            return
        }
        await performSync()
        while syncAgainWhenIdle {
            syncAgainWhenIdle = false
            await performSync()
        }
    }

    private func performSync() async {
        status = .syncing(imported: 0)
        var imported = 0

        do {
            // 1. Primary: HealthKit (and any future primary providers). Time-boxed so a
            // slow/unresponsive HealthKit store can never leave the import spinner up forever.
            // `lastSyncDate` is passed for the provider protocol's sake; HealthKit reads by
            // anchor instead, because a workout can arrive in Health long after it started.
            if healthKitProvider.isAvailable {
                let activities = await healthKitActivities(since: lastSyncDate, timeout: 15)
                var healthImported = 0
                for activity in activities {
                    if try ingestor.ingestPrimary(activity) == .inserted {
                        imported += 1
                        healthImported += 1
                        status = .syncing(imported: imported)
                    }
                }
                try context.save()
                // Only now is it safe to advance HealthKit's read anchors: everything they
                // covered is on disk. A timeout or a throw above leaves them where they were,
                // so the next sync re-reads those workouts rather than losing them.
                healthKitProvider.commitAnchors()

                if activities.isEmpty {
                    // Nothing imported — say why: how many workouts of any type exist vs runs.
                    let provider = healthKitProvider
                    let summary = await withTimeout(10, fallback: "query timed out") {
                        await provider.workoutSummary()
                    }
                    lastDiagnostic = "Health: \(summary)"
                } else {
                    lastDiagnostic = "Health: \(activities.count) new workouts read, \(healthImported) imported"
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

    /// Clears every high-water mark so the next sync re-reads the whole history from scratch.
    /// Paired with "Delete cached activities" — deleting the library while HealthKit's anchors
    /// stay caught up would leave an empty app that never refills.
    func forgetHealthKitHistory() {
        healthKitProvider.resetAnchors()
        lastSyncDate = nil
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
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
    /// The automatic pass, run after a sync and whenever HealthKit reports new route data.
    /// Newest first, bounded, and it stands aside for anything already running.
    func recoverMissingRoutes(limit: Int = 150) async {
        guard healthKitProvider.isAvailable, recoveryTask == nil else { return }
        await runRecovery(limit: limit, oldestCheckedFirst: false, reopenWrittenOffIfIdle: false)
    }

    /// Manual "Recover Missing Maps" entry point.
    ///
    /// It **takes over** from an automatic pass rather than declining, which is the bug that made
    /// this button look broken: `recoverMissingRoutes` fires at the end of every sync, a sync now
    /// runs on every launch, and so a background pass was usually in flight while you were
    /// standing in Settings. The old guard returned immediately, the row stayed disabled behind a
    /// spinner that belonged to something else, and the tap did nothing at all.
    ///
    /// It also sweeps least-recently-checked first, so tapping again continues through the
    /// library instead of re-checking the same newest hundred and fifty every time.
    func resyncHealthKitRoutes() async {
        guard healthKitProvider.isAvailable else { return }
        recoveryTask?.cancel()
        await recoveryTask?.value
        await runRecovery(limit: 600, oldestCheckedFirst: true, reopenWrittenOffIfIdle: true)
    }

    /// Stops the pass in flight. The Settings row doubles as a stop while one is running — a
    /// ninety-second operation with no way out is not a control, it is a wait.
    func cancelRouteRecovery() {
        recoveryTask?.cancel()
    }

    /// Runs one pass under a wall-clock deadline that can actually fire.
    ///
    /// The deadline used to be a `Date()` comparison inside the consume loop, which is only
    /// reached when an item arrives — so a pass that stalled on a slow HealthKit query sat there
    /// with the spinner up and never tripped it. A watchdog that cancels the task works whether
    /// the loop is running or suspended.
    private func runRecovery(limit: Int, oldestCheckedFirst: Bool, reopenWrittenOffIfIdle: Bool) async {
        let task = Task { @MainActor in
            isRecoveringRoutes = true
            defer {
                isRecoveringRoutes = false
                routeProgress = nil
            }
            if reopenWrittenOffIfIdle { reopenWrittenOffRoutesIfNothingElsePending() }
            await hydratePendingRoutes(limit: limit, oldestCheckedFirst: oldestCheckedFirst)
        }
        recoveryTask = task
        let watchdog = Task { [hydrationDeadline] in
            try? await Task.sleep(for: .seconds(hydrationDeadline))
            task.cancel()
        }
        await task.value
        watchdog.cancel()
        if recoveryTask == task { recoveryTask = nil }
    }

    /// Re-opens routes previously ruled `.unavailable`, but only once there is nothing else left
    /// to check.
    ///
    /// Every manual tap used to reopen the lot, which is why the sweep never converged: a library
    /// where nine hundred activities were recorded by an app that writes no route would re-queue
    /// all nine hundred on every tap, hit the deadline, and finish having made no progress that
    /// survived. Written-off runs are worth a second look — a source can start writing routes, or
    /// a query can have failed in a way we mistook for absence — but as the last thing tried, not
    /// the first.
    private func reopenWrittenOffRoutesIfNothingElsePending() {
        guard pendingRouteCount == 0, writtenOffRouteCount > 0 else { return }
        let unavailable = RouteSyncStatus.unavailable.rawValue
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw == unavailable }
        )
        guard let stale = try? context.fetch(descriptor) else { return }
        for run in stale {
            run.routeStatus = .unknown
            run.routeCheckCount = 0
        }
        try? context.save()
    }

    /// Activities whose map could still turn up — the number the Settings badge should show, and
    /// the one that falls as passes run.
    var pendingRouteCount: Int {
        let unavailable = RouteSyncStatus.unavailable.rawValue
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate {
                $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw != unavailable
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Activities Apple Health holds no route for. Nothing will recover these until the app that
    /// recorded them writes one, so counting them as "missing" is what made the badge look stuck
    /// at nine hundred no matter how well a pass went.
    var writtenOffRouteCount: Int {
        let unavailable = RouteSyncStatus.unavailable.rawValue
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate {
                $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw == unavailable
            }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Core hydration. Callers own the `isRecoveringRoutes` flag so it always resets.
    private func hydratePendingRoutes(limit: Int, oldestCheckedFirst: Bool = false) async {
        let unavailable = RouteSyncStatus.unavailable.rawValue
        // Newest-first for the automatic pass: a route that is still arriving belongs to a run
        // you did today. Least-recently-checked for the manual sweep, so successive taps advance
        // through the library instead of grinding the same head of the list.
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate {
                $0.healthKitID != nil && $0.summaryPolyline == "" && $0.routeStatusRaw != unavailable
            },
            sortBy: oldestCheckedFirst
                ? [SortDescriptor(\.routeCheckedAt, order: .forward)]
                : [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else {
            lastRouteResult = "Nothing left to check"
            return
        }
        routeProgress = RouteProgress(checked: 0, total: pending.count, recovered: 0)

        let runsByID = Dictionary(
            pending.compactMap { run in run.healthKitID.map { ($0, run) } },
            uniquingKeysWith: { first, _ in first }
        )
        // Fetch workouts only from the window the pending runs fall in.
        let since = pending.map(\.startDate).min()?.addingTimeInterval(-24 * 60 * 60)
        let deadline = Date().addingTimeInterval(hydrationDeadline)

        var processed = 0, recovered = 0, noRoute = 0, failed = 0
        for await item in healthKitProvider.routeStream(forWorkoutUUIDs: Set(runsByID.keys), since: since) {
            if Task.isCancelled { break }
            if let run = runsByID[item.id] {
                run.routeCheckedAt = Date()
                run.routeCheckCount += 1
                switch item.outcome {
                case .coordinates(let coordinates, let elevations, let paces):
                    ingestor.applyRoute(coordinates, source: .healthKit, to: run,
                                        elevations: elevations, paces: paces)
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
            routeProgress = RouteProgress(checked: processed, total: pending.count, recovered: recovered)
            if processed % 20 == 0 { try? context.save() }   // let the map fill in as we go
            if Date() > deadline { break }
        }

        try? context.save()
        // Say what happened. "Recover Missing Maps" that spins and then goes quiet is
        // indistinguishable from one that failed, which is most of why this looked broken: a
        // pass can be working perfectly and still find nothing, because Apple Health genuinely
        // holds no route for those activities.
        let remaining = pendingRouteCount
        if recovered > 0 {
            lastRouteResult = "Checked \(processed) · \(recovered) map\(recovered == 1 ? "" : "s") recovered"
                + (remaining > 0 ? " · \(remaining) still to check" : "")
        } else if remaining > 0 {
            lastRouteResult = "Checked \(processed) · none had a route yet · \(remaining) to go"
        } else {
            lastRouteResult = "Checked \(processed) · no routes in Apple Health for these"
        }
        HealthKitLog.route("[Etch HealthKit] Route pass: \(recovered) recovered · \(noRoute) no-route · \(failed) failed · of \(processed)")
    }
}
