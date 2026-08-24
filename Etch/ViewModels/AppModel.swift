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

    /// Studio-first mode: Studio is the home page, the map becomes a popup. Held here (rather than
    /// only in `@AppStorage`) so a change made deep inside nested sheets — Profile → Settings —
    /// propagates to `RootView` immediately instead of waiting for the next app launch. Persisted
    /// under the same `studioIsHome` key so the choice survives relaunches.
    var studioIsHome: Bool = UserDefaults.standard.bool(forKey: "studioIsHome") {
        didSet { UserDefaults.standard.set(studioIsHome, forKey: "studioIsHome") }
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
