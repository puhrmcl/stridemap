import Foundation
import SwiftData
import CoreLocation

/// The single place where a normalized `ImportedActivity` becomes a canonical `Run`:
/// de-duplication, cross-provider matching, merge/enrichment, run construction, and route
/// attachment all live here.
///
/// Extracted from `SyncService` so *every* ingestion path shares one dedup brain — live
/// HealthKit/Strava sync today, file/ZIP import next. If two paths ever diverged on how they
/// matched or merged, the map would show the same run twice; keeping the logic in one type is
/// what prevents that.
///
/// The ingestor only ever inserts/mutates in the provided `ModelContext`; it never saves.
/// Callers own the save cadence (batched writes, progress checkpoints) so a large import can
/// stream progress without this type dictating when persistence happens.
@MainActor
final class ActivityIngestor {

    /// What happened to an ingested activity — a brand-new run, or a merge into an existing one.
    enum Outcome {
        case inserted
        case merged
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Primary ingestion (HealthKit and other run-creating sources)

    /// Creates a run from a primary provider activity. De-duplicates on the HealthKit id,
    /// and — so ordering never matters — merges into a matching run that some other
    /// provider (e.g. Strava) created first. Returns `.inserted` only when a new run was added.
    func ingestPrimary(_ activity: ImportedActivity) throws -> Outcome {
        let hkID = activity.externalID
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.healthKitID == hkID })
        descriptor.fetchLimit = 1
        if try !context.fetch(descriptor).isEmpty { return .merged }

        // A provider-created run without a HealthKit id may be this same activity.
        if let match = try bestMatch(for: activity), match.healthKitID == nil {
            mergeHealthKit(activity, into: match)
            return .merged
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
        return .inserted
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

    // MARK: Enrichment ingestion (Strava)

    /// Merges a Strava activity into a matching run, or creates a standalone run when no
    /// HealthKit counterpart exists. Returns `.inserted` only when a *new* run was added.
    ///
    /// Any provider-specific detail fetch (Strava's per-activity city/state call) is the
    /// caller's responsibility and must happen *before* this is invoked — the ingestor stays
    /// provider-agnostic and never makes network calls.
    func ingestEnrichment(_ activity: ImportedActivity) throws -> Outcome {
        // Already linked to a run from a previous sync? Refresh lightweight metadata only.
        if let stravaID = Int64(activity.externalID),
           let existing = try runLinkedToStrava(stravaID) {
            merge(activity, into: existing)
            return .merged
        }

        // Try to match an existing (HealthKit) run that isn't yet Strava-linked.
        if let match = try bestMatch(for: activity), match.stravaActivityID == nil {
            merge(activity, into: match)
            return .merged
        }

        // No match — this is a Strava-only run. Create it.
        let run = makeRun(from: activity)
        run.stravaActivityID = Int64(activity.externalID)
        if run.hasRoute {
            run.routeStatus = .available
            run.routeSource = .strava
        }
        context.insert(run)
        return .inserted
    }

    private func runLinkedToStrava(_ stravaID: Int64) throws -> Run? {
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.stravaActivityID == stravaID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Merges Strava metadata into an existing run, keeping the richest available value
    /// for each field and never overwriting good data with nil.
    private func merge(_ activity: ImportedActivity, into run: Run) {
        if let stravaID = Int64(activity.externalID) { run.stravaActivityID = stravaID }

        // Strava titles are almost always more descriptive than HealthKit's — unless the user
        // has given this run their own title, which we never overwrite.
        if !run.nameIsCustom, let name = activity.name, !name.isEmpty { run.name = name }
        if let gear = activity.gear { run.gear = gear }
        if let notes = activity.notes, run.notes == nil { run.notes = notes }
        if !run.raceIsCustom, activity.isRace == true { run.isRace = true }
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

    // MARK: Matching

    /// Finds the best-scoring existing run within a time window around the activity.
    func bestMatch(for activity: ImportedActivity) throws -> Run? {
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

    /// Caches the run's start point and bounding box from its coordinates, so the map and
    /// stats never have to decode the polyline just to frame it.
    func applyGeometry(_ coordinates: [CLLocationCoordinate2D], to run: Run) {
        let box = RouteGeometry.boundingBox(of: coordinates, fallbackStart: coordinates.first)
        run.startLatitude = coordinates.first?.latitude ?? run.startLatitude
        run.startLongitude = coordinates.first?.longitude ?? run.startLongitude
        run.minLatitude = box.minLat
        run.maxLatitude = box.maxLat
        run.minLongitude = box.minLon
        run.maxLongitude = box.maxLon
    }

    /// Attaches a recovered route to a run and records provenance/state. Central so every
    /// path (initial import, enrichment merge, backfill) writes route state consistently.
    func applyRoute(
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
