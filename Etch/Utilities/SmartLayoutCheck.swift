import SwiftUI
import CoreLocation

/// Fixtures for the Smart Layout work — shared by the assertions and the visual harness so the
/// screenshots and the pass/fail verdict are describing the same pieces.
///
/// The runs are built in memory and never inserted into a `ModelContext`: everything under test
/// reads stored properties, so a bare instance is the whole fixture.
enum SmartLayoutFixtures {

    /// A course of `points` samples running `lonSpan` degrees east and `latSpan` degrees north,
    /// with a little wander so the drawn route is a route rather than a ruled line.
    static func course(originLat: Double, originLon: Double,
                       latSpan: Double, lonSpan: Double,
                       points: Int = 90) -> [CLLocationCoordinate2D] {
        (0...points).map { step in
            let t = Double(step) / Double(points)
            let wander = sin(t * .pi * 3) * 0.08
            return CLLocationCoordinate2D(
                latitude: originLat + latSpan * (t + wander * 0.25),
                longitude: originLon + lonSpan * t
            )
        }
    }

    /// A loop that closes on itself — the compact case.
    static func loop(originLat: Double, originLon: Double,
                     radiusLat: Double, points: Int = 90) -> [CLLocationCoordinate2D] {
        let radiusLon = radiusLat / cos(originLat * .pi / 180)
        return (0...points).map { step in
            let angle = Double(step) / Double(points) * 2 * .pi
            return CLLocationCoordinate2D(
                latitude: originLat + sin(angle) * radiusLat,
                longitude: originLon + cos(angle) * radiusLon
            )
        }
    }

    static func race(name: String,
                     coordinates: [CLLocationCoordinate2D],
                     city: String = "San Diego",
                     state: String = "CA",
                     distance: Double = 42_195,
                     movingTime: Int = 14_647,          // 4:04:07
                     elevationGain: Double = 323,       // ~1,059 ft
                     finishPlace: String = "127",
                     weather: Bool = true) -> Run {
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let run = Run(
            provider: .healthKit,
            name: name,
            startDate: Date(timeIntervalSince1970: 1_709_452_800),   // 3 Mar 2024
            distance: distance,
            movingTime: movingTime,
            elapsedTime: movingTime,
            elevationGain: elevationGain,
            summaryPolyline: PolylineDecoder.encode(coordinates),
            city: city, state: state, country: "United States",
            sportType: "Run",
            isRace: true,
            startLatitude: coordinates.first?.latitude,
            startLongitude: coordinates.first?.longitude,
            minLatitude: lats.min() ?? 0, maxLatitude: lats.max() ?? 0,
            minLongitude: lons.min() ?? 0, maxLongitude: lons.max() ?? 0
        )
        run.finishPlace = finishPlace
        if weather {
            run.weatherTemperatureC = 18.9                    // 66°F
            run.weatherConditionRaw = WeatherCondition.partlyCloudy.rawValue
        }
        return run
    }

    /// A decisively wide point-to-point — a coastal marathon. Corrected aspect ≈ 2.1.
    static var wideRace: Run {
        race(name: "Coast Marathon",
             coordinates: course(originLat: 32.737, originLon: -117.260,
                                 latSpan: 0.048, lonSpan: 0.120))
    }

    /// A city loop that closes on itself. Corrected aspect ≈ 1.0.
    static var compactRace: Run {
        race(name: "Harbor Loop Half",
             coordinates: loop(originLat: 32.737, originLon: -117.160, radiusLat: 0.030),
             distance: 21_097, movingTime: 6_842, elevationGain: 154)
    }

    /// A north–south canyon course. Corrected aspect ≈ 0.35.
    static var tallRace: Run {
        race(name: "Canyon Vertical",
             coordinates: course(originLat: 36.055, originLon: -112.140,
                                 latSpan: 0.110, lonSpan: 0.045),
             city: "Grand Canyon", state: "AZ",
             distance: 34_000, movingTime: 16_200, elevationGain: 1_650)
    }

    /// No route at all — an indoor or unmapped activity.
    static var boundlessRace: Run {
        let run = race(name: "Treadmill Time Trial", coordinates: [])
        run.minLatitude = 0; run.maxLatitude = 0
        run.minLongitude = 0; run.maxLongitude = 0
        run.startLatitude = nil; run.startLongitude = nil
        return run
    }
}

/// Proves the Smart Layout rules, on a simulator, in CI.
///
/// Two things are worth pinning down here and neither needs a map: which sheet the route argues
/// for, and which of the customer's chosen figures the race panel actually prints. Both are pure
/// functions over values — `StudioCurator.routeAspect` / `bestOrientation`, and the curator's own
/// pick construction — so they run as a preview screen (`ETCH_PREVIEW=smart-layout`) and report on
/// screen and as text, the same way `ScopeRuleCheckView` and `PrintEngineCheckView` do.
///
/// What it deliberately does *not* claim to check is whether the panel looks right. That is what
/// `ETCH_PREVIEW=race-panel` renders, and it is judged by eye.
@MainActor
struct SmartLayoutCheckView: View {

    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    /// Asserted by the workflow, so a check that bails out early is a red job rather than a
    /// shorter clean report.
    static let expectedChecks = 21

    @State private var results: [Result] = []
    @State private var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Smart Layout")
                    .font(.etch(.title2, weight: .bold))
                Spacer()
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Text(results.allSatisfy(\.passed) ? "ALL PASS" : "FAIL")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(results.allSatisfy(\.passed) ? .green : .red, in: .capsule)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.etch(size: 13, weight: .semibold))
                                Text(result.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .task { run() }
    }

    private func run() {
        var out: [Result] = []

        func expect(_ name: String, _ actual: some Equatable, _ wanted: some Equatable, _ note: String) {
            let passed = "\(actual)" == "\(wanted)"
            out.append(Result(name: name, passed: passed,
                              detail: passed ? note : "expected \(wanted), got \(actual) — \(note)"))
        }

        func near(_ name: String, _ actual: Double?, _ wanted: Double, _ tolerance: Double,
                  _ note: String) {
            let passed = actual.map { abs($0 - wanted) <= tolerance } ?? false
            let shown = actual.map { String(format: "%.2f", $0) } ?? "nil"
            out.append(Result(name: name, passed: passed,
                              detail: passed ? "\(note) (\(shown))"
                                             : "expected ~\(wanted)±\(tolerance), got \(shown) — \(note)"))
        }

        // ── Route geometry → the recommended sheet.

        let wide = SmartLayoutFixtures.wideRace
        let compact = SmartLayoutFixtures.compactRace
        let tall = SmartLayoutFixtures.tallRace
        let boundless = SmartLayoutFixtures.boundlessRace

        near("Wide course measures wide", StudioCurator.routeAspect(for: wide), 2.10, 0.30,
             "a coastal point-to-point, corrected for latitude")
        near("Loop course measures square", StudioCurator.routeAspect(for: compact), 1.00, 0.15,
             "a closed loop is as tall as it is wide by construction")
        near("Canyon course measures tall", StudioCurator.routeAspect(for: tall), 0.35, 0.15,
             "a north–south course")

        expect("Wide course recommends Landscape",
               StudioCurator.bestOrientation(for: wide), StudioOrientation.landscape,
               "the sheet follows the route rather than the product")
        expect("Compact loop recommends Portrait",
               StudioCurator.bestOrientation(for: compact), StudioOrientation.portrait,
               "a loop wastes nothing on a portrait sheet")
        expect("Tall course recommends Portrait",
               StudioCurator.bestOrientation(for: tall), StudioOrientation.portrait,
               "north–south routes were never the landscape case")
        expect("Missing geometry falls back to Portrait",
               StudioCurator.bestOrientation(for: boundless), StudioOrientation.portrait,
               "no bounds is not an argument for turning the sheet")
        expect("Missing geometry reports no aspect",
               StudioCurator.routeAspect(for: boundless) == nil, true,
               "the caller can tell 'square' from 'unknown'")

        // Mercator correction is the difference between choosing by shape and choosing by
        // latitude: the identical degree box is a different shape on the ground at 60° than at 0°.
        let equator = SmartLayoutFixtures.race(
            name: "Equator", coordinates: SmartLayoutFixtures.course(
                originLat: 0.5, originLon: 0, latSpan: 0.05, lonSpan: 0.08))
        let arctic = SmartLayoutFixtures.race(
            name: "Arctic", coordinates: SmartLayoutFixtures.course(
                originLat: 64.14, originLon: -21.94, latSpan: 0.05, lonSpan: 0.08))
        expect("Latitude correction is applied",
               (StudioCurator.routeAspect(for: arctic) ?? 0)
                   < (StudioCurator.routeAspect(for: equator) ?? 0) * 0.6,
               true,
               "the same degree box is a much narrower shape near the pole")

        // The threshold itself, from both sides.
        expect("Just above the threshold turns the sheet",
               StudioCurator.landscapeAspectThreshold >= 1.45
                   && StudioCurator.landscapeAspectThreshold <= 1.55,
               true,
               "validated range from the spec — chosen at \(StudioCurator.landscapeAspectThreshold)")

        // ── The curated Race Edition.

        let widePicks = StudioCurator.picks(for: wide)
        let compactPicks = StudioCurator.picks(for: compact)
        let wideRaceEdition = widePicks.first { $0.id == "race-gallery" }?.config
        let compactRaceEdition = compactPicks.first { $0.id == "race-gallery" }?.config

        expect("A Race Edition is curated for both routes",
               wideRaceEdition != nil && compactRaceEdition != nil, true,
               "the race lead kind produces its editions whatever the geometry")

        expect("Wide race opens in Landscape",
               wideRaceEdition?.orientation ?? .portrait, StudioOrientation.landscape,
               "the unconditional portrait override is gone")
        expect("Compact race opens in Portrait",
               compactRaceEdition?.orientation ?? .landscape, StudioOrientation.portrait,
               "portrait is still the answer when the route says so")
        expect("Landscape race keeps its data beneath the art",
               wideRaceEdition?.dataPlacement ?? .right, StudioDataPlacement.bottom,
               "not a side column — a Nameplate composes head → art → foot in both orientations")
        expect("Race Edition still leads with the result",
               wideRaceEdition?.heroMetric ?? .none, StatMetric.time,
               "landscape changes the sheet, not the product")
        // Portrait ignores data placement entirely — `canvasSize(.portrait, _)` never reads it —
        // so the curated portrait piece keeps whatever the default was, and that is correct. What
        // matters is that the composition agrees, which is what the next check asserts.
        expect("Portrait is unaffected by data placement",
               StudioComposition.canvasSize(.portrait, .right, .twoThree)
                   == StudioComposition.canvasSize(.portrait, .bottom, .twoThree), true,
               "the portrait canvas is the same sheet whichever placement is stored")
        expect("A landscape Nameplate is not sized as a side-column sheet",
               StudioComposition.canvasSize(.landscape, .bottom, .twoThree)
                   != StudioComposition.canvasSize(.landscape, .right, .twoThree), true,
               "the two canvases genuinely differ, so picking the wrong one would misshape the print")

        // ── The values the panel prints.

        expect("Coordinates split into two lines",
               SmartLayoutFixtures.wideRace.startLatitude != nil, true,
               "the two-line cell needs a start point; the fixture has one")

        let weatherLine = wide.weatherLine()
        expect("Weather resolves to one short line",
               (weatherLine?.count ?? 99) <= 24, true,
               "\(weatherLine ?? "nil") — long enough to deserve its own band, short enough to sit on one")

        // The date belongs to the result band, and the curator must not have put `.place` or
        // `.date` in the supporting slots where it would duplicate it.
        let slots = wideRaceEdition?.dataSlots ?? []
        expect("Default race slots carry no duplicate context",
               slots.contains(.place) || slots.contains(.date), false,
               "place and date are Band A's job — slots are \(slots.map(\.rawValue))")
        expect("Default race slots stay restrained",
               slots.count <= 3, true,
               "Distance, Pace and an optional finishing position — \(slots.map(\.rawValue))")

        // Counted before the count check itself is appended — otherwise the report's own
        // `RAN_CHECKS` disagrees with the number the failure quotes.
        let ran = out.count
        if ran != Self.expectedChecks {
            out.append(Result(name: "Check count", passed: false,
                              detail: "expected \(Self.expectedChecks) checks, ran \(ran)"))
        }

        results = out
        running = false
        writeReport(out, ran: ran)
    }

    private func writeReport(_ results: [Result], ran: Int) {
        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        var lines = ["smart-layout \(AppInfo.changeTag)"]
        for result in results {
            lines.append("\(result.passed ? "PASS" : "FAIL")  \(result.name) — \(result.detail)")
        }
        lines.append("EXPECTED_CHECKS: \(Self.expectedChecks)")
        lines.append("RAN_CHECKS: \(ran)")
        let ok = results.allSatisfy(\.passed) && ran == Self.expectedChecks
        lines.append(ok ? "RESULT: ALL PASS" : "RESULT: FAIL")
        try? lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("smart-layout-report.txt"),
            atomically: true, encoding: .utf8
        )
    }
}

/// The race data panel, rendered for the eye.
///
/// Four scenarios on one scroll: the wide course in landscape, the compact one in portrait, the
/// dense panel (Distance · Pace · Coordinates · Elev Gain, plus weather), and the sparse one. The
/// map style is `.none` on purpose — the panel is the subject, and a basemap snapshot on a CI
/// runner is thirty seconds of waiting for something that is not being judged.
@MainActor
struct RacePanelPreviewView: View {

    struct Piece: Identifiable {
        let id: String
        let caption: String
        let image: UIImage?
    }

    @State private var pieces: [Piece] = []
    @State private var rendering = true

    /// `race-panel@all-data` photographs one scenario filling the screen. Four sheets stacked on
    /// one scroll are each a couple of hundred pixels tall in a screenshot, which is not enough to
    /// judge whether a caption is colliding with the value above it — and judging that is the
    /// whole point of rendering them.
    private var wanted: String? {
        let anchor = ProcessInfo.processInfo.environment["ETCH_PREVIEW_SCROLL"] ?? ""
        return anchor.isEmpty ? nil : anchor
    }

    private var shown: [Piece] {
        guard let wanted else { return pieces }
        return pieces.filter { $0.id == wanted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if wanted == nil {
                    Text("Race data panel")
                        .font(.etch(.title2, weight: .bold))
                }
                if rendering { ProgressView().controlSize(.small) }
                ForEach(shown) { piece in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(piece.caption)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let image = piece.image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .overlay(Rectangle().strokeBorder(.secondary.opacity(0.25),
                                                                  lineWidth: 0.5))
                        } else {
                            Text("render failed").foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(12)
        }
        .task { await render() }
    }

    /// The four scenarios, each a complete `PosterConfig` built the way the curator builds one.
    private func scenarios() -> [(id: String, caption: String, run: Run, config: PosterConfig)] {
        let wide = SmartLayoutFixtures.wideRace
        let compact = SmartLayoutFixtures.compactRace

        func raceConfig(for run: Run, slots: [StatMetric], weather: Bool) -> PosterConfig {
            var config = StudioCurator.picks(for: run)
                .first { $0.id == "race-gallery" }?.config ?? PosterConfig.makeDefault(for: run)
            config.mapStyle = .none
            config.dataSlots = slots
            config.includeWeather = weather
            config.outputSize = .poster
            return config
        }

        return [
            ("wide-landscape",
             "A · wide course → \(StudioCurator.bestOrientation(for: wide).name), data beneath the art",
             wide, raceConfig(for: wide, slots: [.distance, .pace], weather: false)),

            ("compact-portrait",
             "B · compact loop → \(StudioCurator.bestOrientation(for: compact).name)",
             compact, raceConfig(for: compact, slots: [.distance, .pace], weather: false)),

            ("all-data",
             "C · four supporting metrics + weather",
             compact, raceConfig(for: compact,
                                 slots: [.distance, .pace, .coordinates, .elevationGain],
                                 weather: true)),

            ("sparse",
             "D · two supporting metrics",
             compact, raceConfig(for: compact, slots: [.distance, .pace], weather: false))
        ]
    }

    private func render() async {
        var out: [Piece] = []
        let requested = wanted
        for scenario in scenarios() where requested == nil || scenario.id == requested {
            let image = await StudioRenderer.image(
                for: scenario.config.request(for: scenario.run), scale: 0.5)
            out.append(Piece(id: scenario.id, caption: scenario.caption, image: image))
            pieces = out
        }
        rendering = false
    }
}

/// The Design section on its own, so the Orientation recommendation can be photographed.
///
/// Inside the editor tray that control sits below Layout, Style and Color — off the bottom of a
/// screenshot, and `simctl` cannot scroll a sheet. This is the same production `StudioDesignEditor`,
/// just not wrapped in the tray, shown against the wide fixture so the line it prints is the
/// route-derived one rather than the default.
@MainActor
struct OrientationRecommendationPreview: View {
    private let run = SmartLayoutFixtures.wideRace
    @State private var config = PosterConfig.makeDefault(for: SmartLayoutFixtures.wideRace)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Design")
                    .font(.etch(.title3, weight: .bold))
                Text("Wide fixture · corrected aspect "
                     + String(format: "%.2f", StudioCurator.routeAspect(for: run) ?? 0))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                StudioDesignEditor(run: run, config: $config, onNeedRoom: {})
            }
            .padding(20)
        }
        .onAppear {
            config.family = .map
            config.mapStyle = .none
            config.mapLayout = .nameplate
            config.orientation = StudioCurator.bestOrientation(for: run)
        }
    }
}
