import SwiftUI
import MapKit

/// An aggregate map print — the whole running history rendered as one poster.
enum MapPrintKind: String, CaseIterable, Identifiable {
    case allRuns, states, cities, countries, landmarks
    var id: String { rawValue }

    var name: String {
        switch self {
        case .allRuns:   return "All Runs"
        case .states:    return "States"
        case .cities:    return "Cities"
        case .countries: return "Countries"
        case .landmarks: return "Landmarks"
        }
    }

    var descriptor: String {
        switch self {
        case .allRuns:   return "Every route you've run, on one map."
        case .states:    return "The states you've run in, filled."
        case .cities:    return "Every city you've run in, pinned."
        case .countries: return "Every country you've run in, pinned."
        case .landmarks: return "Parks, monuments & notable places you've run."
        }
    }

    var symbol: String {
        switch self {
        case .allRuns:   return "scribble.variable"
        case .states:    return "map.fill"
        case .cities:    return "building.2.fill"
        case .countries: return "globe.americas.fill"
        case .landmarks: return "mappin.and.ellipse"
        }
    }

    /// The label beneath the headline count.
    var heroLabel: String {
        switch self {
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
        case .allRuns, .landmarks: return false
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
    var routeColor: Color = Theme.Palette.blue
    var ground: Color = Theme.Palette.bone

    /// The runs that actually carry a drawable route.
    var mapped: [Run] { runs.filter(\.hasRoute) }

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
        case .states:
            // Continental US; Alaska/Hawaii are drawn but the framing stays on the lower 48.
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
            )
        case .allRuns:
            return boundingRegion(of: runs.filter(\.hasRoute))
        case .cities:
            return boundingRegion(ofCoordinates: RunStatistics(runs).travelPlaces.map(\.coordinate))
        case .countries:
            return boundingRegion(ofCoordinates: RunStatistics(runs).countryPlaces.map(\.coordinate))
        case .landmarks:
            return boundingRegion(ofCoordinates: RunStatistics(runs).landmarkPlaces.map(\.coordinate))
        }
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
        case .allRuns:
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
