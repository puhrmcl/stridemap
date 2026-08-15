import SwiftUI
import SwiftData
import CoreLocation
import MapKit

/// The specific overlay shown under the home map's "Locations" mode.
enum LocationOverlay: String, CaseIterable, Identifiable {
    case cities, states, countries, landmarks
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .cities: return "building.2.fill"
        case .states: return "map.fill"
        case .countries: return "globe.americas.fill"
        case .landmarks: return "mappin.and.ellipse"
        }
    }
}

/// Full-screen map with floating glass controls. The map is the product; chrome floats.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SyncService.self) private var sync
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]

    @AppStorage("mapStyle") private var mapStyleRaw = MapStyleOption.standard.rawValue
    private var mapStyle: MapStyleOption { MapStyleOption(rawValue: mapStyleRaw) ?? .standard }

    /// When true, the map shows a Locations overlay (cities / states / countries / landmarks).
    @State private var showLocations = false
    /// Which Locations overlay is active.
    @State private var locationOverlay: LocationOverlay = .cities
    @State private var stateIntensities: [String: Double] = [:]
    /// States ranked by run count, for the home-map "jump to state" menu.
    @State private var stateRanked: [(name: String, count: Int)] = []
    /// The single selected state (full boundary name). When set, the States map centres on it,
    /// unshades the rest, and pins its runs.
    @State private var selectedStateName: String?
    /// Start points of the runs inside the selected state — the pins drawn over it.
    @State private var selectedStateRunPoints: [RunMapPoint] = []
    @State private var countryIntensities: [String: Double] = [:]
    /// Countries ranked by run count, for the home-map "jump to country" menu.
    @State private var countryRanked: [(name: String, count: Int)] = []
    /// A jump-to target set by the places menu; the overview map zooms to it, then clears it.
    @State private var focusStateName: String?
    @State private var focusCountryName: String?
    @State private var focusCity: CLLocationCoordinate2D?
    /// The last place picked from the "View" menu, shown on its label until the overlay changes.
    @State private var selectedPlaceLabel: String?
    /// Bumped by the Locations recenter button; folded into the overlay map's id so the map is
    /// rebuilt and re-framed to fit all its pins/regions.
    @State private var locationRecenterToken = 0
    /// The bottom navigation buttons collapse behind a menu; tapping it expands them.
    @State private var menuExpanded = false

    /// The full-map print kind that matches the current view.
    private var currentPrintKind: MapPrintKind {
        guard showLocations else { return .allRuns }
        switch locationOverlay {
        case .cities: return .cities
        case .states: return .states
        case .landmarks: return .landmarks
        case .countries: return .allRuns
        }
    }

    /// TEMP diagnostic: counts bottom-button taps regardless of whether a sheet opens, so we
    /// can tell "the touch isn't landing" from "the touch lands but the page won't present".

    /// Runs limited to the active activity scope (All / Runs / Hikes / Walks) — the base for every
    /// map, total, and overview below.
    private var scopedRuns: [Run] { allRuns.scoped(to: appModel.activityScope) }

    private var stats: RunStatistics { RunStatistics(scopedRuns) }

    /// Runs passing the active filter.
    private var visibleRuns: [Run] {
        let prs = appModel.filter.mode == .prs ? stats.prRunIDs : []
        return scopedRuns.filter { appModel.filter.matches($0, isPR: prs.contains($0.id)) }
    }

    private var visibleStats: RunStatistics { RunStatistics(visibleRuns) }

    /// The overview modes ignore the active filter and show everything (within scope).
    private var isOverviewMode: Bool { showLocations }

    /// The runs the map is currently showing. Overview modes show everything; the route map
    /// shows the active filter's runs.
    private var shownRuns: [Run] {
        isOverviewMode ? scopedRuns : visibleRuns
    }

    /// Totals for whatever the map is currently showing.
    private var shownStats: RunStatistics { RunStatistics(shownRuns) }

    /// Zoom/recenter the route or history map to the extent of the runs on screen. The cities
    /// and states overviews use their own maps (no camera command) and already frame on entry.
    private func fitShownRuns() {
        guard !showLocations else { return }
        appModel.fit(shownRuns)
    }

    var body: some View {
        @Bindable var appModel = appModel

        Group {
            if showLocations {
                if locationOverlay == .states {
                    StatesMapView(
                        intensities: stateIntensities,
                        mapStyle: mapStyle,
                        focusStateName: $focusStateName,
                        selectedName: selectedStateName,
                        runPoints: selectedStateRunPoints,
                        selectedRunID: $appModel.selectedRunID,
                        stackedRunIDs: $appModel.stackedRunIDs
                    )
                    .id("states-\(locationRecenterToken)")
                } else if locationOverlay == .countries {
                    CountriesMapView(
                        intensities: countryIntensities,
                        mapStyle: mapStyle,
                        focusCountryName: $focusCountryName
                    )
                    .id("countries-\(locationRecenterToken)")
                } else {
                    CitiesMapView(
                        cities: overlayPlaces,
                        selectedRunID: $appModel.selectedRunID,
                        stackedRunIDs: $appModel.stackedRunIDs,
                        focusCoordinate: $focusCity,
                        mapStyle: mapStyle
                    )
                    // Rebuild the map when the overlay changes (CitiesMapView otherwise only
                    // re-pins on a pin-count change) or when the recenter button is tapped, so
                    // it re-frames all pins.
                    .id("\(locationOverlay.rawValue)-\(locationRecenterToken)")
                }
            } else {
                RunMapView(
                    runs: visibleRuns,
                    selectedRunID: $appModel.selectedRunID,
                    stackedRunIDs: $appModel.stackedRunIDs,
                    command: $appModel.command,
                    mapStyle: mapStyle
                )
            }
        }
        .ignoresSafeArea()
        // The "View" label reflects the chosen place; reset it (and any selected state) when the
        // overlay or mode changes.
        .onChange(of: locationOverlay) { selectedPlaceLabel = nil; selectedStateName = nil }
        .onChange(of: showLocations) { selectedPlaceLabel = nil; selectedStateName = nil }
        // Recompute the selected state's run pins whenever the selection or the located-run set
        // changes.
        .onChange(of: selectedStateName) { recomputeSelectedStateRunPoints() }
        .onChange(of: locatedRunCount) {
            if selectedStateName != nil { recomputeSelectedStateRunPoints() }
        }
        // Recompute whenever States is showing and the number of located runs changes, so the
        // choropleth fills in as Strava/HealthKit routes give older runs coordinates (rather
        // than caching one sparse result forever).
        .task(id: (showLocations && locationOverlay == .states) ? locatedRunCount : -1) {
            guard showLocations, locationOverlay == .states else { return }
            await computeStateIntensities()
        }
        // Same, for the Countries choropleth.
        .task(id: (showLocations && locationOverlay == .countries) ? locatedRunCount : -3) {
            guard showLocations, locationOverlay == .countries else { return }
            await computeCountryIntensities()
        }
        // Detect nearby landmarks while the Landmarks overlay is open. Keying on the number of
        // unchecked runs makes each completed pass re-fire the next one, filling in over time;
        // a failed pass leaves the count unchanged, so it naturally backs off.
        .task(id: (showLocations && locationOverlay == .landmarks) ? uncheckedLandmarkCount : -2) {
            guard showLocations, locationOverlay == .landmarks else { return }
            await sync.detectLandmarks(limit: 20)
        }
        // Applying a filter reframes the route map to the newly filtered runs.
        .onChange(of: appModel.filter) {
            if !isOverviewMode { appModel.fit(visibleRuns) }
        }
        // Switching activity type reframes the route map to the newly scoped set.
        .onChange(of: appModel.activityScope) {
            if !isOverviewMode { appModel.fit(visibleRuns) }
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
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    mapStyleButton
                    if showLocations {
                        // Re-frame the overlay to fit all its pins / regions (and drop any single
                        // state selection so the full choropleth returns).
                        GlassIconButton(systemName: "arrow.up.left.and.arrow.down.right") {
                            selectedStateName = nil
                            selectedPlaceLabel = nil
                            locationRecenterToken += 1
                        }
                    } else {
                        GlassIconButton(systemName: "location.fill") {
                            appModel.recenterOnUser()
                        }
                        // Recenter/zoom the map to frame all the runs currently shown.
                        GlassIconButton(systemName: "arrow.up.left.and.arrow.down.right") {
                            fitShownRuns()
                        }
                    }
                    bottomBar
                }
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
            case .stack(let ids):
                RunStackView(runs: allRuns.filter { ids.contains($0.id) })
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.regularMaterial)
            }
        }
    }

    /// The one thing presented over the map: a surface (bottom buttons), a selected run, or a
    /// pick-list of runs stacked at one location.
    private enum ActiveSheet: Identifiable {
        case surface(AppModel.Surface)
        case run(UUID)
        case stack([UUID])
        var id: String {
            switch self {
            case .surface(let surface): return "surface-\(surface.rawValue)"
            case .run(let id): return "run-\(id.uuidString)"
            case .stack(let ids): return "stack-\(ids.map(\.uuidString).joined())"
            }
        }
    }

    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if let surface = appModel.presentedSurface { return .surface(surface) }
                if let ids = appModel.stackedRunIDs, ids.count > 1 { return .stack(ids) }
                if let id = appModel.selectedRunID { return .run(id) }
                return nil
            },
            set: { newValue in
                switch newValue {
                case .surface(let surface):
                    appModel.presentedSurface = surface
                case .run(let id):
                    appModel.selectedRunID = id
                case .stack(let ids):
                    appModel.stackedRunIDs = ids
                case nil:
                    appModel.presentedSurface = nil
                    appModel.selectedRunID = nil
                    appModel.stackedRunIDs = nil
                }
            }
        )
    }

    // MARK: Top — totals + mode toggles

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                totalsPill
                Spacer()
            }
            // The sync spinner sits at the trailing edge as an overlay, so it never shifts the
            // centred pill.
            .overlay(alignment: .trailing) {
                if sync.isSyncing {
                    GlassContainer(padding: 10, cornerRadius: 18) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Syncing").font(.caption.weight(.medium))
                        }
                    }
                }
            }

            if showLocations { modeSelector }
        }
    }

    /// One glass pill showing both totals — distance and run count — with the map-mode dropdown
    /// folded in: a chevron on the right opens the mode menu (filter modes / History / Locations).
    private var totalsPill: some View {
        HStack(spacing: 10) {
            activitySelector
            Rectangle()
                .fill(.secondary.opacity(0.25))
                .frame(width: 1, height: 30)
            totalsMenu
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(cornerRadius: 18)
    }

    /// The activity-type selector on the left of the pill — All / Runs / Hikes (Walks when the
    /// user opts in). Changing it re-scopes the whole app.
    private var activitySelector: some View {
        Menu {
            Picker("Activity", selection: activityBinding) {
                ForEach(activityScopeOptions) { scope in
                    Label(scope.label, systemImage: scope.icon).tag(scope)
                }
            }
        } label: {
            Image(systemName: appModel.activityScope.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accentOnGlass)
                .frame(width: 24, height: 30)
        }
        .buttonStyle(.plain)
    }

    /// The distance + count totals, with the map-mode dropdown folded in on the right.
    private var totalsMenu: some View {
        Menu {
            Picker("Map", selection: modeSelection) {
                ForEach(RunFilter.Mode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(ModeSelection.mode(mode))
                }
                Label("Locations", systemImage: "mappin.and.ellipse").tag(ModeSelection.locations)
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    metric(
                        value: Format.distanceValue(shownStats.totalDistanceMeters)
                            .formatted(.number.precision(.fractionLength(0))),
                        unit: UnitSystem.current.distanceSuffix,
                        systemName: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    Rectangle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 1, height: 18)
                    metric(
                        value: shownStats.totalRuns.formatted(),
                        unit: appModel.activityScope.countNoun,
                        systemName: appModel.activityScope.icon
                    )
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(height: 1)
                Text(currentModeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accentOnGlass)
                    .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private var activityBinding: Binding<ActivityScope> {
        Binding(
            get: { appModel.activityScope },
            set: { newValue in withAnimation(Theme.gentle) { appModel.activityScope = newValue } }
        )
    }

    /// The scopes offered — Walks only when the user has opted in.
    private var activityScopeOptions: [ActivityScope] {
        ActivitySettings.includeWalks ? ActivityScope.allCases : ActivityScope.allCases.filter { $0 != .walks }
    }

    /// The pill's caption line. A specific map-mode filter (Races, PRs…) or Locations names itself;
    /// otherwise it reads "All Activity" / "All Runs" / "All Hikes" per the selected activity.
    private var currentModeLabel: String {
        if showLocations { return "Locations" }
        if appModel.filter.mode != .all { return appModel.filter.mode.rawValue }
        switch appModel.activityScope {
        case .all:   return "All Activity"
        case .runs:  return "All Runs"
        case .hikes: return "All Hikes"
        case .walks: return "All Walks"
        }
    }

    private func metric(value: String, unit: String, systemName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentOnGlass)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    /// What the map is currently showing: a run-filter mode, the history etch, or a Locations
    /// overlay (whose specific overlay is chosen by a secondary dropdown).
    private enum ModeSelection: Hashable {
        case mode(RunFilter.Mode)
        case locations
    }

    private var modeSelection: Binding<ModeSelection> {
        Binding(
            get: {
                if showLocations { return .locations }
                return .mode(appModel.filter.mode)
            },
            set: { newValue in
                showLocations = false
                switch newValue {
                case .mode(let mode):
                    var f = appModel.filter
                    f.mode = mode
                    appModel.setFilter(f)
                case .locations:
                    showLocations = true
                }
            }
        )
    }

    /// The pins for the active pin-based overlay (cities / landmarks). States and countries are
    /// choropleths, not pins.
    private var overlayPlaces: [RunStatistics.TravelPlace] {
        switch locationOverlay {
        case .cities: return stats.travelPlaces
        case .landmarks: return stats.landmarkPlaces
        case .states, .countries: return []
        }
    }

    /// The primary map-mode dropdown, plus — in Locations mode — a secondary dropdown to pick
    /// the specific overlay and a "jump to" menu to zoom to a place. Scrolls horizontally so
    /// every pill keeps its full label on one line rather than wrapping/hyphenating when the
    /// three don't all fit on a narrow screen.
    private var modeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                overlaySelector
                placesMenu
            }
            .padding(.vertical, 3)   // room for the pills' soft shadows
        }
        .scrollClipDisabled()
    }

    /// Secondary dropdown: which Locations overlay to show.
    private var overlaySelector: some View {
        Menu {
            Picker("Overlay", selection: $locationOverlay) {
                ForEach(LocationOverlay.allCases) { overlay in
                    Label(overlay.label, systemImage: overlay.symbol).tag(overlay)
                }
            }
        } label: {
            pill(symbol: locationOverlay.symbol, text: locationOverlay.label)
        }
        .buttonStyle(.plain)
    }

    /// A "jump to" menu that zooms the active overlay to a chosen place.
    @ViewBuilder
    private var placesMenu: some View {
        if locationOverlay == .states {
            if !stateRanked.isEmpty {
                placesMenuLabel(title: selectedPlaceLabel ?? "View") {
                    if selectedStateName != nil {
                        Button {
                            selectedStateName = nil
                            selectedPlaceLabel = nil
                            locationRecenterToken += 1   // reframe the full choropleth
                        } label: { Label("All States", systemImage: "map") }
                    }
                    ForEach(stateRanked, id: \.name) { item in
                        Button("\(item.name)  ·  \(item.count)") {
                            selectedStateName = item.name
                            focusStateName = item.name
                            selectedPlaceLabel = item.name
                        }
                    }
                }
            }
        } else if locationOverlay == .countries {
            if !countryRanked.isEmpty {
                placesMenuLabel(title: selectedPlaceLabel ?? "View") {
                    ForEach(countryRanked, id: \.name) { item in
                        Button("\(item.name)  ·  \(item.count)") {
                            focusCountryName = item.name
                            selectedPlaceLabel = item.name
                        }
                    }
                }
            }
        } else if !overlayPlaces.isEmpty {
            placesMenuLabel(title: selectedPlaceLabel ?? "View") {
                ForEach(overlayPlaces) { place in
                    Button("\(shortPlaceLabel(place))  ·  \(place.runs.count)") {
                        focusCity = place.coordinate
                        selectedPlaceLabel = shortPlaceLabel(place)
                    }
                }
            }
        }
    }

    /// A compact place label that stays on one menu line — for cities, drops the country so
    /// "Gilbert, AZ, United States" reads "Gilbert, AZ". Other overlays use the full label.
    private func shortPlaceLabel(_ place: RunStatistics.TravelPlace) -> String {
        guard locationOverlay == .cities else { return place.label }
        let parts = place.label.components(separatedBy: ", ")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ", ") : place.label
    }

    private func placesMenuLabel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            pill(symbol: "list.bullet", text: title)
        }
        .buttonStyle(.plain)
    }

    /// The shared glass dropdown pill used by all three menus. The label stays on one line at
    /// its full width — never wrapped or hyphenated.
    private func pill(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassBackground(cornerRadius: 22)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Number of runs that have a start coordinate — the input to both overview maps. Drives
    /// recomputation so the maps fill in as routes arrive.
    private var locatedRunCount: Int {
        scopedRuns.reduce(0) { $0 + ($1.startLatitude != nil ? 1 : 0) }
    }

    /// Located runs not yet checked for a nearby landmark — drives progressive detection.
    private var uncheckedLandmarkCount: Int {
        allRuns.reduce(0) { $0 + (($1.startLatitude != nil && !$1.landmarkChecked) ? 1 : 0) }
    }

    /// Every run's start point that has GPS, paired with its identity, for the Cities map.
    private var runStartPoints: [RunMapPoint] {
        scopedRuns.compactMap { run in
            run.startCoordinate.map { RunMapPoint(id: run.id, coordinate: $0) }
        }
    }

    /// Attributes each located run to a US state by point-in-polygon and shades proportionally
    /// to run count. The coordinate snapshot happens on the main actor (Run isn't Sendable);
    /// the polygon tests run off-main so a large history never stalls the UI.
    private func computeStateIntensities() async {
        let coordinates = runStartPoints.map(\.coordinate)
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
        stateRanked = counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// The located runs whose start point falls inside the selected state — the pins drawn over
    /// it. Cheap: only the one selected boundary's polygons are tested, behind a bbox pre-filter.
    private func recomputeSelectedStateRunPoints() {
        guard let name = selectedStateName,
              let boundary = USStateBoundaries.shared.boundaries.first(where: { $0.name == name }) else {
            selectedStateRunPoints = []
            return
        }
        selectedStateRunPoints = runStartPoints.filter { point in
            let mapPoint = MKMapPoint(point.coordinate)
            guard boundary.boundingMapRect.contains(mapPoint) else { return false }
            return boundary.polygons.contains { $0.contains(mapPoint) }
        }
    }

    /// Attributes each located run to a country by point-in-polygon and shades proportionally to
    /// run count — the country sibling of `computeStateIntensities`.
    private func computeCountryIntensities() async {
        let coordinates = runStartPoints.map(\.coordinate)
        let boundaries = WorldCountryBoundaries.shared
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
        countryIntensities = counts.mapValues { min(1, (Double($0) / Double(maxCount)).squareRoot()) }
        countryRanked = counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    // MARK: Bottom — navigation controls

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if menuExpanded {
                Group {
                    controlButton(icon: "person.crop.circle", surface: .profile)
                    controlButton(icon: "calendar", surface: .timeline)
                    controlButton(icon: "trophy.fill", surface: .highlights)
                    controlButton(icon: "photo.artframe", surface: .studio)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            GlassIconButton(systemName: menuExpanded ? "xmark" : "ellipsis", isActive: menuExpanded) {
                withAnimation(Theme.spring) { menuExpanded.toggle() }
            }
        }
    }

    /// Filter control, pinned to the top-right of the map. Filtering only applies to the route
    /// map; the overview modes (history, locations) deliberately show everything, so it's
    /// disabled there.
    private var filterButton: some View {
        GlassIconButton(systemName: "line.3.horizontal.decrease", isActive: appModel.filter.isActive) {
            appModel.presentedSurface = .filters
        }
        .disabled(isOverviewMode)
        .opacity(isOverviewMode ? 0.35 : 1)
    }

    private func controlButton(icon: String, surface: AppModel.Surface, active: Bool = false) -> some View {
        GlassIconButton(systemName: icon, isActive: active) {
            menuExpanded = false
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
        case .highlights: HighlightsView()
        case .studio: StudioHomeView()
        case .yearInReview: YearInReviewView(year: stats.years.first ?? Calendar.current.component(.year, from: Date()))
        case .search: SearchView()
        case .settings: SettingsView()
        case .profile: ProfileView()
        case .mapPrint: MapPrintView(runs: scopedRuns, kind: currentPrintKind)
        }
    }
}
