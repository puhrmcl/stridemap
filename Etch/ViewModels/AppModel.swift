import SwiftUI
import Observation

/// Shared UI state for the map experience: the active filter, current selection, and
/// pending camera commands. Views read raw runs from SwiftData `@Query`; this object
/// holds the *interaction* state that must be shared across the map and its overlays.
@MainActor
@Observable
final class AppModel {

    var filter = RunFilter()
    var selectedRunID: UUID?
    var command: MapCameraCommand?

    /// Which full-screen surface (if any) is presented over the map.
    enum Surface: String, Identifiable {
        case filters, timeline, explore, travel, yearInReview, search, settings
        var id: String { rawValue }
    }
    var presentedSurface: Surface?

    /// Runs sharing (nearly) the same start point, surfaced as a pick-list when a tight
    /// cluster is tapped — so stacked runs at one location can be told apart and opened.
    var stackedRunIDs: [UUID]?

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
