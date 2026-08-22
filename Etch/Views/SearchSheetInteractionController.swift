import UIKit

/// Owns the *physical* motion of the docked search sheet.
///
/// A single `UIPanGestureRecognizer` drives a vertical `transform` on a stable-height container
/// (no SwiftUI layout runs while the finger moves); a `CADisplayLink`-driven damped spring settles
/// it to velocity-aware detents and is fully interruptible (grabbing mid-settle continues from the
/// live position with no jump); and it coordinates the hand-off with the content's scroll view at
/// the top of the full page by reading/pinning `contentOffset` directly.
///
/// Per frame it only: sets one transform, updates one mask path + a couple of layer properties, and
/// publishes the resulting height to the chrome. It never touches the map or rebuilds SwiftUI.
@MainActor
final class SearchSheetInteractionController: NSObject {

    enum Detent: Int { case collapsed, mid, full }

    // MARK: Wiring (set by the host)

    /// The moving container (the transform target).
    weak var sheetView: UIView?
    /// The glass surface whose mask (inset + top-corner radius) morphs with progress.
    weak var surfaceView: UIView?
    /// The mask applied to `surfaceView`.
    weak var maskLayer: CAShapeLayer?
    /// A hairline that strokes the same outline as the mask, for edge definition.
    weak var borderLayer: CAShapeLayer?
    /// Finds the content's main vertical scroll view (searched lazily, then cached).
    var scrollViewProvider: () -> UIScrollView? = { nil }
    /// Publishes the current visible height (collapsed…full) to the chrome bridge each frame.
    var onHeight: (CGFloat) -> Void = { _ in }
    /// The presentation model the SwiftUI content reads (discrete flags only).
    var model: SearchSheetModel?

    var reduceMotion = false

    // MARK: Geometry (translation space; 0 = full, positive = translated down)

    private var full: CGFloat = 0          // visible height at the full detent
    private var mid: CGFloat = 0
    private var collapsedHeight: CGFloat = 62

    private var maxTranslation: CGFloat { max(0, full - collapsedHeight) }   // collapsed
    private func translation(for detent: Detent) -> CGFloat {
        switch detent {
        case .full:      return 0
        case .mid:       return max(0, full - mid)
        case .collapsed: return maxTranslation
        }
    }
    private var detentTranslations: [(Detent, CGFloat)] {
        [(.full, 0), (.mid, translation(for: .mid)), (.collapsed, maxTranslation)]
    }

    // MARK: State

    private(set) var currentDetent: Detent = .collapsed
    /// True between a pan's `.began` and its end, so a layout pass never resets the transform while
    /// the finger is down.
    private(set) var isPanning = false
    private var currentTranslation: CGFloat = 0
    private var panStartTranslation: CGFloat = 0
    private var panStartDetent: Detent = .collapsed
    /// Per-gesture ownership: nil = undecided, true = the sheet owns it, false = the scroll owns it.
    private var sheetOwnsPan: Bool?
    private var cachedScrollView: UIScrollView?

    // Spring settling.
    private var displayLink: CADisplayLink?
    private var springVelocity: CGFloat = 0
    private var springTarget: CGFloat = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var reduceMotionElapsed: CGFloat = 0
    private var reduceMotionStart: CGFloat = 0

    private let haptics = UIImpactFeedbackGenerator(style: .soft)

    private func scrollView() -> UIScrollView? {
        if let cachedScrollView { return cachedScrollView }
        cachedScrollView = scrollViewProvider()
        return cachedScrollView
    }

    // MARK: Configuration

    /// Sets the detent geometry. On first configuration the sheet is placed at the collapsed pill.
    func configure(full: CGFloat, mid: CGFloat, collapsed: CGFloat) {
        let first = self.full == 0
        self.full = full
        self.mid = mid
        self.collapsedHeight = collapsed
        if first {
            currentDetent = .collapsed
            currentTranslation = maxTranslation
            applyPresentation(currentTranslation)
        } else if displayLink == nil && !isPanning {
            // Re-settle at the current detent after a bounds change (e.g. rotation), but never while
            // a finger is down or a spring is running — that would fight the live interaction.
            currentTranslation = translation(for: currentDetent)
            applyPresentation(currentTranslation)
        }
    }

    // MARK: Pan

    @objc func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let sheetView, let container = sheetView.superview else { return }
        switch gr.state {
        case .began:
            stopSpring()
            isPanning = true
            // Interruption: adopt the live presentation position as the new origin — no jump.
            currentTranslation = livePresentationTranslation()
            sheetView.transform = CGAffineTransform(translationX: 0, y: currentTranslation)
            panStartTranslation = currentTranslation
            panStartDetent = currentDetent
            sheetOwnsPan = nil
            model?.isExpanded = (full - currentTranslation) > collapsedHeight + 24

        case .changed:
            let t = gr.translation(in: container)

            // Decide ownership on the first meaningful movement.
            if sheetOwnsPan == nil {
                // Ignore horizontal-dominant gestures so the Studio/Achievements carousels swipe
                // without dragging the sheet.
                if abs(t.x) > abs(t.y) + 2 { return }
                if abs(t.y) < 1 { return }
                sheetOwnsPan = decideOwnership(downward: t.y > 0)
            }

            if sheetOwnsPan == false {
                // The scroll view owns this gesture. Keep the sheet still and rebase, so if the user
                // scrolls back to the top and keeps pulling down, we take over from here.
                if let sv = scrollView(), sv.contentOffset.y <= 0, t.y > 0 {
                    sheetOwnsPan = true
                    gr.setTranslation(.zero, in: container)
                    panStartTranslation = currentTranslation
                } else {
                    return
                }
            }

            // The sheet owns the gesture: pin the scroll to its top so it can't scroll under us
            // (it stays simultaneously recognized), then move the sheet with the finger.
            if let sv = scrollView(), sv.contentOffset.y > 0 { sv.contentOffset.y = 0 }
            let proposed = panStartTranslation + t.y
            applyPresentation(rubberBanded(proposed))

        case .ended, .cancelled, .failed:
            defer { sheetOwnsPan = nil; isPanning = false }
            guard sheetOwnsPan == true else { return }
            let velocity = gr.velocity(in: container).y
            settle(to: targetDetent(for: velocity), velocity: velocity)

        default:
            break
        }
    }

    /// At the start of a drag, decide whether the sheet or the scroll view should own it.
    private func decideOwnership(downward: Bool) -> Bool {
        // Below full, the sheet always owns (the scroll view is parked and disabled there).
        guard currentDetent == .full else { return true }
        guard let sv = scrollView() else { return downward }   // no scroll view found: sheet owns
        // At full: a downward pull from the very top collapses the sheet; anything else scrolls.
        return sv.contentOffset.y <= 0 && downward
    }

    /// Nonlinear resistance past the collapsed/full limits, iOS-style, so the edges feel soft.
    private func rubberBanded(_ t: CGFloat) -> CGFloat {
        let lower: CGFloat = 0
        let upper = maxTranslation
        if t < lower { return -resist(lower - t) }
        if t > upper { return upper + resist(t - upper) }
        return t
    }
    private func resist(_ x: CGFloat) -> CGFloat {
        let dim: CGFloat = 120
        return (1 - 1 / (x / dim * 0.55 + 1)) * dim
    }

    // MARK: Detent selection

    private func targetDetent(for velocity: CGFloat) -> Detent {
        let strong: CGFloat = 900   // pts/sec — a decisive flick
        if velocity < -strong { return neighbour(of: currentClosestDetent(), up: true) }
        if velocity >  strong {
            let target = neighbour(of: currentClosestDetent(), up: false)
            return target
        }
        // Otherwise snap to the nearest detent to a lightly projected end position.
        let projected = currentTranslation + velocity * 0.12
        let nearest = detentTranslations.min { abs($0.1 - projected) < abs($1.1 - projected) }
        var target = nearest?.0 ?? .collapsed
        // A swipe up from the collapsed pill only *peeks* to mid — a tap is what opens fully.
        if panStartDetent == .collapsed, target == .full { target = .mid }
        return target
    }

    /// The detent whose translation is closest to where the sheet currently sits.
    private func currentClosestDetent() -> Detent {
        (detentTranslations.min { abs($0.1 - currentTranslation) < abs($1.1 - currentTranslation) }?.0) ?? currentDetent
    }

    private func neighbour(of detent: Detent, up: Bool) -> Detent {
        // "up" = physically higher / larger sheet = a smaller translation.
        switch (detent, up) {
        case (.collapsed, true):  return .mid
        case (.mid, true):        return .full
        case (.full, false):      return .mid
        case (.mid, false):       return .collapsed
        default:                  return detent
        }
    }

    // MARK: Programmatic moves (search field focus, grabber tap, open)

    func animate(to detent: Detent) {
        stopSpring()
        currentTranslation = livePresentationTranslation()
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

        // Scroll enablement is deterministic and synchronous: only the full page scrolls, and it
        // always resets to the top when leaving full so a re-open shows the Explore shortcuts.
        if let sv = scrollView() {
            if detent != .full { sv.setContentOffset(.zero, animated: false) }
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
        let dt = min(CGFloat(now - lastTimestamp), 1.0 / 30)   // clamp to survive stalls
        lastTimestamp = now
        guard dt > 0 else { return }

        if reduceMotion {
            // A short, spring-free ease for accessibility.
            reduceMotionElapsed += dt
            let p = min(1, reduceMotionElapsed / 0.18)
            let inv = 1 - p
            let eased = 1 - inv * inv   // easeOut
            let value = reduceMotionStart + (springTarget - reduceMotionStart) * eased
            applyPresentation(value)
            if p >= 1 { applyPresentation(springTarget); stopSpring() }
            return
        }

        // Critically-ish damped spring toward the target.
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

    private func livePresentationTranslation() -> CGFloat {
        // The settle spring sets the transform directly every display-link tick (no implicit
        // Core Animation), so `currentTranslation` is always exactly the on-screen position. A grab
        // mid-settle therefore continues from precisely where the sheet is, with no jump.
        currentTranslation
    }

    /// Applies one translation: sets the transform, morphs the surface mask, and publishes height.
    private func applyPresentation(_ t: CGFloat) {
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

    /// The glass surface's mask: a top-rounded rectangle inset horizontally, both eased by progress
    /// — a slightly inset docked bar at the collapsed rest, edge-to-edge at full. The bottom runs
    /// off-screen (the container extends past the bottom edge), so only the top corners ever show.
    private func updateSurface(progress: CGFloat) {
        guard let surfaceView, let maskLayer else { return }
        let inset = 14 * (1 - progress)                       // 14 → 0
        let radius = 26 * (1 - progress) + 20 * progress      // 26 → 20
        let rect = surfaceView.bounds.insetBy(dx: inset, dy: 0)
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        maskLayer.path = path.cgPath
        borderLayer?.path = path.cgPath

        // Keep the resting shadow cheap and correct at rest; drop it while actively moving so it
        // isn't re-blurred over the live map every frame.
        if let container = sheetView {
            if displayLink == nil {
                container.layer.shadowPath = path.cgPath
                container.layer.shadowOpacity = 0.14
            } else {
                container.layer.shadowOpacity = 0
            }
        }
    }
}

// MARK: - Gesture coordination

extension SearchSheetInteractionController: UIGestureRecognizerDelegate {
    /// Recognize simultaneously with the content's scroll views (vertical page + horizontal
    /// carousels), so buttons, scrolling, and the sheet pan all coexist; ownership is arbitrated in
    /// `handlePan` by reading the scroll offset and the gesture direction.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
