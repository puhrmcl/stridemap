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
    /// The originating file's stable id (TCX `<Id>`, or a synthetic id for GPX) — the
    /// de-duplication key for file imports, so re-importing the same export is idempotent.
    /// Defaulted so existing runs migrate cleanly.
    var sourceExternalID: String? = nil

    /// How this run reached Etch (Apple Health, Strava API, GPX/TCX/FIT file, …), distinct
    /// from `provider`/`originApp`. Defaulted for clean migration; nil on runs imported
    /// before it existed.
    var importMethodRaw: String? = nil

    // MARK: Core

    var name: String
    /// True once the user has renamed this run, so provider re-syncs don't overwrite the
    /// custom title. Defaulted so existing runs migrate cleanly.
    var nameIsCustom: Bool = false
    var startDate: Date
    var distance: Double        // metres
    var movingTime: Int         // seconds
    var elapsedTime: Int        // seconds
    var elevationGain: Double

    /// Encoded (Google-format) polyline of the route.
    var summaryPolyline: String

    /// The source's recorded altitude profile (metres) sampled along the route, stored compactly
    /// via `ElevationSeries` (downsampled, comma-separated). Empty when the source carried no
    /// per-point elevation stream — the elevation chart then falls back to terrain data. Defaulted
    /// so existing runs migrate cleanly.
    var elevationSeriesRaw: String = ""

    // MARK: Route synchronisation state

    /// Tracks the route independently of the workout. A HealthKit workout can exist in Etch
    /// while its `HKWorkoutRoute` is still pending — routes often arrive after the workout
    /// (Nike Run Club writes the workout first, the route seconds-to-minutes later). Default
    /// `.unknown` so runs imported before this field existed get re-checked once.
    var routeStatusRaw: String = RouteSyncStatus.unknown.rawValue
    /// Where the current route came from, so a future Strava / GPX fallback can decide
    /// whether to override or defer to it.
    var routeSourceRaw: String?
    /// Last time we queried HealthKit for this run's route. Drives backoff so we don't
    /// rescan the whole history every launch.
    var routeCheckedAt: Date?
    /// Number of route lookups performed for this run — used to stop retrying eventually.
    var routeCheckCount: Int = 0

    // MARK: Rich metrics (may be absent depending on source)

    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergy: Double?       // kcal
    var averageCadence: Double?     // steps/min
    /// Top speed in metres per second, when the source recorded it (Strava `max_speed`, TCX
    /// `MaximumSpeed`). Nil when unknown. Defaulted for clean migration.
    var maxSpeed: Double? = nil

    // MARK: Weather (when the source recorded it)

    /// Temperature at the time of the run, in Celsius. Defaulted for clean migration.
    var weatherTemperatureC: Double? = nil
    /// Normalized `WeatherCondition` raw value, when known (HealthKit only; Strava gives
    /// temperature but no condition).
    var weatherConditionRaw: String? = nil

    // MARK: Location metadata

    var city: String?
    var state: String?
    var country: String?

    /// The nearby point of interest this run started at/next to (a park, university, museum,
    /// …), if any — powers the Landmarks overlay. Nil means "no landmark here". `landmarkChecked`
    /// records that we've already looked, so a run with no nearby POI isn't re-queried forever.
    var landmarkName: String? = nil
    var landmarkChecked: Bool = false

    // MARK: Classification

    var sportType: String
    /// Normalized activity kind (run/walk/hike/ride/…). Defaulted to `run` so existing runs
    /// migrate cleanly and the running-only UI is unaffected; parsed from every source so
    /// walking/hiking/cycling can be surfaced later without re-importing.
    var activityTypeRaw: String = ActivityType.run.rawValue
    var isRace: Bool
    /// True once the user has manually set race status, so provider re-syncs don't override
    /// their choice. Defaulted so existing runs migrate cleanly.
    var raceIsCustom: Bool = false
    var isCommute: Bool
    var isTrail: Bool
    /// True for treadmill / indoor runs (HealthKit's `HKMetadataKeyIndoorWorkout`). These carry
    /// no GPS route, so the UI represents them with an indoor treatment instead of a map.
    /// Defaulted so existing runs migrate cleanly.
    var isIndoor: Bool = false

    /// When true, this activity is kept out of aggregate totals and records (the home totals,
    /// achievements, PRs, year sums) while still appearing on the map, in the timeline, and in
    /// Studio. Set by the user when adding a race from the library — a hand-entered official time
    /// they may not want inflating their tracked mileage or PR table. Defaulted false so every
    /// existing run counts and migrates cleanly.
    var excludedFromTotals: Bool = false

    /// User chose to hide this run from Etch. Unlike deletion, it stays in the store — so a synced
    /// run isn't re-imported as new on the next sync — but is excluded from every browsing surface
    /// (map, timeline, achievements, Studio, totals). Reversible from Settings › Hidden Runs.
    /// Defaulted false so existing runs migrate cleanly.
    var isHidden: Bool = false

    /// True when the user hand-placed this run's location on the map — an indoor/treadmill run (or
    /// a GPS-less import) that no source gave coordinates for. Defaulted so existing runs migrate
    /// cleanly. Drives the treadmill map pin and lets the run count toward geographic reach.
    var locationIsManual: Bool = false

    // MARK: User & future-proofing

    var gear: String?
    var notes: String?
    /// Race bib number, hand-entered in the activity's Edit sheet ("9478", "A123"). Shown on
    /// posters as a data point when set. Defaulted so existing runs migrate cleanly.
    var bibNumber: String = ""
    /// Where the runner finished — free text so "127", "4th", or "3rd F35-39" all work. Shown as
    /// a poster data point; a bare number renders as an ordinal ("127th"). Defaulted so existing
    /// runs migrate cleanly.
    var finishPlace: String = ""
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
        isIndoor: Bool = false,
        excludedFromTotals: Bool = false,
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
        self.isIndoor = isIndoor
        self.excludedFromTotals = excludedFromTotals
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

// MARK: - Route synchronisation

/// The lifecycle of a run's route, tracked separately from the workout so a late-arriving
/// `HKWorkoutRoute` can be recovered without re-importing (or duplicating) the run.
enum RouteSyncStatus: String {
    /// Never checked — either brand new or imported before route tracking existed.
    case unknown
    /// Checked, no route yet, but it may still arrive (recent run).
    case pending
    /// Route successfully imported.
    case available
    /// Checked and the route is genuinely unavailable from this source (source wrote no
    /// `HKWorkoutRoute`) — e.g. Nike Run Club, treadmill/indoor runs.
    case unavailable
    /// The route query errored; distinct from `.unavailable` so it's retried on re-sync.
    case failed
}

/// Where a route came from. HealthKit is canonical today; Strava and file imports are
/// future fallbacks for workouts HealthKit never received a route for.
enum RouteSource: String {
    case healthKit
    case strava
    case imported
}

// MARK: - Provenance helpers

extension Run {

    var routeStatus: RouteSyncStatus {
        get { RouteSyncStatus(rawValue: routeStatusRaw) ?? .unknown }
        set { routeStatusRaw = newValue.rawValue }
    }

    var routeSource: RouteSource? {
        get { routeSourceRaw.flatMap(RouteSource.init(rawValue:)) }
        set { routeSourceRaw = newValue?.rawValue }
    }
}

extension Run {

    var provider: ActivitySource {
        get { ActivitySource(rawValue: providerRaw) }
        set { providerRaw = newValue.rawValue }
    }

    var originApp: ActivitySource? {
        get { originAppRaw.map { ActivitySource(rawValue: $0) } }
        set { originAppRaw = newValue?.rawValue }
    }

    var importMethod: ImportMethod? {
        get { importMethodRaw.flatMap(ImportMethod.init(rawValue:)) }
        set { importMethodRaw = newValue?.rawValue }
    }

    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRaw) ?? .run }
        set { activityTypeRaw = newValue.rawValue }
    }

    /// The recorded altitude profile (metres) along the route, decoded from storage. Assigning
    /// re-encodes and downsamples it. Empty when the source recorded no elevation stream.
    var elevationSeries: [Double] {
        get { ElevationSeries.decode(elevationSeriesRaw) }
        set { elevationSeriesRaw = ElevationSeries.encode(newValue) }
    }

    /// Whether this run carries a source-recorded elevation profile (vs. needing terrain data).
    var hasElevationSeries: Bool { !elevationSeriesRaw.isEmpty }

    /// The source shown to the user: the true origin app when known, otherwise the
    /// importing provider. If the run has been enriched by Strava we still surface the
    /// original recording app, because that's where the run actually came from.
    var displaySource: ActivitySource {
        originApp ?? provider
    }

    var isStravaLinked: Bool { stravaActivityID != nil }
}

// MARK: - Collection helpers

extension Sequence where Element == Run {
    /// Drops activities the user marked as not counting toward aggregate totals and records.
    /// Applied where headline numbers, achievements, PRs, and year sums are computed — never to
    /// the map, timeline, or Studio, where the activity still belongs.
    var countingTotals: [Run] { filter { !$0.excludedFromTotals } }
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

    /// A route-less run with no location at all — an indoor/treadmill run, or an import without
    /// GPS — that the user could place on the map by hand.
    var needsLocation: Bool { !hasRoute && startCoordinate == nil }

    /// Hand-place this run at a coordinate: set the start point and a tiny bounding box so the map
    /// and offline place-name backfill treat it like any located run, and clear stale place names
    /// so they re-derive from the new spot.
    func setManualLocation(_ coordinate: CLLocationCoordinate2D) {
        startLatitude = coordinate.latitude
        startLongitude = coordinate.longitude
        let d = 0.0009   // ~100 m box
        minLatitude = coordinate.latitude - d
        maxLatitude = coordinate.latitude + d
        minLongitude = coordinate.longitude - d
        maxLongitude = coordinate.longitude + d
        locationIsManual = true
        city = nil; state = nil; country = nil
        landmarkChecked = false
        updatedAt = Date()
    }

    var placeLabel: String {
        [city, state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var weatherCondition: WeatherCondition? {
        weatherConditionRaw.flatMap { WeatherCondition(rawValue: $0) }
    }

    var hasWeather: Bool { weatherTemperatureC != nil || weatherConditionRaw != nil }

    /// A metadata line for the poster, e.g. "58°F · Clear".
    func weatherLine(unit: UnitSystem = .current) -> String? {
        WeatherFormat.line(temperatureC: weatherTemperatureC, condition: weatherCondition, unit: unit)
    }

    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
    }
}
