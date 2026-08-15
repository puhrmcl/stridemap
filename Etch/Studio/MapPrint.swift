import SwiftUI
import MapKit

/// An aggregate map print — the whole running history rendered as one poster.
enum MapPrintKind: String, CaseIterable, Identifiable {
    case artMap, allRuns, states, cities, countries, landmarks
    var id: String { rawValue }

    var name: String {
        switch self {
        case .artMap:    return "Wall Art"
        case .allRuns:   return "All Runs"
        case .states:    return "States"
        case .cities:    return "Cities"
        case .countries: return "Countries"
        case .landmarks: return "Landmarks"
        }
    }

    var descriptor: String {
        switch self {
        case .artMap:    return "Every route as abstract line art — no map, no words."
        case .allRuns:   return "Every route you've run, on one map."
        case .states:    return "The states you've run in, filled."
        case .cities:    return "Every city you've run in, pinned."
        case .countries: return "Every country you've run in, pinned."
        case .landmarks: return "Parks, monuments & notable places you've run."
        }
    }

    var symbol: String {
        switch self {
        case .artMap:    return "sparkles"
        case .allRuns:   return "scribble.variable"
        case .states:    return "map.fill"
        case .cities:    return "building.2.fill"
        case .countries: return "globe.americas.fill"
        case .landmarks: return "mappin.and.ellipse"
        }
    }

    /// The label beneath the headline count. Unused by the text-free Wall Art.
    var heroLabel: String {
        switch self {
        case .artMap:    return ""
        case .allRuns:   return UnitSystem.current.label.uppercased()
        case .states:    return "STATES RUN"
        case .cities:    return "CITIES RUN"
        case .countries: return "COUNTRIES RUN"
        case .landmarks: return "LANDMARKS"
        }
    }

    /// Kinds that can be narrowed to a single place (state / city / country).
    var supportsSinglePlace: Bool {
        switch self {
        case .states, .cities, .countries: return true
        case .artMap, .allRuns, .landmarks: return false
        }
    }

    /// The text-free, full-bleed abstract art (no base map, no footer).
    var isArt: Bool { self == .artMap }
}

/// A curated palette for the Wall Art print — ground + line, chosen to read as gallery-grade art.
enum MapArtPalette: String, CaseIterable, Identifiable {
    case gallery, noir, blueprint, brass, sage
    var id: String { rawValue }

    var name: String {
        switch self {
        case .gallery:   return "Gallery"
        case .noir:      return "Noir"
        case .blueprint: return "Blueprint"
        case .brass:     return "Brass"
        case .sage:      return "Sage"
        }
    }

    var ground: Color {
        switch self {
        case .gallery:   return Theme.Palette.bone
        case .noir:      return Theme.Palette.ink
        case .blueprint: return Theme.Palette.navy
        case .brass:     return Theme.Palette.ink
        case .sage:      return Theme.Palette.sage
        }
    }

    var line: Color {
        switch self {
        case .gallery:   return Theme.Palette.ink
        case .noir:      return Theme.Palette.bone
        case .blueprint: return Color(red: 0.66, green: 0.80, blue: 0.95)
        case .brass:     return Theme.Palette.brass
        case .sage:      return Theme.Palette.ink
        }
    }

    /// Whether the ground is dark (glow reads as additive light here).
    var isDark: Bool { ground.isDarkGround }
}

/// A toggleable metric on the single-state print.
enum StateMetric: String, CaseIterable, Identifiable {
    case runs, miles, cities, highElev, lowElev
    var id: String { rawValue }
    var name: String {
        switch self {
        case .runs:     return "Runs"
        case .miles:    return "Miles"
        case .cities:   return "Cities"
        case .highElev: return "High Elev"
        case .lowElev:  return "Low Elev"
        }
    }
    /// Needs a terrain-elevation lookup for the state's runs.
    var needsElevation: Bool { self == .highElev || self == .lowElev }
}

/// The Wall Art rendering treatment.
enum MapArtStyle: String, CaseIterable, Identifiable {
    case lines, glow, points, clusters
    var id: String { rawValue }
    var name: String {
        switch self {
        case .lines:    return "Lines"
        case .glow:     return "Glow"
        case .points:   return "Points"
        case .clusters: return "Clusters"
        }
    }
}

/// Everything needed to render one aggregate print: the kind, the runs in scope, and a framed
/// region + title. Build one with `make(kind:runs:)`, which derives the region and a scope name.
struct MapPrintRequest {
    var kind: MapPrintKind
    var runs: [Run]
    var title: String
    var region: MKCoordinateRegion
    var orientation: StudioOrientation = .portrait
    /// When set, the outline of this US state is drawn behind the routes (single-state prints).
    var boundaryStateName: String? = nil
    var artPalette: MapArtPalette = .gallery
    var artStyle: MapArtStyle = .lines
    /// Single-state print options.
    var isSingleState: Bool = false
    var stateMetrics: [StateMetric] = StateMetric.allCases
    var titleOverride: String? = nil
    var routeColor: Color = Theme.Palette.blue
    var ground: Color = Theme.Palette.bone

    /// The title shown, honouring a user edit.
    var displayTitle: String { (titleOverride?.isEmpty == false ? titleOverride : nil) ?? title }

    /// Full-bleed state poster size (map fills the page; metrics float over the bottom).
    var statePosterSize: CGSize {
        orientation == .landscape ? CGSize(width: 1500, height: 1000) : CGSize(width: 1000, height: 1400)
    }

    /// Builds the enabled state metrics as (label, value), given fetched high/low elevation.
    func stateFooterMetrics(elevHigh: Double?, elevLow: Double?) -> [(label: String, value: String)] {
        let stats = RunStatistics(runs)
        return stateMetrics.compactMap { metric -> (label: String, value: String)? in
            switch metric {
            case .runs:   return ("RUNS", stats.totalRuns.formatted())
            case .miles:  return (UnitSystem.current.label.uppercased(),
                                  Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0))))
            case .cities: return ("CITIES", stats.cities.count.formatted())
            case .highElev: return elevHigh.map { ("HIGH ELEV", Format.elevation($0)) }
            case .lowElev:  return elevLow.map { ("LOW ELEV", Format.elevation($0)) }
            }
        }
    }

    /// The runs that actually carry a drawable route.
    var mapped: [Run] { runs.filter(\.hasRoute) }

    /// Nominal poster size. Wall Art is a full-bleed 2:3 / 3:2; the rest use the composition size.
    var posterNominalSize: CGSize {
        if kind.isArt {
            return orientation == .landscape ? CGSize(width: 1500, height: 1000)
                                             : CGSize(width: 1000, height: 1500)
        }
        if isSingleState { return statePosterSize }
        return MapPrintComposition.nominalSize(orientation)
    }

    static func make(kind: MapPrintKind, runs: [Run]) -> MapPrintRequest {
        MapPrintRequest(kind: kind, runs: runs, title: title(for: kind, runs: runs),
                        region: region(for: kind, runs: runs))
    }

    // MARK: Titles

    private static func title(for kind: MapPrintKind, runs: [Run]) -> String {
        if kind == .states { return "United States" }
        return scopeTitle(for: runs)
    }

    /// The tightest place that contains the runs: a single city, else state, else country, else
    /// a generic mark.
    private static func scopeTitle(for runs: [Run]) -> String {
        let stats = RunStatistics(runs)
        if stats.cities.count == 1, let c = stats.cities.first { return c }
        if stats.states.count == 1, let s = stats.states.first { return s }
        if stats.countries.count == 1, let c = stats.countries.first { return c }
        return "Your Runs"
    }

    // MARK: Region

    private static func region(for kind: MapPrintKind, runs: [Run]) -> MKCoordinateRegion {
        switch kind {
        case .artMap:
            // Frame the dense core, not the full spread, so outlier trips don't shrink the art.
            return denseRegion(of: runs.filter(\.hasRoute))
        case .allRuns:
            return boundingRegion(of: runs.filter(\.hasRoute))
        case .states:
            // Continental US; Alaska/Hawaii are drawn but the framing stays on the lower 48.
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
            )
        case .cities:
            return boundingRegion(ofCoordinates: RunStatistics(runs).travelPlaces.map(\.coordinate))
        case .countries:
            return boundingRegion(ofCoordinates: RunStatistics(runs).countryPlaces.map(\.coordinate))
        case .landmarks:
            return boundingRegion(ofCoordinates: RunStatistics(runs).landmarkPlaces.map(\.coordinate))
        }
    }

    /// A region framing the *core* of activity — the 5th–95th percentile of run centres — so a
    /// handful of far-flung trips don't collapse the everyday training area into specks.
    private static func denseRegion(of runs: [Run]) -> MKCoordinateRegion {
        let centers = runs.map {
            CLLocationCoordinate2D(latitude: ($0.minLatitude + $0.maxLatitude) / 2,
                                   longitude: ($0.minLongitude + $0.maxLongitude) / 2)
        }
        guard centers.count > 3 else { return boundingRegion(of: runs) }
        let lats = centers.map(\.latitude).sorted()
        let lons = centers.map(\.longitude).sorted()
        func pct(_ a: [Double], _ p: Double) -> Double {
            a[min(a.count - 1, max(0, Int((Double(a.count - 1) * p).rounded())))]
        }
        return region(minLat: pct(lats, 0.05), maxLat: pct(lats, 0.95),
                      minLon: pct(lons, 0.05), maxLon: pct(lons, 0.95))
    }

    /// A region framing every run's cached bounding box, with padding.
    private static func boundingRegion(of runs: [Run]) -> MKCoordinateRegion {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        var any = false
        for r in runs {
            minLat = min(minLat, r.minLatitude); maxLat = max(maxLat, r.maxLatitude)
            minLon = min(minLon, r.minLongitude); maxLon = max(maxLon, r.maxLongitude)
            any = true
        }
        guard any else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                                      span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40))
        }
        return region(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    private static func boundingRegion(ofCoordinates coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                                      span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40))
        }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        return region(minLat: lats.min()!, maxLat: lats.max()!, minLon: lons.min()!, maxLon: lons.max()!)
    }

    private static func region(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.3, 0.05)
        let lonDelta = max((maxLon - minLon) * 1.3, 0.05)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    // MARK: Footer data

    /// The footer strings for this print. `visitedStateCount` is only meaningful for `.states`.
    func footerData(visitedStateCount: Int) -> MapPrintFooterData {
        let stats = RunStatistics(runs)
        let miles = Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))
        let milesLabel = UnitSystem.current.label.uppercased()
        let unitPair: (label: String, value: String) = (milesLabel, miles)
        let runsPair: (label: String, value: String) = ("RUNS", stats.totalRuns.formatted())
        let citiesPair: (label: String, value: String) = ("CITIES", stats.cities.count.formatted())
        let statesPair: (label: String, value: String) = ("STATES", stats.states.count.formatted())

        let heroValue: String
        let subStats: [(label: String, value: String)]
        switch kind {
        case .artMap, .allRuns:
            heroValue = miles
            subStats = [runsPair, citiesPair, statesPair]
        case .states:
            heroValue = visitedStateCount.formatted()
            subStats = [unitPair, runsPair, citiesPair]
        case .cities:
            heroValue = stats.cities.count.formatted()
            subStats = [unitPair, runsPair, statesPair]
        case .countries:
            heroValue = stats.countries.count.formatted()
            subStats = [unitPair, runsPair, citiesPair]
        case .landmarks:
            heroValue = RunStatistics(runs).landmarkPlaces.count.formatted()
            subStats = [unitPair, runsPair, citiesPair]
        }

        return MapPrintFooterData(
            title: title, heroValue: heroValue, heroLabel: kind.heroLabel, subStats: subStats,
            ground: ground, ink: Theme.Palette.ink,
            subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.blue
        )
    }
}

/// Dumb, pre-resolved strings + palette for the aggregate print footer.
struct MapPrintFooterData {
    var title: String
    var heroValue: String
    var heroLabel: String
    var subStats: [(label: String, value: String)]
    var ground: Color
    var ink: Color
    var subtle: Color
    var accent: Color
}
