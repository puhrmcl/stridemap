import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UIKit

/// Carries the measured height of the totals pill's right-hand column up to the pill, so the
/// leading icon and divider can be sized to match it exactly.
private struct PillColumnHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Carries the measured full width of the totals pill up, so its dropdowns (and the selected-view
/// strip beneath it) can be sized to exactly the pill's width.
private struct PillWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The docked search sheet's live drag height, held in a tiny reference object rather than in
/// `HomeView`'s `@State`. The sheet updates it ~60×/s while dragging; keeping it *out* of HomeView's
/// own state means the map, the totals pill, and the (expensive) run-statistics derivations are not
/// re-evaluated on every finger movement. Only the small views that visibly track the sheet — the
/// floating controls and the top-bar fade — observe this, so finger movement drives a lightweight
/// presentation update instead of a full Home-screen re-render.
@MainActor
@Observable
final class SheetMetrics {
    var height: CGFloat = 62
}

/// The specific overlay shown under the home map's "Locations" mode.
enum LocationOverlay: String, CaseIterable, Identifiable {
    case cities, states, countries, landmarks
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cities: return "City"
        case .states: return "State"
        case .countries: return "Country"
        case .landmarks: return "Landmark"
        }
    }
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
    /// True when the map is presented as a popup from Studio-first mode: the bottom bar (Timeline /
    /// Achievements / Studio / Profile) is hidden and a close button returns to Studio.
    var isMapPopup: Bool = false

    @Environment(AppModel.self) private var appModel
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]

    @AppStorage("mapStyle") private var mapStyleRaw = MapStyleOption.standard.rawValue
    private var mapStyle: MapStyleOption { MapStyleOption(rawValue: mapStyleRaw) ?? .standard }
    /// When off, the route map hides the start pins and shows only the mapped lines.
    @AppStorage("showMapPins") private var showPins = true

    /// The route map's live center, for opening Look Around at whatever is on screen.
    @State private var centerBox = MapCenterBox()

    /// Live height of the docked search sheet, held in a lightweight observable so a drag doesn't
    /// invalidate HomeView's body (and re-run the run-statistics derivations) every frame. Only the
    /// floating controls and the top-bar fade observe it. Starts at the collapsed detent.
    @State private var sheetMetrics = SheetMetrics()
    /// Route map tilt: false = flat 2D, true = tilted 3D.
    @State private var is3D = false
    /// Measured map height, for sizing the sheet's detents.
    @State private var screenHeight: CGFloat = 800

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
    /// Bumped on every "jump to place" pick (city / state / country / landmark). Passed to the
    /// overview maps so each pick deterministically re-frames the map — even re-picking the same
    /// place — instead of relying on a binding whose async clear could be missed on device.
    @State private var placeFocusToken = 0

    /// Measured height of the pill's totals column, used to size the leading icon and divider to
    /// exactly that — `maxHeight: .infinity` would instead grab the whole top bar's height. Seeded
    /// near the real value so the icon's fill is bounded even before the first measurement lands.
    @State private var pillColumnHeight: CGFloat = 40

    /// Measured full width of the totals pill, so its dropdowns and the selected-view strip below
    /// it match the pill exactly (rather than a fixed guess).
    @State private var pillWidth: CGFloat = 250

    /// The map-mode dropdown, rendered as a custom panel that extends from the pill (not a detached
    /// native Menu), so it reads as part of the pill.
    @State private var showModeMenu = false
    @State private var showTypeMenu = false
    /// The base-map-style dropdown, rendered as a custom glass panel extending from the map-style
    /// button, so it matches the pill's dropdowns rather than using a detached native Menu.
    @State private var showMapStyleMenu = false

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

    /// Concrete activity types (not "All") that are both enabled in Settings and actually present
    /// in the library. When only one qualifies, the app has nothing to switch between.
    private var presentActivityScopes: [ActivityScope] {
        [.runs, .hikes, .rides, .walks].filter { ActivitySettings.isVisible($0) && !allRuns.scoped(to: $0).isEmpty }
    }
    /// True when there's a single activity type — the activity selector is hidden and the pill
    /// collapses to that one type, with no icon or dropdown to choose between.
    private var isSingleActivity: Bool { presentActivityScopes.count <= 1 }
    private var soleScope: ActivityScope { presentActivityScopes.first ?? .runs }

    /// The scope actually used for totals and labels: the sole type when there's only one, `.all`
    /// if the stored scope was hidden in Settings, otherwise the user's selection.
    private var effectiveScope: ActivityScope {
        if isSingleActivity { return soleScope }
        if !ActivitySettings.isVisible(appModel.activityScope) { return .all }
        return appModel.activityScope
    }

    /// Runs limited to the active activity scope (All / Runs / Hikes / Walks) — the base for every
    /// map, total, and overview below.
    private var scopedRuns: [Run] { allRuns.scoped(to: effectiveScope) }

    /// The newest edit timestamp across every activity. A route edit or favorite toggle bumps a
    /// run's `updatedAt` without changing the count, so this is what tells the map to redraw after
    /// an in-place edit. It's an O(n) max, but evaluated only when `HomeView.body` genuinely
    /// re-renders — never on the per-frame sheet-drag path, which no longer re-runs the body — so
    /// it costs nothing during interaction while still catching every content change.
    private var runEditSignature: Double {
        var newest = 0.0
        for run in allRuns { newest = max(newest, run.updatedAt.timeIntervalSinceReferenceDate) }
        return newest
    }

    /// Everything that determines what the route map draws, as one Equatable value. A single
    /// `.onChange` on this advances the map's content revision, so the map rebuilds its overlays
    /// only when the drawable set truly changes — and folding it into one value keeps `HomeView`'s
    /// body to a single extra modifier, which the SwiftUI type-checker handles far more cheaply
    /// than several separate `.onChange` handlers.
    private var mapContentInputs: MapContentInputs {
        MapContentInputs(
            filter: appModel.filter,
            scope: appModel.activityScope,
            runCount: allRuns.count,
            newestEdit: runEditSignature
        )
    }

    /// The map's drawable-content inputs, compared as a whole to trigger a single revision bump.
    /// `showPins` is deliberately *not* here: `RunMapView` owns the pins toggle through its own
    /// `appliedShowPins` check, so routing it through the content revision as well would rebuild
    /// the clusters twice for one toggle.
    private struct MapContentInputs: Equatable {
        var filter: RunFilter
        var scope: ActivityScope
        var runCount: Int
        var newestEdit: Double
    }

    private var stats: RunStatistics { RunStatistics(scopedRuns) }

    /// Runs that count as milestones — their map pins get the gold trophy.
    private var milestoneRunIDs: Set<UUID> { stats.milestoneRunIDs }

    /// Runs passing the active filter. The PRs view shows the runs that currently *hold* an
    /// achievement (the milestone set — furthest, fastest, highest climb, and each distance PR),
    /// i.e. the same activities marked with a gold pin, rather than the full distance progression.
    private var visibleRuns: [Run] {
        let prs = appModel.filter.mode == .prs ? stats.milestoneRunIDs : []
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

    /// Totals for whatever the map is currently showing. Excludes activities the user opted out
    /// of totals (e.g. a hand-entered race) — they still appear on the map, just not in the count.
    private var shownStats: RunStatistics { RunStatistics(shownRuns.countingTotals) }

    /// Zoom/recenter the route or history map to the extent of the runs on screen. The cities
    /// and states overviews use their own maps (no camera command) and already frame on entry.
    private func fitShownRuns() {
        guard !showLocations else { return }
        appModel.fit(shownRuns)
    }

    /// The screen's bottom safe-area inset — the floating controls track the search sheet's true
    /// top edge, which sits relative to the physical bottom (not the safe-area line).
    private var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    /// The status-bar / Dynamic Island height, so the fully-expanded search page can run right up
    /// to just below it — above the totals pill. Uses the status-bar frame rather than the window's
    /// safeAreaInsets.top, which the totals pill's own safeAreaInset inflates.
    private var topSafeArea: CGFloat {
        let bar = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.statusBarManager?.statusBarFrame.height ?? 0
        return bar > 0 ? bar : 47   // fall back to a typical notch inset
    }

    /// The search sheet's full-height detent — runs to just below the status bar / Dynamic Island.
    /// Depends only on the (rarely-changing) screen height, never the live drag position.
    private var sheetMaxHeight: CGFloat {
        max(screenHeight * 0.5, screenHeight - topSafeArea)
    }

    /// The map layer plus the state-syncing modifiers that don't depend on the search sheet's live
    /// height. Split out of `body` so the modifier chain is two shorter expressions rather than one
    /// enormous one — which keeps SwiftUI's type-checker comfortably under its per-expression time
    /// limit (a single chain this long trips "unable to type-check in reasonable time").
    @ViewBuilder private var mapCanvas: some View {
        @Bindable var appModel = appModel

        Group {
            if showLocations {
                if locationOverlay == .states {
                    StatesMapView(
                        intensities: stateIntensities,
                        mapStyle: mapStyle,
                        focusStateName: $focusStateName,
                        focusToken: placeFocusToken,
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
                        focusCountryName: $focusCountryName,
                        focusToken: placeFocusToken
                    )
                    .id("countries-\(locationRecenterToken)")
                } else {
                    CitiesMapView(
                        cities: overlayPlaces,
                        selectedRunID: $appModel.selectedRunID,
                        stackedRunIDs: $appModel.stackedRunIDs,
                        focusCoordinate: $focusCity,
                        focusToken: placeFocusToken,
                        mapStyle: mapStyle
                    )
                    .id("\(locationOverlay.rawValue)-\(locationRecenterToken)")
                }
            } else {
                RunMapView(
                    runs: visibleRuns,
                    milestoneRunIDs: milestoneRunIDs,
                    selectedRunID: $appModel.selectedRunID,
                    stackedRunIDs: $appModel.stackedRunIDs,
                    command: $appModel.command,
                    mapStyle: mapStyle,
                    showPins: showPins,
                    is3D: is3D,
                    centerBox: centerBox,
                    contentRevision: appModel.mapContentRevision
                )
            }
        }
        .ignoresSafeArea()
        // Tap anywhere on the map to dismiss the open mode dropdown (it sits above this layer).
        .overlay {
            if showModeMenu || showTypeMenu {
                Color.black.opacity(0.0001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Theme.spring) { showModeMenu = false; showTypeMenu = false } }
            }
        }
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
        // Advance the map's content revision on the discrete events that change what it draws —
        // filter, scope, new/removed activities, or a route edit / favorite toggle (same count, new
        // `updatedAt`) — folded into one Equatable value so a single `onChange` covers them all.
        // (The pins toggle is handled separately inside RunMapView, so it's not included here.)
        // The route map then rebuilds overlays/clusters only when this changes, never on an
        // unrelated re-render (a sheet drag), which is the whole point of the revision.
        .onChange(of: mapContentInputs) { appModel.bumpMapContent() }
        .onAppear {
            // Heal a stored scope that's since been hidden in Settings (e.g. viewing Hikes, then
            // turning hikes off) so the selector and totals never point at an unavailable type.
            if !ActivitySettings.isVisible(appModel.activityScope) { appModel.activityScope = .all }
        }
    }

    var body: some View {
        mapCanvas
        // Controls float via safe-area insets rather than a ZStack overlay, so SwiftUI owns
        // their hit-testing and they don't compete with the map's UIKit gestures (which made
        // the buttons need several taps).
        .safeAreaInset(edge: .top, spacing: 0) {
            // The fade-with-sheet lives in a child that observes the live height, so the totals pill
            // fades smoothly as the page expands without re-running HomeView's body every frame.
            SheetFade(metrics: sheetMetrics, maxHeight: sheetMaxHeight) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        // The docked Apple Maps-style search sheet plus the floating map controls that track its
        // top edge. A plain overlay (not a system sheet), so the map stays interactive above it and
        // run detail / surfaces keep presenting through the map's own sheet with no conflict. The
        // Studio-first popup keeps a focused map (close button returns to Studio) — no dock there.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { screenHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in screenHeight = h }
            }
        )
        // The docked search sheet plus the floating map controls that track its top edge — both in
        // one overlay so HomeView's (large) body gains no extra modifier. The sheet is a UIKit motion
        // shell (`SearchSheetHost`) hosting the SwiftUI search content: UIKit owns the physical
        // drag/settle (a transform-driven, interruptible sheet), SwiftUI owns the content. The shell
        // writes the live height into the same `sheetMetrics` bridge the controls and totals pill
        // already track, so the map stays completely isolated during a drag.
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                SheetLayer(metrics: sheetMetrics, maxHeight: sheetMaxHeight) {
                    floatingControls
                }
                SearchSheetHost(
                    maxHeight: sheetMaxHeight,
                    bottomSafeArea: bottomSafeArea,
                    reduceMotion: reduceMotion,
                    appModel: appModel,
                    modelContainer: modelContext.container,
                    onHeight: { sheetMetrics.height = $0 }
                )
                .ignoresSafeArea()
            }
        }
        .overlay {
            if allRuns.isEmpty {
                emptyOrSyncing
            }
        }
        // The Apple Maps-style "Map Type" picker: a rounded-top card that rises from the bottom
        // with a thumbnail tile per base map, over a dimmed backdrop.
        .overlay {
            if showMapStyleMenu { mapModesSheet }
        }
        // The Activity Type / Activity View pickers — tile bottom sheets matching Map Type.
        .overlay {
            if showTypeMenu { activityTypeSheet }
        }
        .overlay {
            if showModeMenu { activityViewSheet }
        }
        // A single sheet for both surfaces and the run detail. Two `.sheet` modifiers — even
        // on different views — can leave one flaky; one sheet driven by one binding is
        // reliable, so the bottom buttons always present on the first tap.
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .surface(let surface):
                surfaceView(for: surface)
                    // A grabber makes the swipe-down-to-close obvious now the Done button is gone.
                    .presentationDragIndicator(.visible)
            case .run(let id):
                if let run = allRuns.first(where: { $0.id == id }) {
                    RunDetailView(run: run)
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.regularMaterial)
                        // The detail has its own ✕ close, so the redundant drag line (which sat
                        // awkwardly above the toolbar) is hidden — swipe-to-dismiss still works.
                        .presentationDragIndicator(.hidden)
                }
            case .stack(let ids):
                RunStackView(runs: allRuns.filter { ids.contains($0.id) })
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.regularMaterial)
            case .studioPoster(let poster):
                if let run = allRuns.first(where: { $0.id == poster.runID }) {
                    StudioView(run: run, poster: poster)
                }
            }
        }
        // Let the keyboard float over the map and the docked search sheet (Apple Maps behaviour)
        // rather than pushing the whole screen up when the search field is focused.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // A light tactile tick when the base map type changes from the Map Type picker.
        .sensoryFeedback(.selection, trigger: mapStyleRaw)
        // A selection tick when the activity type or view actually changes.
        .sensoryFeedback(.selection, trigger: appModel.activityScope)
        .sensoryFeedback(.selection, trigger: appModel.filter.mode)
        .sensoryFeedback(.selection, trigger: showLocations)
        // A soft tick as either picker opens or closes.
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: showTypeMenu)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: showModeMenu)
    }

    /// The one thing presented over the map: a surface (bottom buttons), a selected run, or a
    /// pick-list of runs stacked at one location.
    private enum ActiveSheet: Identifiable {
        case surface(AppModel.Surface)
        case run(UUID)
        case stack([UUID])
        case studioPoster(SavedPoster)
        var id: String {
            switch self {
            case .surface(let surface): return "surface-\(surface.rawValue)"
            case .run(let id): return "run-\(id.uuidString)"
            case .stack(let ids): return "stack-\(ids.map(\.uuidString).joined())"
            case .studioPoster(let poster): return "poster-\(poster.id.uuidString)"
            }
        }
    }

    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if let poster = appModel.studioPoster { return .studioPoster(poster) }
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
                case .studioPoster(let poster):
                    appModel.studioPoster = poster
                case nil:
                    appModel.presentedSurface = nil
                    appModel.selectedRunID = nil
                    appModel.stackedRunIDs = nil
                    appModel.studioPoster = nil
                }
            }
        )
    }

    // MARK: Top — totals + mode toggles

    private var topBar: some View {
        // The pill is centred in the screen (its fixed size keeps the layout steady); its dropdowns
        // drop straight beneath it, centred to match. The Studio-first close button and the sync
        // indicator float at the row's edges without shifting the pill.
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                totalsPill
                HStack(spacing: 8) {
                    if isMapPopup {
                        GlassIconButton(systemName: "xmark") { dismiss() }
                    }
                    Spacer(minLength: 8)
                    if sync.isSyncing {
                        GlassContainer(padding: 10, cornerRadius: 18) {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Syncing").font(.caption.weight(.medium))
                            }
                        }
                    }
                }
            }

            // Places: independent Country / State / City / Landmark dropdowns under the pill. The
            // Activity Type / View pickers are now bottom sheets (see the overlays below), not
            // dropdowns, so they no longer sit under the pill.
            if showLocations && !showTypeMenu && !showModeMenu { modeSelector }
        }
    }

    /// The current view's name — used for VoiceOver only (the pill shows an icon, not text): the
    /// map-mode when showing routes, else "Places".
    private var currentViewName: String {
        showLocations ? locationOverlay.label : modeLabel(appModel.filter.mode)
    }

    private var currentViewSymbol: String {
        showLocations ? locationOverlay.symbol : appModel.filter.mode.symbol
    }

    /// The current activity type's short name — for VoiceOver.
    private var currentScopeName: String {
        appModel.activityScope == .all ? "All" : appModel.activityScope.label
    }

    /// One glass pill, a single row: the activity-type selector on the left, the totals in the
    /// middle (tap to open the map-view dropdown), and the filter button on the right (opens the
    /// full Filters as a bottom sheet). Each side element is sized to the totals' height.
    private var totalsPill: some View {
        HStack(spacing: 7) {
            // The activity-type selector only appears when there's more than one type to choose
            // between; with a single type the pill leads with the totals.
            if !isSingleActivity {
                typeSelector
                    .frame(height: pillColumnHeight)
                pillDivider
            }
            // Middle: the totals (display only).
            metricsRow
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: PillColumnHeightKey.self, value: geo.size.height)
                    }
                )
            pillDivider
            // Right: the current view (All Runs / PRs / Places …) with a dropdown chevron — tap to
            // open the map-view (mode) dropdown.
            viewSelector
                .frame(height: pillColumnHeight)
        }
        .onPreferenceChange(PillColumnHeightKey.self) { if $0 > 0 { pillColumnHeight = $0 } }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .glassBackground(cornerRadius: 17)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PillWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(PillWidthKey.self) { if $0 > 0 { pillWidth = $0 } }
    }

    /// The right control: the current view's icon (map / trophy / heart / pin …) plus a dropdown
    /// chevron — icon-only, so it stays compact and the pill never grows with a long view name.
    /// Tapping anywhere in it opens the Activity View selector.
    private var viewSelector: some View {
        Button {
            withAnimation(Theme.spring) { showModeMenu.toggle(); showTypeMenu = false }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: currentViewSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(showModeMenu ? 180 : 0))
            }
            .foregroundStyle(Theme.accentOnGlass)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Activity View, \(currentViewName)")
        .accessibilityHint("Double tap to change activity view.")
    }

    /// A hairline separator sized to the pill's row height.
    private var pillDivider: some View {
        // A true hairline, not a 1pt bar — at 3x it's still crisp, and the pill reads lighter.
        Rectangle()
            .fill(.secondary.opacity(0.3))
            .frame(width: 0.5, height: pillColumnHeight)
    }

    /// The activity-type selector on the left of the pill — All Types / Runs / Hikes / Rides /
    /// Walks. The small chevron beside the icon signals it's a dropdown; it drops from the icon.
    private var typeSelector: some View {
        Button {
            withAnimation(Theme.spring) { showTypeMenu.toggle(); showModeMenu = false }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: appModel.activityScope.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(showTypeMenu ? 180 : 0))
            }
            .foregroundStyle(Theme.accentOnGlass)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Activity Type, \(currentScopeName)")
        .accessibilityHint("Double tap to change activity type.")
    }

    /// The totals — activity count then distance, separated by a dot. Count has no leading icon
    /// (it would just duplicate the activity-type icon on the pill's left).
    private var metricsRow: some View {
        // Align the two numbers on one baseline; each unit label stacks beneath its own number.
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            metric(
                value: shownStats.totalRuns.formatted(),
                unit: effectiveScope.countNoun
            )
            Text("·")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            metric(
                value: Format.distanceValue(shownStats.totalDistanceMeters)
                    .formatted(.number.precision(.fractionLength(0))),
                unit: UnitSystem.current.distanceSuffix
            )
        }
    }

    /// The Activity Type bottom sheet — tiles for All / Runs / Hikes / Rides / Walks (only the
    /// activity types enabled in Settings), matching the Map Type sheet's design.
    private var activityTypeSheet: some View {
        EtchSelectionSheet(
            title: "Activity Type",
            options: activityScopeOptions.map { scope in
                SelectionOption(
                    id: scope.rawValue,
                    icon: scope.icon,
                    label: scope == .all ? "All" : scope.label,
                    isSelected: appModel.activityScope == scope,
                    accessibilityLabel: "Activity Type, \(scope == .all ? "All" : scope.label)"
                ) { applyScope(scope) }
            }
        ) {
            withAnimation(Theme.spring) { showTypeMenu = false }
        }
    }

    /// The Activity View bottom sheet — All / Recent / PRs / Races / Favorites / Places, matching
    /// the Map Type sheet. `RunFilter.Mode.allCases` supplies the first five; Places is appended.
    private var activityViewSheet: some View {
        EtchSelectionSheet(
            title: "Activity View",
            options: activityViewOptions
        ) {
            withAnimation(Theme.spring) { showModeMenu = false }
        }
    }

    private var activityViewOptions: [SelectionOption] {
        var options = RunFilter.Mode.allCases.map { mode in
            SelectionOption(
                id: mode.rawValue,
                icon: mode.symbol,
                label: modeLabel(mode),
                isSelected: !showLocations && appModel.filter.mode == mode,
                accessibilityLabel: "Activity View, \(modeLabel(mode))"
            ) { applyMode(.mode(mode)) }
        }
        // The place maps are first-class views here, one tile each — City, State, Country,
        // Landmark. They used to hide behind a single "Places" tile that then revealed a separate
        // dropdown under the pill, which made the choropleths hard to reach (and easy to lose). Now
        // choosing "State" switches the map to the state choropleth in one tap, exactly like
        // choosing Recent or PRs switches the route view.
        options.append(contentsOf: LocationOverlay.allCases.map { overlay in
            SelectionOption(
                id: "place-\(overlay.rawValue)",
                icon: overlay.symbol,
                label: overlay.label,
                isSelected: showLocations && locationOverlay == overlay,
                accessibilityLabel: "Activity View, \(overlay.label)"
            ) { applyMode(.place(overlay)) }
        })
        return options
    }

    /// Applies an activity-type choice from the type sheet, then closes it.
    private func applyScope(_ scope: ActivityScope) {
        withAnimation(Theme.gentle) {
            appModel.activityScope = scope
            // Returning to All also drops any lingering Races / PRs / Locations view.
            if scope == .all {
                showLocations = false
                var f = appModel.filter
                f.mode = .all
                appModel.setFilter(f)
            }
        }
        withAnimation(Theme.spring) { showTypeMenu = false }
    }

    /// Applies a mode chosen in the Activity View sheet, then closes it.
    private func applyMode(_ newValue: ModeSelection) {
        withAnimation(Theme.gentle) {
            showLocations = false
            switch newValue {
            case .mode(let mode):
                var f = appModel.filter
                f.mode = mode
                appModel.setFilter(f)
            case .place(let overlay):
                // Switch straight to that place map. Setting the overlay before showing it means
                // the correct choropleth/pin map is the first thing built, with no flash of the
                // previously-selected one.
                locationOverlay = overlay
                showLocations = true
            }
        }
        withAnimation(Theme.spring) { showModeMenu = false }
    }

    /// The scopes offered — hikes/walks appear only when their visibility is on.
    private var activityScopeOptions: [ActivityScope] {
        ActivitySettings.visibleScopes
    }

    /// The plural activity noun for the active scope — "Runs", "Hikes", "Activities" — so map-mode
    /// labels match the selected activity ("Long Hikes", never "Long Runs" under Hikes).
    private var scopeNounPlural: String {
        switch effectiveScope {
        case .all:   return "Activities"
        case .runs:  return "Runs"
        case .hikes: return "Hikes"
        case .rides: return "Rides"
        case .walks: return "Walks"
        }
    }

    /// A map-mode's label phrased for the active activity scope, so "runs" never shows under Hikes.
    /// Recent / PRs / Races / Favorites are activity-neutral and read the same everywhere.
    private func modeLabel(_ mode: RunFilter.Mode) -> String {
        switch mode {
        case .all:       return "All"
        case .recent:    return "Recent"
        case .prs:       return "PRs"
        case .races:     return "Races"
        case .favorites: return "Favorites"
        }
    }

    /// One metric with the unit label stacked *under* the number, so the column is only as wide as
    /// the number (or the short label) — condensing the pill versus laying value + unit side by side.
    private func metric(value: String, unit: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                // Monospaced digits so the count/distance don't jitter the pill as they tick.
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// What the map is currently showing: a run-filter mode, the history etch, or a Locations
    /// overlay (whose specific overlay is chosen by a secondary dropdown). Set via `applyMode`.
    private enum ModeSelection: Hashable {
        case mode(RunFilter.Mode)
        case place(LocationOverlay)
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

    /// Places: a single "jump to" menu that zooms the active place map to a chosen state / country /
    /// city / landmark. Which place *map* is showing is chosen in the Activity View sheet (one tile
    /// per place type), so this bar no longer carries a second overlay dropdown — it does the one
    /// thing the sheet can't: pick a specific place out of a long list.
    private var modeSelector: some View {
        placesMenu
            .padding(.vertical, 3)   // room for the pill's soft shadow
    }

    /// A "jump to" menu that zooms the active overlay to a chosen place.
    @ViewBuilder
    private var placesMenu: some View {
        if locationOverlay == .states {
            if !stateRanked.isEmpty {
                placesMenuLabel(title: selectedPlaceLabel ?? "All") {
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
                            placeFocusToken += 1
                        }
                    }
                }
            }
        } else if locationOverlay == .countries {
            if !countryRanked.isEmpty {
                placesMenuLabel(title: selectedPlaceLabel ?? "All") {
                    ForEach(countryRanked, id: \.name) { item in
                        Button("\(displayCountry(item.name))  ·  \(item.count)") {
                            focusCountryName = item.name
                            selectedPlaceLabel = displayCountry(item.name)
                            placeFocusToken += 1
                        }
                    }
                }
            }
        } else if locationOverlay == .cities, !overlayPlaces.isEmpty {
            // Cities grouped under their state, so a long list stays navigable.
            placesMenuLabel(title: selectedPlaceLabel ?? "All") { citiesByStateMenu }
        } else if !overlayPlaces.isEmpty {
            // Landmarks — a flat list.
            placesMenuLabel(title: selectedPlaceLabel ?? "All") {
                ForEach(overlayPlaces) { place in
                    Button("\(shortPlaceLabel(place))  ·  \(place.runs.count)") {
                        focusCity = place.coordinate
                        selectedPlaceLabel = shortPlaceLabel(place)
                        placeFocusToken += 1
                    }
                }
            }
        }
    }

    /// The Cities jump-to list, grouped into a section per state (most-visited state first), with
    /// the bare city name under each — so a big travel history reads as a tidy state-by-state index.
    @ViewBuilder private var citiesByStateMenu: some View {
        let grouped = Dictionary(grouping: overlayPlaces) { $0.runs.first?.state ?? "" }
        let orderedStates = grouped.keys.sorted { a, b in
            let ca = grouped[a]?.reduce(0) { $0 + $1.runs.count } ?? 0
            let cb = grouped[b]?.reduce(0) { $0 + $1.runs.count } ?? 0
            return ca != cb ? ca > cb : a < b
        }
        ForEach(orderedStates, id: \.self) { state in
            Section(state.isEmpty ? "Other" : state) {
                ForEach(grouped[state] ?? []) { place in
                    Button("\(cityOnly(place))  ·  \(place.runs.count)") {
                        focusCity = place.coordinate
                        selectedPlaceLabel = cityOnly(place)
                        placeFocusToken += 1
                    }
                }
            }
        }
    }

    /// Just the city name from a "City, State, Country" travel label (the state is the section head).
    private func cityOnly(_ place: RunStatistics.TravelPlace) -> String {
        place.label.components(separatedBy: ", ").first ?? place.label
    }

    /// A shorter display name for a country — "USA" for the United States, keeping the list tidy.
    private func displayCountry(_ name: String) -> String {
        (name == "United States" || name == "United States of America") ? "USA" : name
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

    /// The map's action buttons, grouped in a single vertical capsule (Apple Maps style): base-map
    /// style, show/hide pins, recenter-to-fit, and current location. In the Locations overview the
    /// pins toggle is dropped and recenter reframes the overlay.
    /// The map's floating controls: the 2D/3D toggle on the *left* (where Look Around's binoculars
    /// used to sit), the action capsule on the right.
    private var floatingControls: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if !showLocations { dimensionButton }
            Spacer(minLength: 0)
            actionCapsule
        }
        .padding(.horizontal, MapControl.edgeInset)
        .frame(maxWidth: .infinity)
    }

    /// Toggles the route map between a flat 2D view and a tilted 3D view (Apple Maps' "3D"
    /// button). The label shows the mode you'll switch *to*. Sized to the shared map-control size so
    /// it reads as a peer of the right-hand capsule, not a dominant standalone button.
    private var dimensionButton: some View {
        Button {
            withAnimation(Theme.spring) { is3D.toggle() }
        } label: {
            Text(is3D ? "2D" : "3D")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(is3D ? Theme.accentOnGlass : .primary)
                .frame(width: MapControl.size, height: MapControl.size)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(is3D ? "Switch to 2D" : "Switch to 3D")
    }

    /// The right-side map controls as one narrow vertical glass capsule (Apple Maps): a map-type
    /// button that opens the Map Type sheet, and the current-location button. The extra Etch options
    /// (start pins, frame-to-fit) live inside the Map Type sheet so this capsule stays the same clean
    /// two-control pill Apple uses.
    private var actionCapsule: some View {
        VStack(spacing: 0) {
            capsuleButton(systemName: "map", isActive: showMapStyleMenu) {
                withAnimation(Theme.spring) { showMapStyleMenu.toggle() }
            }
            .accessibilityLabel("Map type")

            capsuleDivider

            capsuleButton(systemName: "location.fill") { appModel.recenterOnUser() }
                .accessibilityLabel("Current location")
        }
        .glassBackground(cornerRadius: MapControl.size / 2)
    }

    /// One flat icon button inside the action capsule (the capsule itself carries the glass).
    private func capsuleButton(systemName: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? Theme.accentOnGlass : .primary)
                .frame(width: MapControl.size, height: MapControl.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A hairline between capsule buttons. A *fixed* width keeps it from stretching the capsule to
    /// full screen width (an unconstrained Rectangle expands to infinity).
    private var capsuleDivider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: MapControl.size - 18, height: 0.5)
    }

    /// The Apple Maps-style "Map Type" picker: a dimmed backdrop with a rounded-top card rising
    /// from the bottom edge, holding a thumbnail tile per base map.
    private var mapModesSheet: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(Theme.spring) { showMapStyleMenu = false } }
            mapModesCard
                .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var mapModesCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Text("Map Type")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity)
                HStack {
                    Spacer()
                    Button { withAnimation(Theme.spring) { showMapStyleMenu = false } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(MapStyleOption.allCases) { style in
                        mapModeTile(style)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }

            mapOptionsSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity)
        .background(
            .regularMaterial,
            in: UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38, style: .continuous)
                .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: -2)
    }

    /// Display options that used to hang off the floating capsule — now grouped in the Map Type
    /// sheet (Apple keeps map toggles here), so the on-map controls stay a clean two-button pill.
    /// Start pins toggle for the route map; a frame-to-fit action that reframes the shown runs (or
    /// resets the Locations overview).
    @ViewBuilder private var mapOptionsSection: some View {
        VStack(spacing: 0) {
            if !showLocations {
                Toggle(isOn: $showPins.animation(Theme.gentle)) {
                    Label("Show start pins", systemImage: showPins ? "mappin.and.ellipse" : "mappin.slash")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                }
                .tint(Theme.accent)
                .frame(minHeight: 44)

                Divider()
            }

            Button {
                withAnimation(Theme.spring) { showMapStyleMenu = false }
                if showLocations {
                    selectedStateName = nil
                    selectedPlaceLabel = nil
                    locationRecenterToken += 1
                } else {
                    fitShownRuns()
                }
            } label: {
                Label(showLocations ? "Reset view" : "Frame all activities",
                      systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator.opacity(0.25), lineWidth: 0.5))
    }

    private func mapModeTile(_ style: MapStyleOption) -> some View {
        let selected = mapStyle == style
        return Button {
            withAnimation(Theme.gentle) { mapStyleRaw = style.rawValue }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(mapModeGradient(style))
                    .frame(width: 92, height: 92)
                    .overlay(
                        Image(systemName: style.symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 3)
                    )
                Text(style.label)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected ? Theme.accent : .primary)
            }
        }
        .buttonStyle(.plain)
    }

    /// A representative swatch gradient for each base map, evoking its look in the picker tiles.
    private func mapModeGradient(_ style: MapStyleOption) -> LinearGradient {
        let colors: [Color]
        switch style {
        case .standard:
            colors = [Color(red: 0.83, green: 0.86, blue: 0.83), Color(red: 0.70, green: 0.77, blue: 0.72)]
        case .explore:
            colors = [Color(red: 0.87, green: 0.89, blue: 0.85), Color(red: 0.76, green: 0.82, blue: 0.74)]
        case .night:
            colors = [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.05, green: 0.06, blue: 0.12)]
        case .terrain:
            colors = [Color(red: 0.47, green: 0.56, blue: 0.36), Color(red: 0.33, green: 0.40, blue: 0.26)]
        case .satellite:
            colors = [Color(red: 0.20, green: 0.30, blue: 0.28), Color(red: 0.36, green: 0.40, blue: 0.24)]
        case .hybrid:
            colors = [Color(red: 0.15, green: 0.17, blue: 0.22), Color(red: 0.24, green: 0.28, blue: 0.26)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
        case .hub: HubView()
        case .filters: FilterView()
        case .timeline: TimelineView()
        case .highlights: HighlightsView()
        case .studio: StudioHomeView()
        case .yearInReview: YearInReviewView(year: stats.years.first ?? Calendar.current.component(.year, from: Date()))
        case .search: SearchView()
        case .settings: SettingsView()
        case .profile: ProfileView()
        case .mapPrint: MapPrintView(runs: scopedRuns, kind: currentPrintKind)
        case .addHistory: NavigationStack { AddHistoryView() }
        }
    }
}

// MARK: - Sheet-tracking layers

/// Fades (and disables) its content as the search sheet expands past its mid rest. Reads the live
/// sheet height from the shared `SheetMetrics`, so only this small view re-renders during a drag —
/// the totals pill it wraps is built once by HomeView and reused.
private struct SheetFade<Content: View>: View {
    let metrics: SheetMetrics
    let maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let mid = max(260, maxHeight * 0.5)
        let progress = max(0, min(1, (metrics.height - mid) / max(1, maxHeight - mid)))
        content
            .opacity(1 - progress)
            .allowsHitTesting(progress < 0.5)
    }
}

/// The floating map controls, tracking the search sheet's top edge. It owns the live-height layout
/// (reading `SheetMetrics`, which the UIKit sheet shell writes each frame) so a drag re-renders only
/// this small layer — never HomeView's body, the map, or the run-statistics work. The sheet itself
/// is a sibling UIKit overlay (`SearchSheetHost`), so this layer no longer embeds it.
private struct SheetLayer<Controls: View>: View {
    @Bindable var metrics: SheetMetrics
    let maxHeight: CGFloat
    @ViewBuilder var controls: Controls

    /// The sheet's collapsed visible height (the floating pill plus the gap it floats above the
    /// physical bottom edge).
    private var collapsed: CGFloat { SearchSheetInteractionController.collapsedVisibleHeight }

    var body: some View {
        let mid = max(260, maxHeight * 0.5)
        // Fade the controls out over the collapsed → mid range as the sheet rises.
        let t = max(0, min(1, (metrics.height - collapsed) / max(1, mid - collapsed)))
        ZStack(alignment: .bottom) {
            controls
                // `metrics.height` is measured from the physical bottom edge (as is this padding,
                // since the layer ignores the bottom safe area), so this clears the sheet's true top
                // edge by a fixed gap. Apple Maps leaves ~20pt between its map controls and the
                // search bar; the round glass buttons need that much so their curved edges don't
                // read as touching the pill's rounded corners.
                .padding(.bottom, max(20, metrics.height + 30))
                .opacity(1 - t)
                .allowsHitTesting(t < 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Ignore the top inset too (the totals pill reserves it via safeAreaInset).
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
