import Foundation

/// Arriving at one activity on the map, from anywhere.
///
/// The reveal used to be three lines inside `HomeView`, and every one of its failure modes came
/// from the same thing: the decision about *when* the camera may move was tangled up with the view
/// state that answers it. So the decision lives here, as values — which is also what makes it
/// executable in CI without a device (`ScopeRuleCheckView` drives exactly these functions).
///
/// The rules it encodes, each of which was a real defect:
///
/// - The route map is permanently mounted but sits at `opacity 0` behind a place overview. A focus
///   issued while that overlay is up lands on an invisible map, and the reveal reports success. So
///   the overlay must be exited *first*, and the reveal may not complete while it is up.
/// - `HomeView` draws the route map from the filtered set, not the scoped set. Completing against
///   the scoped set (which is what a place overview shows) means focusing a run the map does not
///   have — `RunMapView.apply` looks the id up in its own `runs` and silently does nothing.
/// - Applying a filter or switching activity type refits the map. A reveal changes both on its way
///   in, so the focus must be protected until the map has actually consumed the camera command —
///   not merely until it has been issued.
/// - Visibility rules outrank Search. A hidden activity, or one whose type is disabled in
///   Settings, must not be reachable through a search result at all.

/// A request to show one activity on the map, outstanding until the map has genuinely moved to it.
struct RevealRequest: Equatable {

    /// How far along the reveal is. The distinction matters because the camera command is not
    /// consumed in the same update it is issued: `RunMapView` applies it in `updateUIView` and
    /// clears the binding asynchronously. Between those two moments the request must still be
    /// outstanding, or the filter/scope refit handlers — which fire in the very same update that
    /// started the reveal — will overwrite the focus before the map ever sees it.
    enum Phase: Equatable {
        /// Looking for its target among the runs the route map draws.
        case pending
        /// Focus issued. Waiting for the map to consume the camera command.
        case focused
    }

    let runID: UUID
    /// Makes two reveals of the *same* activity distinct values, so selecting one result twice
    /// still registers as a change.
    let token: Int
    var phase: Phase = .pending
}

/// What the map should do next about a pending reveal.
enum RevealStep: Equatable {
    /// The target is drawable now — move the camera to it.
    case focus(runID: UUID)
    /// The route map is hidden behind a place overview. Leave it; that rebuild asks again.
    case exitLocationOverlay
    /// Not drawable yet, but it could become drawable. Leave the request outstanding.
    case wait
    /// It can never be drawn — hidden by the reader, or a type disabled in Settings. Give up
    /// rather than hang, and do not override the reader's visibility rules to satisfy a search.
    case abandon
}

/// The state changes a reveal must make before its target can be drawn at all.
struct RevealPlan: Equatable {
    /// The activity scope to switch to. A selected type that excludes the target would leave the
    /// map with nothing to focus; widening to All is the smallest change that admits it, and it
    /// still never surfaces a type the reader disabled (`scoped(to:)` drops those regardless).
    var scope: ActivityScope
    /// Whether the active browse filter has to be cleared. A date range, Favourites or a city is a
    /// *query*, not a preference — arriving at a specific activity is a new query that replaces it.
    var clearsFilter: Bool
}

enum Reveal {

    /// Whether an activity may be revealed at all.
    ///
    /// Deliberately independent of the current scope and filter, both of which a reveal is allowed
    /// to change. Visibility is the one thing it may not change: an activity the reader hid, or one
    /// whose type is switched off in Settings, stays unreachable. Checked *before* any state is
    /// assigned, so a rejected reveal leaves the selection exactly as it was.
    static func isRevealable(_ run: Run) -> Bool {
        !run.isHidden && ActivitySettings.isVisible(run.activityType)
    }

    /// The scope/filter changes needed to make `run` drawable.
    static func plan(for run: Run, scope: ActivityScope, filter: RunFilter) -> RevealPlan {
        var resolved = scope
        // A scope the reader has since disabled in Settings is not a selection worth preserving.
        if !ActivitySettings.isVisible(resolved) { resolved = .all }
        if let selectedType = resolved.activityType, run.activityType != selectedType {
            resolved = .all
        }
        // Judged with `isPR: false`, which is the safe direction: only the map knows the real
        // personal-best set, so `.prs` mode is treated as excluding and cleared, rather than
        // risking a reveal that quietly lands on an activity the map is not drawing.
        let clears = filter.isActive && !filter.matches(run, isPR: false)
        return RevealPlan(scope: resolved, clearsFilter: clears)
    }

    /// The next step for an outstanding reveal.
    ///
    /// - Parameters:
    ///   - request: the outstanding request, if any.
    ///   - showLocations: whether a place overview is covering the route map.
    ///   - drawnRunIDs: the ids the **route map** is actually drawing — `HomeView`'s filtered set,
    ///     never the scoped set a place overview shows.
    ///   - isAdmissible: whether the target survives the current scope and visibility rules, i.e.
    ///     whether it could still become drawable.
    static func next(request: RevealRequest?,
                     showLocations: Bool,
                     drawnRunIDs: Set<UUID>,
                     isAdmissible: Bool) -> RevealStep {
        guard let request, request.phase == .pending else { return .wait }
        guard isAdmissible else { return .abandon }
        // Checked before the membership test on purpose. While the overlay is up the map is at
        // opacity 0, so "the target is in the drawn set" is not sufficient — and the drawn set
        // handed in during an overlay is the scoped one, which contains runs the route map does
        // not have.
        guard !showLocations else { return .exitLocationOverlay }
        guard drawnRunIDs.contains(request.runID) else { return .wait }
        return .focus(runID: request.runID)
    }

    /// Whether the map may refit itself to the filter/scope right now.
    ///
    /// False for the whole life of a reveal — including after the focus has been issued — because
    /// a refit at that moment replaces the camera command the map has not read yet.
    static func allowsCameraRefit(request: RevealRequest?) -> Bool {
        request == nil
    }
}
