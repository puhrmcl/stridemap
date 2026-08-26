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

        for index in 0..<80 {
            let place = places[index % places.count]
            let daysAgo = index * 9 + Int(random() * 4)
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }

            let isRace = index % 17 == 0
            let miles = isRace ? [13.1, 26.2, 6.2].randomElement()! : 3 + random() * 7
            let distance = miles * 1609.344
            let paceSecondsPerMile = 480 + random() * 180
            let movingTime = Int(miles * paceSecondsPerMile)

            // A looping route around the start: enough shape to read as a real run in a glyph.
            var coordinates: [CLLocationCoordinate2D] = []
            let loops = 1.0 + random()
            let radius = 0.004 + miles * 0.0004
            for step in 0...120 {
                let t = Double(step) / 120 * loops * 2 * .pi
                let wobble = 1 + 0.28 * sin(t * 3 + Double(index))
                coordinates.append(CLLocationCoordinate2D(
                    latitude: place.lat + sin(t) * radius * wobble,
                    longitude: place.lon + cos(t) * radius * wobble * 1.2
                ))
            }

            // An elevation profile with a believable climb and descent.
            let base = 300 + random() * 900
            let relief = 20 + random() * 260
            let elevations = (0...120).map { step -> Double in
                let t = Double(step) / 120
                return base + relief * (sin(t * .pi * 1.5) * 0.7 + sin(t * .pi * 5) * 0.3)
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
                case "archive":         CollectionBrowserView(collection: .archive, runs: allRuns)
                case "course":          CollectionBrowserView(collection: .course, runs: allRuns)
                case "summit":          CollectionBrowserView(collection: .summit, runs: allRuns)
                case "yearbook":        YearBookView()
                case "prints":          PrintShopView(subjectTitle: subject?.name)
                case "wall-art":        MapPrintView(runs: allRuns, kind: .artMap)
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
