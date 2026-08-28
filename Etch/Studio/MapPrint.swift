import SwiftUI
import MapKit
import UIKit

/// An aggregate map print — the whole running history rendered as one poster.
enum MapPrintKind: String, CaseIterable, Identifiable {
    case artMap, allRuns, states, cities, countries, landmarks
    var id: String { rawValue }

    var name: String {
        switch self {
        case .artMap:    return "Anthology"
        case .allRuns:   return "All Runs"
        case .states:    return "States"
        case .cities:    return "Cities"
        case .countries: return "Countries"
        case .landmarks: return "Landmarks"
        }
    }

    var descriptor: String {
        switch self {
        case .artMap:    return "The body of work as one abstract piece — no map, no words."
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
    case gallery, noir, blueprint, brass, sage, rose, forest, graphite
    var id: String { rawValue }

    var name: String {
        switch self {
        case .gallery:   return "Gallery"
        case .noir:      return "Noir"
        case .blueprint: return "Blueprint"
        case .brass:     return "Brass"
        case .sage:      return "Sage"
        case .rose:      return "Rose"
        case .forest:    return "Forest"
        case .graphite:  return "Graphite"
        }
    }

    var ground: Color {
        switch self {
        case .gallery:   return Theme.Palette.bone
        case .noir:      return Theme.Palette.ink
        case .blueprint: return Theme.Palette.navy
        case .brass:     return Theme.Palette.ink
        case .sage:      return Theme.Palette.sage
        case .rose:      return Theme.Palette.bone
        case .forest:    return Theme.Palette.forest
        case .graphite:  return Theme.Palette.stone
        }
    }

    var line: Color {
        switch self {
        case .gallery:   return Theme.Palette.ink
        case .noir:      return Theme.Palette.bone
        case .blueprint: return Color(red: 0.66, green: 0.80, blue: 0.95)
        case .brass:     return Theme.Palette.brass
        case .sage:      return Theme.Palette.ink
        case .rose:      return Color(red: 0.71, green: 0.20, blue: 0.29)   // #B5344A deep rose
        case .forest:    return Theme.Palette.sage
        case .graphite:  return Theme.Palette.ink
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
    /// A contact sheet — each run its own normalized glyph in its own cell.
    case grid
    /// Every run's elevation profile stacked as overlapping ridgelines — a mountain chain of
    /// the whole history.
    case ridgeline
    /// The years as tree rings — every run a tick placed by its day in the year.
    case rings
    /// The whole history as one continuous line, wrapped across the sheet — each activity a
    /// stretch of it proportional to its distance, carrying its own elevation profile.
    case thread
    /// One band per year, every activity a bar at its day of the year, height by distance —
    /// the years as sediment layers.
    case strata
    var id: String { rawValue }
    var name: String {
        switch self {
        case .grid:          return "Grid"
        case .ridgeline:     return "Ridgeline"
        case .rings:         return "Rings"
        case .thread:        return "Thread"
        case .strata:        return "Strata"
        }
    }
    var descriptor: String {
        switch self {
        case .grid:          return "Every run as its own glyph, in a grid."
        case .ridgeline:     return "Every climb stacked — your elevations as one mountain chain."
        case .rings:         return "Your years as tree rings — every run a mark in its season."
        case .thread:        return "Every mile as one unbroken line."
        case .strata:        return "Your years in layers — every day's distance, banked."
        }
    }
    /// A glyph that gestures at the composition, for the style tiles. The rendered thumbnail is
    /// the real preview; the symbol only has to tell five tiles apart at a glance.
    var symbol: String {
        switch self {
        case .grid:      return "square.grid.3x3"
        case .ridgeline: return "mountain.2"
        case .rings:     return "circle.circle"
        case .thread:    return "scribble.variable"
        case .strata:    return "chart.bar.fill"
        }
    }
}

/// Where the Anthology's small data line sits — or nowhere.
///
/// The Anthology began text-free on principle, and the principle half-survives: the caption is
/// off never the piece's subject, one quiet line in the margin saying what the body of work is.
/// Left and right set the line vertically along that edge, the way a plate mark runs up the
/// margin of an etching.
enum ArtCaptionEdge: String, CaseIterable, Identifiable {
    case hidden, top, bottom, left, right
    var id: String { rawValue }
    var name: String {
        switch self {
        case .hidden: return "Off"
        case .top:    return "Top"
        case .bottom: return "Bottom"
        case .left:   return "Left"
        case .right:  return "Right"
        }
    }
}

/// Line weight for the Wall Art — a global multiplier on every stroke/point.
enum MapArtWeight: String, CaseIterable, Identifiable {
    case fine, medium, bold
    var id: String { rawValue }
    var name: String {
        switch self {
        case .fine:   return "Fine"
        case .medium: return "Medium"
        case .bold:   return "Bold"
        }
    }
    var multiplier: CGFloat {
        switch self {
        case .fine:   return 0.6
        case .medium: return 1.0
        case .bold:   return 1.7
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
    var artStyle: MapArtStyle = .grid
    var artWeight: MapArtWeight = .medium
    /// The City Index's hero — the tour-poster layout: an image across the top of the sheet,
    /// the cities listed like dates beneath it.
    enum CityIndexHero: String, CaseIterable, Identifiable {
        case none, map, photo
        var id: String { rawValue }
        var name: String {
            switch self {
            case .none:  return "Type only"
            case .map:   return "Map"
            case .photo: return "Photo"
            }
        }
    }
    var cityIndexHero: CityIndexHero = .none
    /// The chosen photograph when the hero is `.photo`.
    var cityIndexPhoto: UIImage? = nil
    /// Whether each city carries its totals (activities · miles) or just the count.
    var cityIndexTotals: Bool = true

    /// The Anthology's data line: where it sits, and which halves it carries.
    var artCaptionEdge: ArtCaptionEdge = .hidden
    var artCaptionShowsTitle: Bool = true
    var artCaptionShowsSummary: Bool = true

    /// Cities drawn as a typographic index — every city named, ranked by visits — instead of
    /// pins on a map. The index is composed entirely of our own type on our own ground, which
    /// is what makes it the *printable* form of the cities piece: the pinned form draws on an
    /// Apple snapshot, licensed for screens and not for merchandise.
    var cityIndex: Bool = false
    /// Single-state print options.
    var isSingleState: Bool = false
    var stateMetrics: [StateMetric] = StateMetric.allCases
    var titleOverride: String? = nil
    var routeColor: Color = Theme.Palette.blue
    var ground: Color = Theme.Palette.bone
    /// States aggregate only: draw a clean US choropleth on a plain ground (no Apple base map), so
    /// Canada and Mexico don't appear. Off keeps the base-map snapshot with surrounding context.
    var statesUSAOnly: Bool = false
    /// When false, the poster is the map panel alone — no footer title / stats / caption.
    var showFooter: Bool = true

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

    /// The City Index composes on the same full-bleed 2:3 sheet the art styles use.
    var posterIndexSize: CGSize {
        orientation == .landscape ? CGSize(width: 1500, height: 1000)
                                  : CGSize(width: 1000, height: 1500)
    }

    /// Nominal poster size. The Anthology is a full-bleed 2:3 / 3:2; the rest use the composition size.
    var posterNominalSize: CGSize {
        if kind.isArt {
            return orientation == .landscape ? CGSize(width: 1500, height: 1000)
                                             : CGSize(width: 1000, height: 1500)
        }
        if isSingleState { return statePosterSize }
        // Map-only: the square panel is the whole poster.
        if !showFooter { return CGSize(width: MapPrintComposition.width, height: MapPrintComposition.artHeight) }
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

    /// The footer strings for this print. `visitedStateNames` (the states matched by point-in-polygon)
    /// is only meaningful for `.states`, where they're listed in place of a hero number.
    func footerData(visitedStateNames: [String] = []) -> MapPrintFooterData {
        let stats = RunStatistics(runs)
        let miles = Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))
        let milesLabel = UnitSystem.current.label.uppercased()
        let unitPair: (label: String, value: String) = (milesLabel, miles)
        let runsPair: (label: String, value: String) = ("RUNS", stats.totalRuns.formatted())
        let citiesPair: (label: String, value: String) = ("CITIES", stats.cities.count.formatted())
        let statesPair: (label: String, value: String) = ("STATES", stats.states.count.formatted())

        var heroValue = ""
        var heroList: [String]? = nil
        let subStats: [(label: String, value: String)]
        switch kind {
        case .artMap, .allRuns:
            heroValue = miles
            subStats = [runsPair, citiesPair, statesPair]
        case .states:
            // List the state names instead of a single count; the count moves to a fourth stat.
            heroList = visitedStateNames
            let statesCount: (label: String, value: String) = ("STATES", visitedStateNames.count.formatted())
            subStats = [unitPair, runsPair, citiesPair, statesCount]
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
            title: title, heroValue: heroValue, heroLabel: kind.heroLabel, heroList: heroList,
            subStats: subStats, ground: ground, ink: Theme.Palette.ink,
            subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.blue
        )
    }
}

/// Dumb, pre-resolved strings + palette for the aggregate print footer.
struct MapPrintFooterData {
    var title: String
    var heroValue: String
    var heroLabel: String
    /// When set (states print), these names are listed in place of the hero number.
    var heroList: [String]? = nil
    var subStats: [(label: String, value: String)]
    var ground: Color
    var ink: Color
    var subtle: Color
    var accent: Color
}
