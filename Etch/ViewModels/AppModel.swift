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
