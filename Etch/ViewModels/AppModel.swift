import SwiftUI
import Observation

/// Shared UI state for the map experience: the active filter, current selection, and
/// pending camera commands. Views read raw runs from SwiftData `@Query`; this object
/// holds the *interaction* state that must be shared across the map and its overlays.
@MainActor
@Observable
final class AppModel {

    var filter = RunFilter()
    /// The activity type shown across the app — All by default on each launch, per the design.
    var activityScope: ActivityScope = .all
    var selectedRunID: UUID?
    var command: MapCameraCommand?

    /// A monotonic revision of the map's *content* — bumped only when the routes/pins the map draws
    /// could actually differ (activities imported or edited, filter or scope changed, pins toggled).
    /// The route map compares this integer instead of re-hashing every activity on each representable
    /// update, so a sheet drag (or any unrelated `HomeView` re-render) never iterates the run set.
    /// Bump it via `bumpMapContent()` whenever map-relevant data changes.
    private(set) var mapContentRevision = 0
    func bumpMapContent() { mapContentRevision &+= 1 }

    /// Which of the four destinations is showing.
    ///
    /// Held here rather than as `@State` inside the tab view so any surface can move the app —
    /// Studio's masthead button reaches the map by selecting a tab, not by presenting one. Its
    /// predecessor, `studioIsHome`, did the opposite: it asked which half of the app you wanted
    /// and hid the other behind a modal. Persisted, because the tab you were on is a place, and
    /// returning to the app should return you to it.
    ///
    /// The stored value is checked against `destinations` rather than merely parsed. `.bag` is
    /// still a valid `EtchTab` — Studio's header button and the search prompts use it — but it is
    /// no longer a bar item, so anyone whose last session ended on the Bag would have been
    /// restored to a tab the `TabView` no longer contains, and met a blank screen on upgrade.
    var selectedTab: EtchTab = AppModel.restoredTab {
        didSet {
            // `.search` is a tool you pass through, never somewhere to be restored to.
            guard selectedTab != .search else { return }
            UserDefaults.standard.set(selectedTab.rawValue, forKey: "etchSelectedTab")
        }
    }

    /// The tab to open on, healed against the bar as it exists today.
    private static var restoredTab: EtchTab {
        let stored = EtchTab(rawValue: UserDefaults.standard.string(forKey: "etchSelectedTab") ?? "")
        guard let stored, EtchTab.destinations.contains(stored) else { return .map }
        return stored
    }

    /// Which full-screen surface (if any) is presented over the map.
    enum Surface: String, Identifiable {
        case filters, timeline, highlights, studio, yearInReview, search, settings, profile, mapPrint, hub, addHistory
        var id: String { rawValue }
    }
    var presentedSurface: Surface?

    /// Tapping the tab you are already on.
    ///
    /// Every iOS app of any size does something with this — Photos and Mail return you to the top
    /// of the list, Safari to the top of the page — because a tab bar is the only navigation
    /// always within reach, and "get me back to the start" is the thing you most often want from
    /// somewhere deep in a long scroll. Etch's lists run the other way round, oldest at the top,
    /// so the start is the foot: the newest activity.
    ///
    /// The tab alone cannot carry the signal, because the selection has not changed — hence the
    /// counter. Views watch the count and check the tab.
    private(set) var reselectedTab: EtchTab = .map
    private(set) var reselectCount = 0

    func reselect(_ tab: EtchTab) {
        reselectedTab = tab
        reselectCount += 1
    }

    /// Runs sharing (nearly) the same start point, surfaced as a pick-list when a tight
    /// cluster is tapped — so stacked runs at one location can be told apart and opened.
    var stackedRunIDs: [UUID]?

    /// A product Studio should open as soon as it appears.
    ///
    /// Studio's routing is eight cases of local `@State` — a picker for the ones that need an
    /// activity, a sheet for the books, a kind for the aggregate prints — and none of it is
    /// reachable from another tab. Rather than teach search that routing, or duplicate it, the
    /// request is left here and Studio answers it on arrival. One definition of what "open the
    /// medal frame" means, in the file that owns the medal frame.
    ///
    /// Cleared by Studio once acted on, so returning to the tab later does not re-open it.
    var studioRequest: StudioRequest?

    enum StudioRequest: Hashable {
        case product(StudioProduct)
        /// The print catalogue itself — what a search for a paper or a size is asking for.
        case prints
    }

    /// A saved Studio poster to open directly in the editor (from an explore-page thumbnail).
    var studioPoster: SavedPoster?

    /// A run to open in the Studio editor as a *new* creation (Create in Studio from a row's
    /// overflow menu). Cleared when the editor sheet closes.
    var studioRun: UUID?

    // MARK: Camera helpers

    func focus(on run: Run) {
        withAnimation(Theme.spring) {
            command = MapCameraCommand(target: .focus(runID: run.id))
        }
    }

    func fit(_ runs: [Run]) {
        command = MapCameraCommand(target: .fit(runIDs: runs.map(\.id)))
    }

    func fitAll(_ runs: [Run]) {
        command = MapCameraCommand(target: .fit(runIDs: []))
        // Empty list tells the map to fit whatever is currently visible.
        _ = runs
    }

    func select(_ run: Run) {
        selectedRunID = run.id
        focus(on: run)
    }

    // MARK: Reveal — arriving at one activity from anywhere

    /// Non-nil while a reveal is in flight. `HomeView` advances and clears it; the decisions it
    /// makes along the way are in `Reveal`, so they can be executed without a view.
    private(set) var revealRequest: RevealRequest?
    private var revealToken = 0

    /// Arrive on the Map and reveal one activity — the shared action behind every search result.
    ///
    /// Selecting a result used to call `select(_:)`, which sets the selection and fires a camera
    /// command immediately. That fails whenever the target is not among the activities the map
    /// draws: an activity outside the active browse filter is simply absent, and a location
    /// overlay hides the route map entirely, so the command lands on nothing. Worse, the camera
    /// then moved anyway — `HomeView` refits the map on any filter or scope change, so a focus
    /// issued before those settled was overwritten a moment later.
    ///
    /// So this makes the target admissible first and defers the camera. The focus itself is issued
    /// by `HomeView` once the activity is genuinely drawable, and is protected until the map has
    /// consumed it.
    ///
    /// - Returns: `false` when the activity may not be revealed at all — hidden by the reader, or
    ///   a type disabled in Settings. Nothing is mutated in that case, selection included:
    ///   visibility rules outrank Search, so a result that slipped through a caller's own filter
    ///   must not move the app or change what is selected.
    @discardableResult
    func reveal(_ run: Run) -> Bool {
        guard Reveal.isRevealable(run) else { return false }
        let plan = Reveal.plan(for: run, scope: activityScope, filter: filter)
        activityScope = plan.scope
        if plan.clearsFilter { filter = RunFilter() }
        selectedRunID = run.id
        selectedTab = .map
        revealToken &+= 1
        revealRequest = RevealRequest(runID: run.id, token: revealToken)
        return true
    }

    /// The focus command has been issued, but the map has not read it yet.
    ///
    /// The request stays outstanding through this phase deliberately. `HomeView`'s filter and
    /// scope handlers refit the camera, they fire in the same update that started the reveal, and
    /// they stand down only while a request exists — clearing it here is exactly how the focus
    /// used to be thrown away a moment after it was issued.
    func revealDidFocus() {
        guard var request = revealRequest, request.phase == .pending else { return }
        request.phase = .focused
        revealRequest = request
    }

    /// Called once the map has consumed the camera command, or the reveal can never be satisfied.
    func finishReveal() { revealRequest = nil }

    func clearSelection() {
        selectedRunID = nil
    }

    /// Recenters the map on the user's current location (the blue dot).
    func recenterOnUser() {
        command = MapCameraCommand(target: .userLocation)
    }

    /// Applies a filter change with an animated map transition.
    func setFilter(_ new: RunFilter) {
        withAnimation(Theme.gentle) { filter = new }
    }
}
