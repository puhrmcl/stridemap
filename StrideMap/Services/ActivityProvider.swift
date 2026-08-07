import Foundation

/// Abstraction over any source of running activities. New ecosystems (Garmin, COROS,
/// Polar, Suunto, …) can be added by conforming a new type — the import service and the
/// UI never change, because everything downstream speaks `ImportedActivity` / `Run`.
@MainActor
protocol ActivityProvider {

    /// Which ecosystem this provider represents.
    var source: ActivitySource { get }

    /// Whether the provider is usable right now (framework present, user connected, …).
    var isAvailable: Bool { get }

    /// Whether this provider contributes primary activities (HealthKit) or only enriches
    /// existing ones (Strava). Enrichment providers never create runs that don't already
    /// have a strong match — see `ActivityImportService`.
    var role: ProviderRole { get }

    /// Fetches activities. When `since` is provided, only newer activities need be
    /// returned (incremental sync); providers may ignore it and return everything.
    func fetchActivities(since: Date?) async throws -> [ImportedActivity]
}

enum ProviderRole {
    /// Contributes the canonical set of runs (e.g. HealthKit).
    case primary
    /// Adds metadata to / de-duplicates against primary runs (e.g. Strava).
    case enrichment
}

extension ActivityProvider {
    var role: ProviderRole { .primary }
}
