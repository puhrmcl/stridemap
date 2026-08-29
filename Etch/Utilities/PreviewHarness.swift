import SwiftUI
import SwiftData
import CoreLocation

/// Drives the app to a named screen with a synthetic history, so CI can screenshot any surface
/// without a device, a TestFlight build, or a real Apple Health library. Activated only by the
/// `ETCH_PREVIEW` environment variable, which nothing but the preview workflow sets — in a
/// normal launch every symbol here is inert.
///
/// The point is the feedback loop: a design change can be seen in about five minutes, by the
/// person who made it, instead of waiting on a build-and-install cycle to find out the type
/// clips.
enum PreviewHarness {

    /// The screen to open, e.g. `studio`, `archive`, `yearbook`, `map-studio`.
    static var screen: String? {
        ProcessInfo.processInfo.environment["ETCH_PREVIEW"]
    }

    static var isActive: Bool { screen?.isEmpty == false }

    /// Seeds a synthetic two-year history: enough volume for the Archive's gates, a spread of
    /// geography for Constellation, real elevation profiles for Ridgeline, and a handful of
    /// races so the finisher surfaces have something to show.
    @MainActor
    static func seed(into context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Run>())) ?? 0
        guard existing == 0 else { return }

        // Home turf plus a few travel cities, so place-based views have shape.
        let places: [(city: String, state: String, lat: Double, lon: Double)] = [
            ("Gilbert", "Arizona", 33.352, -111.789),
            ("Gilbert", "Arizona", 33.361, -111.801),
            ("Mesa", "Arizona", 33.415, -111.831),
            ("Phoenix", "Arizona", 33.448, -112.074),
            ("San Diego", "California", 32.716, -117.161),
            ("Chicago", "Illinois", 41.882, -87.623),
            ("Boulder", "Colorado", 40.015, -105.271)
        ]
        let calendar = Calendar.current
        var seedValue: UInt64 = 42
        // A small deterministic generator: the same history every run, so a screenshot diff
        // reflects the code change and nothing else.
        func random() -> Double {
            seedValue = seedValue &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((seedValue >> 33) % 10_000) / 10_000
        }

        // Enough volume to be honest: an Archive style that looks good on 80 runs can still
        // fall apart on a real library, and the person this is built for has over a thousand.
        for index in 0..<220 {
            // A real history is lopsided: most runs start within a few miles of home, and trips
            // punctuate them. An even spread across seven cities made every place-based
            // composition read as uniform noise, and framed Constellation on a continent when
            // the piece is really about a neighbourhood.
            let roll = random()
            let place: (city: String, state: String, lat: Double, lon: Double)
            switch roll {
            case ..<0.62:  place = places[index % 2]        // home, two nearby hubs
            case ..<0.78:  place = places[2]                // the next town over
            case ..<0.88:  place = places[3]                // the city
            default:       place = places[4 + index % 3]    // travel
            }
            let daysAgo = index * 3 + Int(random() * 3)
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }

            let isRace = index % 17 == 0
            let miles = isRace ? [13.1, 26.2, 6.2].randomElement()! : 3 + random() * 7
            let distance = miles * 1609.344
            let paceSecondsPerMile = 480 + random() * 180
            let movingTime = Int(miles * paceSecondsPerMile)

            // Runs start from a different place each time — a trailhead, a hotel, the far side of
            // town — spread a few kilometres around the hub. Every run sharing one exact start
            // pin collapsed Constellation to a handful of dots, which said more about the seed
            // than about the composition.
            let originLat = place.lat + (random() - 0.5) * 0.06
            let originLon = place.lon + (random() - 0.5) * 0.06

            // Routes come in shapes — a loop home, an out-and-back, a point-to-point, a figure
            // eight. One formula for all 220 made the Grid a page of near-identical glyphs and
            // turned Bloom into a symmetric rosette: the compositions looked settled because the
            // data was uniform, not because they worked.
            var coordinates: [CLLocationCoordinate2D] = []
            let radius = 0.004 + miles * 0.0004
            let loops = 1.0 + random()
            let routePhase = random() * 6.28
            let drift = 0.6 + random() * 0.8
            for step in 0...120 {
                let u = Double(step) / 120
                var dx: Double, dy: Double
                switch (index / 3) % 4 {
                case 0:   // a loop back to the door
                    let t = u * loops * 2 * .pi
                    let wobble = 1 + 0.28 * sin(t * 3 + routePhase)
                    dx = cos(t) * wobble * 1.2
                    dy = sin(t) * wobble
                case 1:   // out and back along the same line
                    let v = u < 0.5 ? u * 2 : (1 - u) * 2
                    dx = v * 1.8 * drift
                    dy = sin(v * .pi * 2.2 + routePhase) * 0.5
                case 2:   // point to point, never returning
                    dx = (u - 0.5) * 2.4 * drift
                    dy = sin(u * .pi * 1.6 + routePhase) * 0.7 + u * 0.6
                default:  // a figure eight
                    let t = u * 2 * .pi
                    dx = sin(t) * 1.3
                    dy = sin(t * 2 + routePhase) * 0.7
                }
                coordinates.append(CLLocationCoordinate2D(
                    latitude: originLat + dy * radius,
                    longitude: originLon + dx * radius
                ))
            }

            // Elevation profiles in four believable shapes — a summit, rolling hills, a net
            // descent, and a near-flat loop. One shared curve made every Ridgeline ridge
            // identical, which flattered the composition and told us nothing.
            let base = 300 + random() * 900
            let relief = 30 + random() * 340
            let phase = random() * 6.28
            let shape = index % 4
            let elevations = (0...120).map { step -> Double in
                let t = Double(step) / 120
                switch shape {
                case 0:   // out-and-back over a summit
                    return base + relief * sin(t * .pi)
                case 1:   // rolling
                    return base + relief * 0.55 * (0.6 + 0.4 * sin(t * .pi * 6 + phase))
                case 2:   // point to point, net downhill
                    return base + relief * (1 - t) + relief * 0.12 * sin(t * .pi * 9 + phase)
                default:  // flat with one bump
                    return base + relief * 0.22 * sin(t * .pi * 2 + phase)
                }
            }

            let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
            let run = Run(
                provider: .healthKit,
                name: isRace ? "\(place.city) \(miles == 26.2 ? "Marathon" : miles == 13.1 ? "Half" : "10K")"
                             : ["Morning Run", "Night Run", "Long Run", "Easy Miles"][index % 4],
                startDate: date,
                distance: distance,
                movingTime: movingTime,
                elapsedTime: movingTime + Int(random() * 120),
                elevationGain: RouteMetrics.elevationGain(of: elevations),
                summaryPolyline: PolylineDecoder.encode(coordinates),
                city: place.city,
                state: place.state,
                country: "United States",
                sportType: "Run",
                isRace: isRace,
                startLatitude: coordinates.first?.latitude,
                startLongitude: coordinates.first?.longitude,
                minLatitude: lats.min() ?? 0, maxLatitude: lats.max() ?? 0,
                minLongitude: lons.min() ?? 0, maxLongitude: lons.max() ?? 0
            )
            run.elevationSeries = elevations
            if isRace { run.finishPlace = "\(Int(random() * 400) + 12)" }
            context.insert(run)
        }
        try? context.save()
    }

    /// The most recent seeded run — the subject for the Studio previews.
    @MainActor
    static func subject(in context: ModelContext) -> Run? {
        var descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// Presents the screen named by `ETCH_PREVIEW`, skipping onboarding, the splash, and the sync
/// that a simulator has no data for.
struct PreviewHarnessView: View {
    @Environment(\.modelContext) private var context
    @State private var subject: Run?
    @State private var ready = false

    private var screen: String { PreviewHarness.screen ?? "studio" }

    var body: some View {
        Group {
            if !ready {
                Color(.systemBackground)
            } else {
                switch screen {
                case "home":            HomeView()
                // The whole shell rather than one surface — the only way CI can photograph the
                // tab bar, since every other case renders a view directly and never sees it.
                // "tabs@studio" opens the shell on that tab.
                case let name where name.hasPrefix("tabs"): EtchTabView()
                case "archive":         CollectionBrowserView(collection: .archive, runs: allRuns)
                case "course":          CollectionBrowserView(collection: .course, runs: allRuns)
                case "summit":          CollectionBrowserView(collection: .summit, runs: allRuns)
                case "yearbook":        BookStudioView(kind: .year)
                case "collections":     BookStudioView(kind: .collection)
                case "prints":          PrintShopView(subjectTitle: subject?.name)
                // Not a screen of the app: the print engine's self-check, reported on screen
                // because CI photographs screens and this project has no test target.
                case "print-engine":    PrintEngineCheckView()
                // Also not a screen of the app: the brand sheet's UI elements on one page, so
                // CI can photograph them and they can be held against the reference.
                case "components":      ComponentSheetView()
                // "wall-art:ridgeline" opens that style full size — the Archive's thumbnails
                // are too small to judge a composition by.
                case let name where name.hasPrefix("wall-art"):
                    MapPrintView(runs: allRuns, kind: .artMap, artStyle: artStyle(from: name))
                // "city-index:world" (or :country / :state) opens the tour-poster form with the
                // dot-map hero on that ground — the hero is normally chosen by hand, and CI
                // has none. Bare "city-index" is the type-only form.
                case let name where name.hasPrefix("city-index"):
                    let scope = name.split(separator: ":", maxSplits: 1).count == 2
                        ? MapPrintRequest.CityIndexMapScope(
                            rawValue: String(name.split(separator: ":", maxSplits: 1)[1]))
                        : nil
                    MapPrintView(runs: allRuns, kind: .cities, cityIndex: true,
                                 indexHero: scope == nil ? .none : .map,
                                 indexMapScope: scope ?? .world)
                case "map-studio":      studio(family: .map)
                case "gallery-studio":  studio(family: .gallery)
                case "detail":          detail
                default:                StudioHomeView(isHome: true)
                }
            }
        }
        .task {
            PreviewHarness.seed(into: context)
            subject = PreviewHarness.subject(in: context)
            ready = true
        }
    }

    private var allRuns: [Run] {
        (try? context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\Run.startDate, order: .reverse)]))) ?? []
    }

    @ViewBuilder private func studio(family: PosterFamily) -> some View {
        if let subject {
            StudioView(run: subject, preset: preset(family, for: subject))
        } else {
            Color(.systemBackground)
        }
    }

    /// The style named after the colon in `wall-art:<style>`, defaulting to Grid.
    private func artStyle(from name: String) -> MapArtStyle {
        let parts = name.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return .grid }
        return MapArtStyle(rawValue: String(parts[1])) ?? .grid
    }

    /// Opens the editor straight on the requested product, past the Map/Gallery chooser.
    private func preset(_ family: PosterFamily, for run: Run) -> PosterConfig {
        var config = PosterConfig.makeDefault(for: run)
        config.family = family
        return config
    }

    @ViewBuilder private var detail: some View {
        if let subject {
            NavigationStack { RunDetailView(run: subject) }
        } else {
            Color(.systemBackground)
        }
    }
}
