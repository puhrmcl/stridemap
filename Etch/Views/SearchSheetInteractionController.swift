import UIKit

/// Owns the *physical* motion and the gesture arbitration of the docked search sheet.
///
/// Two recognizers cooperate:
/// - a container `UIPanGestureRecognizer` (`handlePan`) owns drags that start on the header/grabber,
///   and any drag while the page can't scroll (below the full detent). It has
///   `cancelsTouchesInView = true`, so the moment it recognizes a drag it cancels the child button
///   under the finger — a downward swipe never activates a card, row, or shortcut.
/// - the content scroll view's *own* pan (observed via an added target, `handleScrollPan`) owns
///   drags inside the scrolling page at full. Because the drive comes from the scroll view's pan,
///   we inherit its content-touch cancellation (accidental taps can't fire) and its immediate
///   recognition (no separate threshold, no bounce-first), and at the very top a downward drag is
///   handed to the sheet instantly by pinning `contentOffset` and translating.
///
/// A `CADisplayLink` damped spring settles to velocity-aware *adjacent* detents and is fully
/// interruptible. Per frame the drive path only sets one transform + a mask path and publishes the
/// height to the chrome — it never touches the map or rebuilds SwiftUI.
@MainActor
final class SearchSheetInteractionController: NSObject {

    enum Detent: Int { case collapsed, mid, full }

    // MARK: Pill geometry (Apple-Maps-style floating search bar at the collapsed rest)

    /// How far the collapsed pill sits in from the screen's side edges — and, matching Apple Maps,
    /// the same distance it floats above the physical bottom edge.
    static let pillInset: CGFloat = 20
    /// The collapsed pill's own height (grabber + search row).
    static let pillHeight: CGFloat = 64
    /// Corner radius of the floating pill at rest. A full capsule for the pill's height, so the
    /// anchored bar reads as a rounded pill rather than a soft-cornered slab.
    static let pillRadius: CGFloat = pillHeight / 2
    /// The sheet's collapsed *visible* height: the pill plus the gap it floats above the bottom.
    static var collapsedVisibleHeight: CGFloat { pillHeight + pillInset }

    // MARK: Wiring (set by the host)

    weak var sheetView: UIView?
    weak var surfaceView: UIView?
    weak var maskLayer: CAShapeLayer?
    weak var borderLayer: CAShapeLayer?
    weak var sheetPan: UIPanGestureRecognizer?
    var scrollViewProvider: () -> UIScrollView? = { nil }
    var onHeight: (CGFloat) -> Void = { _ in }
    var model: SearchSheetModel?
    var reduceMotion = false

    // MARK: Geometry (translation space; 0 = full, positive = translated down)

    private var full: CGFloat = 0
    private var mid: CGFloat = 0
    private var collapsedHeight: CGFloat = 62

    private var maxTranslation: CGFloat { max(0, full - collapsedHeight) }
    private func translation(for detent: Detent) -> CGFloat {
        switch detent {
        case .full:      return 0
        case .mid:       return max(0, full - mid)
        case .collapsed: return maxTranslation
        }
    }

    // MARK: State

    private(set) var currentDetent: Detent = .collapsed
    private(set) var isPanning = false
    /// The currently *visible* (masked) area of the sheet, in the sheet's own coordinates. Touches
    /// outside it — the map showing around the floating pill — must pass straight through.
    private(set) var currentVisibleRect: CGRect = .zero
    private var currentTranslation: CGFloat = 0

    private var dragStartTranslation: CGFloat = 0
    private var dragStartDetent: Detent = .collapsed

    /// The content scroll gesture is currently driving the sheet (a downward pull from the top).
    private var scrollTakeover = false
    private var scrollTakeoverStart: CGFloat = 0

    private var cachedScrollView: UIScrollView?
    private var didAttachScrollPan = false

    // Spring settling.
    private var displayLink: CADisplayLink?
    private var springVelocity: CGFloat = 0
    private var springTarget: CGFloat = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var reduceMotionElapsed: CGFloat = 0
    private var reduceMotionStart: CGFloat = 0

    private let haptics = UIImpactFeedbackGenerator(style: .soft)

    /// The scroll view's true top offset (accounts for any adjusted content inset).
    private func topOffset(_ sv: UIScrollView) -> CGFloat { -sv.adjustedContentInset.top }

    /// Finds the content's main vertical scroll view and, once, adds ourselves as a target on its
    /// pan so a content drag can drive the sheet directly.
    @discardableResult
    func attachScrollViewIfNeeded() -> UIScrollView? {
        if let cachedScrollView { return cachedScrollView }
        guard let sv = scrollViewProvider() else { return nil }
        cachedScrollView = sv
        if !didAttachScrollPan {
            didAttachScrollPan = true
            sv.panGestureRecognizer.addTarget(self, action: #selector(handleScrollPan(_:)))
        }
        return sv
    }
    private func scrollView() -> UIScrollView? { attachScrollViewIfNeeded() }

    // MARK: Configuration

    func configure(full: CGFloat, mid: CGFloat, collapsed: CGFloat) {
        let first = self.full == 0
        self.full = full
        self.mid = mid
        self.collapsedHeight = collapsed
        if first {
            currentDetent = .collapsed
            currentTranslation = maxTranslation
            applyPresentation(currentTranslation)
        } else if displayLink == nil && !isPanning && !scrollTakeover {
            currentTranslation = translation(for: currentDetent)
            applyPresentation(currentTranslation)
        }
    }

    // MARK: Drag lifecycle (shared by both recognizers)

    private func beginDrag() {
        stopSpring()
        isPanning = true
        dragStartTranslation = currentTranslation
        dragStartDetent = currentDetent
        // A sheet drag dismisses the keyboard as part of the same gesture (no double-swipe).
        sheetView?.endEditing(true)
    }

    private func updateDrag(translationY: CGFloat) {
        applyPresentation(rubberBanded(dragStartTranslation + translationY))
    }

    private func endDrag(velocity: CGFloat) {
        isPanning = false
        settle(to: targetDetent(from: dragStartDetent, velocity: velocity), velocity: velocity)
    }

    // MARK: Container pan (header / grabber / below-full)

    @objc func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let container = sheetView?.superview else { return }
        switch gr.state {
        case .began:
            beginDrag()
        case .changed:
            updateDrag(translationY: gr.translation(in: container).y)
        case .ended, .cancelled, .failed:
            endDrag(velocity: gr.velocity(in: container).y)
        default:
            break
        }
    }

    // MARK: Content scroll pan (full page)

    @objc func handleScrollPan(_ gr: UIPanGestureRecognizer) {
        guard let sv = scrollView(), let container = sheetView?.superview else { return }
        switch gr.state {
        case .began:
            scrollTakeover = false

        case .changed:
            let t = gr.translation(in: container)
            if scrollTakeover {
                sv.contentOffset.y = topOffset(sv)                 // pin to the top as the sheet moves
                updateDrag(translationY: t.y - scrollTakeoverStart)
            } else if currentDetent == .full,
                      sv.contentOffset.y <= topOffset(sv) + 0.5,    // at (or above) the top
                      t.y > 0,                                      // pulling down
                      abs(t.y) > abs(t.x) {                         // vertical-dominant
                // Hand the gesture to the sheet immediately, from this pixel.
                scrollTakeover = true
                scrollTakeoverStart = t.y
                sv.contentOffset.y = topOffset(sv)
                beginDrag()
            }
            // Otherwise the scroll view scrolls normally.

        case .ended, .cancelled, .failed:
            if scrollTakeover {
                scrollTakeover = false
                endDrag(velocity: gr.velocity(in: container).y)
            }

        default:
            break
        }
    }

    // MARK: Rubber-banding

    private func rubberBanded(_ t: CGFloat) -> CGFloat {
        let lower: CGFloat = 0
        let upper = maxTranslation
        // Above full the ceiling is tight: the full detent already sits a standard-sheet gap
        // (~59–69pt) below the screen top, so the old 120pt allowance let a hard fling carry the
        // whole page off the top of the screen. 28pt reads as resistance and always stays on-screen.
        if t < lower { return -resist(lower - t, dim: 28) }
        if t > upper { return upper + resist(t - upper, dim: 120) }
        return t
    }
    private func resist(_ x: CGFloat, dim: CGFloat) -> CGFloat {
        (1 - 1 / (x / dim * 0.55 + 1)) * dim
    }

    // MARK: Detent selection (forgiving, adjacent-only)

    /// From the detent the drag began at, pick where to settle. A modest downward/upward flick
    /// (≥ ~600 pt/s) advances one detent in that direction; otherwise a slow drag commits to the
    /// next detent once it has travelled ~20% of the way there. Never more than one detent from the
    /// start, so noise can't cause a full→collapsed jump.
    private func targetDetent(from start: Detent, velocity: CGFloat) -> Detent {
        let flick: CGFloat = 600
        if velocity < -flick { return neighbour(of: start, up: true) }
        if velocity >  flick { return neighbour(of: start, up: false) }

        let startT = translation(for: start)
        let moved = currentTranslation - startT      // positive = moved down (toward collapse)
        let commit: CGFloat = 0.2

        let downT = translation(for: neighbour(of: start, up: false))
        let upT = translation(for: neighbour(of: start, up: true))
        if downT > startT, moved > (downT - startT) * commit { return neighbour(of: start, up: false) }
        if upT < startT, moved < (upT - startT) * commit { return neighbour(of: start, up: true) }
        return start
    }

    private func neighbour(of detent: Detent, up: Bool) -> Detent {
        switch (detent, up) {
        case (.collapsed, true):  return .mid
        case (.mid, true):        return .full
        case (.full, false):      return .mid
        case (.mid, false):       return .collapsed
        default:                  return detent
        }
    }

    // MARK: Programmatic moves

    func animate(to detent: Detent) {
        stopSpring()
        settle(to: detent, velocity: 0)
    }

    func toggleFromGrabber() {
        animate(to: currentDetent == .collapsed ? .mid : .collapsed)
    }

    // MARK: Settling (interruptible spring on a display link)

    private func settle(to detent: Detent, velocity: CGFloat) {
        let changed = detent != currentDetent
        currentDetent = detent
        springTarget = translation(for: detent)

        // Only the full page scrolls; it resets to the top when leaving full so a re-open shows the
        // Explore shortcuts.
        if let sv = scrollView() {
            if detent != .full { sv.setContentOffset(CGPoint(x: 0, y: topOffset(sv)), animated: false) }
            sv.isScrollEnabled = (detent == .full)
        }

        if changed { haptics.impactOccurred(intensity: 0.6) }

        springVelocity = velocity
        reduceMotionStart = currentTranslation
        reduceMotionElapsed = 0
        startSpring()
    }

    private func startSpring() {
        stopSpring()
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopSpring() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        if lastTimestamp == 0 { lastTimestamp = now }
        let dt = min(CGFloat(now - lastTimestamp), 1.0 / 30)
        lastTimestamp = now
        guard dt > 0 else { return }

        if reduceMotion {
            reduceMotionElapsed += dt
            let p = min(1, reduceMotionElapsed / 0.18)
            let inv = 1 - p
            let eased = 1 - inv * inv
            let value = reduceMotionStart + (springTarget - reduceMotionStart) * eased
            applyPresentation(value)
            if p >= 1 { applyPresentation(springTarget); stopSpring() }
            return
        }

        let stiffness: CGFloat = 200
        let damping: CGFloat = 26
        let force = -stiffness * (currentTranslation - springTarget)
        let damper = -damping * springVelocity
        springVelocity += (force + damper) * dt
        let next = currentTranslation + springVelocity * dt
        applyPresentation(next)

        if abs(next - springTarget) < 0.4 && abs(springVelocity) < 0.4 {
            applyPresentation(springTarget)
            springVelocity = 0
            stopSpring()
        }
    }

    // MARK: Presentation

    private func applyPresentation(_ t: CGFloat) {
        // Absolute bounds, regardless of which gesture/spring/layout path produced the value:
        // the sheet can never sit more than 40pt above its full detent (which itself sits just
        // below the status bar), and never fully below the screen. Belt for every braces.
        let t = max(-40, min(t, maxTranslation + 160))
        currentTranslation = t
        sheetView?.transform = CGAffineTransform(translationX: 0, y: t)

        let visible = max(collapsedHeight, full - t)
        let progress = full > collapsedHeight
            ? max(0, min(1, (visible - collapsedHeight) / (full - collapsedHeight)))
            : 0
        updateSurface(progress: progress)

        if let model {
            model.progress = progress
            let expanded = visible > collapsedHeight + 24
            if model.isExpanded != expanded { model.isExpanded = expanded }
            let atFull = t <= 1
            if model.isAtFull != atFull { model.isAtFull = atFull }
        }
        onHeight(visible)
    }

    /// Morphs the glass surface between an Apple-Maps-style *floating pill* at the collapsed rest
    /// and a full bottom page:
    /// - horizontally, inset from the screen edges at rest, edge-to-edge at full;
    /// - vertically, the pill's bottom floats the same distance off the physical bottom edge as off
    ///   the sides (so the map shows all the way around it), while the full page runs past the
    ///   bottom edge into the bleed so no map ever shows beneath it;
    /// - all four corners rounded as a pill, the bottom corners squaring off as it reaches full.
    ///
    /// This is one `CGPath` rebuilt per frame on a masked layer — no SwiftUI layout is involved.
    private func updateSurface(progress: CGFloat) {
        guard let surfaceView, let maskLayer, full > 0 else { return }
        let bounds = surfaceView.bounds

        let inset = Self.pillInset * (1 - progress)
        // The physical bottom edge, expressed in the (translated) sheet's own coordinates.
        let screenBottom = full - currentTranslation
        // At rest the pill floats `inset` above that edge; it never shrinks below its own height, so
        // an over-drag slides it off the bottom rather than squashing the search row.
        let floatingBottom = max(Self.pillHeight, screenBottom - inset)
        let bottomY = floatingBottom + (bounds.height - floatingBottom) * progress

        let rect = CGRect(
            x: bounds.minX + inset,
            y: bounds.minY,
            width: max(0, bounds.width - inset * 2),
            height: max(0, bottomY - bounds.minY)
        )
        let topRadius = Self.pillRadius * (1 - progress) + 20 * progress
        let bottomRadius = Self.pillRadius * (1 - progress)
        let path = Self.roundedPath(rect: rect, topRadius: topRadius, bottomRadius: bottomRadius)

        maskLayer.path = path
        borderLayer?.path = path
        currentVisibleRect = rect

        if let container = sheetView {
            if displayLink == nil && !isPanning && !scrollTakeover {
                container.layer.shadowPath = path
                container.layer.shadowOpacity = 0.14
            } else {
                container.layer.shadowOpacity = 0
            }
        }
    }

    /// A rounded rectangle with independent top and bottom corner radii.
    private static func roundedPath(rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let limit = min(rect.width, rect.height) / 2
        let tr = max(0, min(topRadius, limit))
        let br = max(0, min(bottomRadius, limit))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + tr, y: rect.minY), radius: tr)
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + tr), radius: tr)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - br, y: rect.maxY), radius: br)
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - br), radius: br)
        path.closeSubpath()
        return path
    }
}

// MARK: - Gesture coordination

extension SearchSheetInteractionController: UIGestureRecognizerDelegate {
    /// The container pan owns a drag only where the sheet should move: on the header/grabber (any
    /// detent), and anywhere while the page can't scroll (below full). At full, a drag that starts
    /// inside the scrolling content is left to the scroll view's pan (handled by `handleScrollPan`).
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let sheetView,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let point = pan.location(in: sheetView)
        let hit = sheetView.hitTest(point, with: nil)
        if isInsideScrollView(hit) {
            // Content area: the container pan owns it only when the page can't scroll (below full).
            return !(scrollView()?.isScrollEnabled ?? false)
        }
        return true   // header / grabber / non-scroll region → the container pan owns it
    }

    /// Let the container pan and the content scroll pan recognize together where they overlap.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func isInsideScrollView(_ view: UIView?) -> Bool {
        guard let target = scrollView() else { return false }
        var v = view
        while let current = v {
            if current === target { return true }
            v = current.superview
        }
        return false
    }
}
