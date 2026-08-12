import SwiftUI
import SwiftData
import CoreLocation

/// Full-screen map with floating glass controls. The map is the product; chrome floats.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SyncService.self) private var sync
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]

    @AppStorage("mapStyle") private var mapStyleRaw = MapStyleOption.standard.rawValue
    private var mapStyle: MapStyleOption { MapStyleOption(rawValue: mapStyleRaw) ?? .standard }

    /// When true, the map shows the states-visited choropleth instead of routes.
    @State private var showStates = false
    /// When true, the map shows the accumulative "etch" view of all tracked history.
    @State private var showHistory = false
    /// When true, the map shows clustered run counts by city.
    @State private var showCities = false
    @State private var stateIntensities: [String: Double] = [:]

    /// TEMP diagnostic: counts bottom-button taps regardless of whether a sheet opens, so we
    /// can tell "the touch isn't landing" from "the touch lands but the page won't present".

    private var stats: RunStatistics { RunStatistics(allRuns) }

    /// Runs passing the active filter.
    private var visibleRuns: [Run] {
        let prs = appModel.filter.mode == .prs ? stats.prRunIDs : []
        return allRuns.filter { appModel.filter.matches($0, isPR: prs.contains($0.id)) }
    }

    private var visibleStats: RunStatistics { RunStatistics(visibleRuns) }

    /// Totals for whatever the map is currently showing. The overview modes (history, cities,
    /// states) ignore the active filter, so their pills reflect the full body of work.
    private var shownStats: RunStatistics {
        (showHistory || showCities || showStates) ? stats : visibleStats
    }

    var body: some View {
        @Bindable var appModel = appModel

        Group {
            if showStates {
                StatesMapView(intensities: stateIntensities, mapStyle: mapStyle)
            } else if showCities {
                CitiesMapView(coordinates: runStartCoordinates, mapStyle: mapStyle)
            } else {
                RunMapView(
                    // History shows the whole body of work, so it ignores the active filter.
                    runs: showHistory ? allRuns : visibleRuns,
                    selectedRunID: $appModel.selectedRunID,
                    command: $appModel.command,
                    mapStyle: mapStyle,
                    renderStyle: showHistory ? .history : .routes
                )
            }
        }
        .ignoresSafeArea()
        // Recompute whenever States is showing and the number of located runs changes, so the
        // choropleth fills in as Strava/HealthKit routes give older runs coordinates (rather
        // than caching one sparse result forever).
        .task(id: showStates ? locatedRunCount : -1) {
            guard showStates else { return }
            await computeStateIntensities()
        }
        // Controls float via safe-area insets rather than a ZStack overlay, so SwiftUI owns
        // their hit-testing and they don't compete with the map's UIKit gestures (which made
        // the buttons need several taps).
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        mapStyleButton
                        // Recenter-on-user only makes sense on the route/history maps, not the
                        // country-wide states or cities overviews.
                        if !showStates && !showCities {
                            GlassIconButton(systemName: "location.fill") {
                                appModel.recenterOnUser()
                            }
                        }
                    }
                }
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .overlay {
            if allRuns.isEmpty {
                emptyOrSyncing
            }
        }
        // A single sheet for both surfaces and the run detail. Two `.sheet` modifiers — even
        // on different views — can leave one flaky; one sheet driven by one binding is
        // reliable, so the bottom buttons always present on the first tap.
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .surface(let surface):
                surfaceView(for: surface)
            case .run(let id):
                if let run = allRuns.first(where: { $0.id == id }) {
                    RunDetailView(run: run)
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.regularMaterial)
                }
            }
        }
    }

    /// The one thing presented over the map: a surface (bottom buttons) or a selected run.
    private enum ActiveSheet: Identifiable {
        case surface(AppModel.Surface)
        case run(UUID)
        var id: String {
            switch self {
            case .surface(let surface): return "surface-\(surface.rawValue)"
            case .run(let id): return "run-\(id.uuidString)"
            }
        }
    }

    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if let surface = appModel.presentedSurface { return .surface(surface) }
                if let id = appModel.selectedRunID { return .run(id) }
                return nil
            },
            set: { newValue in
                switch newValue {
                case .surface(let surface):
                    appModel.presentedSurface = surface
                case .run(let id):
                    appModel.selectedRunID = id
                case nil:
                    appModel.presentedSurface = nil
                    appModel.selectedRunID = nil
                }
            }
        )
    }

    // MARK: Top — totals + mode toggles

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GlassPill(
                    title: UnitSystem.current.distanceSuffix,
                    value: Format.distanceValue(shownStats.totalDistanceMeters)
                        .formatted(.number.precision(.fractionLength(0))),
                    systemName: "point.topleft.down.to.point.bottomright.curvepath"
                )
                GlassPill(
                    title: "runs",
                    value: shownStats.totalRuns.formatted(),
                    systemName: "figure.run"
                )
                Spacer()
                if sync.isSyncing {
                    GlassContainer(padding: 10, cornerRadius: 18) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Syncing").font(.caption.weight(.medium))
                        }
                    }
                }
            }

            modeSelector
        }
    }

    /// What the map is currently showing: a run-filter mode, the history etch, the cities
    /// cluster map, or the states choropleth.
    private enum ModeSelection: Hashable {
        case mode(RunFilter.Mode)
        case history
        case cities
        case states
    }

    private var modeSelection: Binding<ModeSelection> {
        Binding(
            get: {
                if showStates { return .states }
                if showCities { return .cities }
                if showHistory { return .history }
                return .mode(appModel.filter.mode)
            },
            set: { newValue in
                showStates = false
                showHistory = false
                showCities = false
                switch newValue {
                case .mode(let mode):
                    var f = appModel.filter
                    f.mode = mode
                    appModel.setFilter(f)
                case .history:
                    showHistory = true
                case .cities:
                    showCities = true
                case .states:
                    showStates = true
                }
            }
        )
    }

    private var currentModeLabel: String {
        if showStates { return "States" }
        if showCities { return "Cities" }
        if showHistory { return "History" }
        return appModel.filter.mode.rawValue
    }
    private var currentModeSymbol: String {
        if showStates { return "map.fill" }
        if showCities { return "building.2.fill" }
        if showHistory { return "point.3.filled.connected.trianglepath.dotted" }
        return appModel.filter.mode.symbol
    }

    /// A rounded glass dropdown for the map mode (replaces the old chip row), with States
    /// added as a way to see the visited-states map right on the home screen.
    private var modeSelector: some View {
        HStack {
            Menu {
                Picker("Map", selection: modeSelection) {
                    ForEach(RunFilter.Mode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbol).tag(ModeSelection.mode(mode))
                    }
                    Label("History", systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .tag(ModeSelection.history)
                    Label("Cities", systemImage: "building.2.fill").tag(ModeSelection.cities)
                    Label("States", systemImage: "map.fill").tag(ModeSelection.states)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentModeSymbol).font(.caption)
                    Text(currentModeLabel)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassBackground(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    /// Number of runs that have a start coordinate — the input to both overview maps. Drives
    /// recomputation so the maps fill in as routes arrive.
    private var locatedRunCount: Int {
        allRuns.reduce(0) { $0 + ($1.startLatitude != nil ? 1 : 0) }
    }

    /// Every run's start point that has GPS, for the Cities cluster map.
    private var runStartCoordinates: [CLLocationCoordinate2D] {
        allRuns.compactMap(\.startCoordinate)
    }

    /// Attributes each located run to a US state by point-in-polygon and shades proportionally
    /// to run count. The coordinate snapshot happens on the main actor (Run isn't Sendable);
    /// the polygon tests run off-main so a large history never stalls the UI.
    private func computeStateIntensities() async {
        let coordinates = runStartCoordinates
        let boundaries = USStateBoundaries.shared
        let counts = await Task.detached(priority: .userInitiated) { () -> [String: Int] in
            var counts: [String: Int] = [:]
            for coordinate in coordinates {
                if let name = boundaries.region(containing: coordinate) {
                    counts[name, default: 0] += 1
                }
            }
            return counts
        }.value
        let maxCount = counts.values.max() ?? 1
        stateIntensities = counts.mapValues { min(1, (Double($0) / Double(maxCount)).squareRoot()) }
    }

    // MARK: Bottom — navigation controls

    private var bottomBar: some View {
        HStack(spacing: 10) {
            controlButton(icon: "magnifyingglass", surface: .search)
            controlButton(icon: "line.3.horizontal.decrease", surface: .filters, active: appModel.filter.isActive)
            controlButton(icon: "calendar", surface: .timeline)
            controlButton(icon: "sparkles", surface: .explore)
            controlButton(icon: "mappin.and.ellipse", surface: .travel)
            Spacer()
            controlButton(icon: "gearshape", surface: .settings)
        }
    }

    private func controlButton(icon: String, surface: AppModel.Surface, active: Bool = false) -> some View {
        GlassIconButton(systemName: icon, isActive: active) {
            appModel.presentedSurface = surface
        }
    }

    /// Switches the base map between standard, satellite, and hybrid.
    private var mapStyleButton: some View {
        Menu {
            Picker("Map Style", selection: $mapStyleRaw) {
                ForEach(MapStyleOption.allCases) { style in
                    Label(style.label, systemImage: style.symbol).tag(style.rawValue)
                }
            }
        } label: {
            Image(systemName: mapStyle.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .glassBackground(cornerRadius: 23)
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty / syncing state

    private var emptyOrSyncing: some View {
        VStack(spacing: 12) {
            if sync.isSyncing {
                ProgressView()
                Text(syncingLabel)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No runs yet")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Button("Sync Now") {
                    Task { await sync.sync() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            if !sync.lastDiagnostic.isEmpty {
                Text(sync.lastDiagnostic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            Text(AppInfo.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(28)
        .glassBackground(cornerRadius: Theme.cardRadius)
    }

    private var syncingLabel: String {
        if case .syncing(let imported) = sync.status, imported > 0 {
            return "Importing runs… \(imported)"
        }
        return "Importing your runs…"
    }

    // MARK: Sheet plumbing

    @ViewBuilder
    private func surfaceView(for surface: AppModel.Surface) -> some View {
        switch surface {
        case .filters: FilterView()
        case .timeline: TimelineView()
        case .explore: ExploreView()
        case .travel: TravelMapView()
        case .yearInReview: YearInReviewView(year: stats.years.first ?? Calendar.current.component(.year, from: Date()))
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
}
