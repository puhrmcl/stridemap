import SwiftUI

/// Presentation state for the docked search sheet, written by the UIKit interaction controller
/// (`SearchSheetInteractionController`) and read by the SwiftUI content (`SearchSheetContent`).
///
/// Kept deliberately tiny. The controller updates `progress`/`isExpanded`/`isAtFull` as the sheet
/// moves, but the SwiftUI content only reads the *discrete* flags (`isExpanded`, `isAtFull`) — which
/// change a handful of times per interaction, never per frame. The continuous per-frame position is
/// consumed by the controller itself (for the surface mask) and bridged to the floating chrome
/// through a plain closure, so a drag never re-evaluates the search content's body.
@MainActor
@Observable
final class SearchSheetModel {
    /// 0 at the collapsed rest, 1 at the full detent. Written every frame by the controller; the
    /// content does **not** read this (reading it would re-render the content each frame).
    var progress: CGFloat = 0
    /// True once the sheet has lifted off the collapsed pill — the scroll page becomes interactive.
    var isExpanded: Bool = false
    /// True at (or within a hair of) the full detent — the state the page is allowed to scroll in.
    var isAtFull: Bool = false

    // MARK: Content → controller callbacks (wired by the host)

    /// The content's scroll view reached (or left) its top. A backup signal for the scroll→sheet
    /// hand-off; the controller prefers the live `contentOffset` of the discovered scroll view.
    var onScrollAtTop: (Bool) -> Void = { _ in }
    /// The search field gained focus (a tap) — open fully, with the keyboard.
    var requestFull: () -> Void = {}
    /// The grabber was tapped — peek to mid from the collapsed pill, otherwise collapse.
    var toggleFromGrabber: () -> Void = {}
    /// Collapse the sheet to the pill (used when an activity is opened from the list).
    var requestCollapse: () -> Void = {}
}
