import SwiftUI
import SwiftData
import UIKit

/// Bridges the UIKit search-sheet motion shell into SwiftUI. It hosts `SearchSheetContent` inside a
/// `UIHostingController` that lives in a stable, full-height container moved by
/// `SearchSheetInteractionController`. The host itself is a full-screen, touch-transparent overlay:
/// only the sheet region receives touches, so the map and the floating controls beneath stay live.
struct SearchSheetHost: UIViewControllerRepresentable {
    /// Visible height at the full detent (the space above the top chrome).
    let maxHeight: CGFloat
    /// The screen's bottom safe-area inset (home indicator).
    var bottomSafeArea: CGFloat = 0
    /// Whether Reduce Motion is on — the settle uses a short, spring-free ease then.
    var reduceMotion: Bool = false
    /// The shared app model, injected into the hosted content's environment.
    let appModel: AppModel
    /// The SwiftData container, injected so the hosted content's `@Query`s resolve.
    let modelContainer: ModelContainer
    /// Publishes the sheet's live visible height to the chrome bridge (the totals pill + controls).
    let onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> SearchSheetContainerViewController {
        let model = context.coordinator.model
        let vc = SearchSheetContainerViewController(model: model, rootView: rootView(model: model))
        vc.maxHeight = maxHeight
        vc.bottomSafeArea = bottomSafeArea
        vc.controller.reduceMotion = reduceMotion
        vc.controller.onHeight = onHeight
        return vc
    }

    func updateUIViewController(_ vc: SearchSheetContainerViewController, context: Context) {
        vc.controller.reduceMotion = reduceMotion
        vc.controller.onHeight = onHeight
        vc.update(rootView: rootView(model: context.coordinator.model),
                  maxHeight: maxHeight, bottomSafeArea: bottomSafeArea)
    }

    private func rootView(model: SearchSheetModel) -> AnyView {
        AnyView(
            SearchSheetContent(model: model, bottomSafeArea: bottomSafeArea)
                .environment(appModel)
                .modelContainer(modelContainer)
        )
    }

    @MainActor
    final class Coordinator {
        /// Owned here so the model (and its wired callbacks) survive SwiftUI view updates.
        let model = SearchSheetModel()
    }
}

/// A view that is transparent to touches everywhere except the sheet's *visible* (masked) area, so
/// the map and floating controls stay interactive — including in the margins around the collapsed
/// floating pill, where the sheet's container extends but nothing is drawn.
final class PassthroughView: UIView {
    weak var sheetView: UIView?
    /// The visible masked rect, in the sheet's own coordinates.
    var visibleRect: () -> CGRect = { .zero }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let sheetView, !sheetView.isHidden, sheetView.alpha > 0.01 else { return nil }
        let local = sheetView.convert(point, from: self)
        guard visibleRect().contains(local) else { return nil }
        return sheetView.hitTest(local, with: event)
    }
}

/// The UIKit container: a passthrough root holding the transform-driven sheet (glass surface +
/// hosted SwiftUI content), with the pan gesture and interaction controller wired up.
@MainActor
final class SearchSheetContainerViewController: UIViewController {

    let model: SearchSheetModel
    let controller = SearchSheetInteractionController()

    private let hostingController: UIHostingController<AnyView>
    private let sheetView = UIView()
    private let surfaceView = UIView()
    private let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    var maxHeight: CGFloat = 0
    var bottomSafeArea: CGFloat = 0
    private var lastLaidOutBounds: CGRect = .zero

    init(model: SearchSheetModel, rootView: AnyView) {
        self.model = model
        self.hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = PassthroughView()
        root.sheetView = sheetView
        root.visibleRect = { [weak controller] in controller?.currentVisibleRect ?? .zero }
        root.backgroundColor = .clear
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sheetView.backgroundColor = .clear
        sheetView.layer.shadowColor = UIColor.black.cgColor
        sheetView.layer.shadowRadius = 18
        sheetView.layer.shadowOffset = CGSize(width: 0, height: 3)
        sheetView.layer.shadowOpacity = 0.14
        view.addSubview(sheetView)

        surfaceView.backgroundColor = .clear
        surfaceView.layer.mask = maskLayer
        sheetView.addSubview(surfaceView)

        effectView.isUserInteractionEnabled = false
        surfaceView.addSubview(effectView)

        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        surfaceView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.separator.withAlphaComponent(0.4).cgColor
        borderLayer.lineWidth = 0.75
        sheetView.layer.addSublayer(borderLayer)

        let pan = UIPanGestureRecognizer(
            target: controller,
            action: #selector(SearchSheetInteractionController.handlePan(_:))
        )
        pan.delegate = controller
        // Once this pan recognizes a drag it cancels the touch under the finger, so a downward swipe
        // that starts on a card / row / shortcut never activates it. Taps (no movement) still fire.
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        sheetView.addGestureRecognizer(pan)
        controller.sheetPan = pan

        controller.sheetView = sheetView
        controller.surfaceView = surfaceView
        controller.maskLayer = maskLayer
        controller.borderLayer = borderLayer
        controller.model = model
        controller.scrollViewProvider = { [weak self] in self?.findScrollView() }

        // Wire the content's callbacks to the interaction controller.
        model.requestFull = { [weak controller] in controller?.animate(to: .full) }
        model.requestCollapse = { [weak controller] in controller?.animate(to: .collapsed) }
        model.toggleFromGrabber = { [weak controller] in controller?.toggleFromGrabber() }
    }

    func update(rootView: AnyView, maxHeight: CGFloat, bottomSafeArea: CGFloat) {
        hostingController.rootView = rootView
        self.maxHeight = maxHeight
        self.bottomSafeArea = bottomSafeArea
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        guard maxHeight > 1 else { return }
        // Skip re-laying-out (which momentarily clears the transform) unless the bounds truly
        // changed — never mid-drag, where the bounds are stable.
        guard bounds != lastLaidOutBounds else {
            controller.configure(full: maxHeight, mid: max(260, maxHeight * 0.5),
                             collapsed: SearchSheetInteractionController.collapsedVisibleHeight)
            controller.attachScrollViewIfNeeded()
            return
        }
        lastLaidOutBounds = bounds

        let bleed = bottomSafeArea + 140
        let topAtFull = bounds.height - maxHeight
        // The glass surface extends `topBleed` above the content, so at the full detent it runs
        // behind the status bar to the physical top of the screen (Apple Maps' expanded search) —
        // the content itself stays below the safe area, and the collapsed pill is untouched.
        let topBleed = max(0, topAtFull)
        // Set the frame with the transform temporarily cleared, then let the controller reapply the
        // current translation via `configure`.
        sheetView.transform = .identity
        sheetView.frame = CGRect(x: 0, y: topAtFull, width: bounds.width, height: maxHeight + bleed)
        surfaceView.frame = CGRect(x: 0, y: -topBleed,
                                   width: bounds.width, height: sheetView.bounds.height + topBleed)
        effectView.frame = surfaceView.bounds
        hostingController.view.frame = CGRect(x: 0, y: topBleed,
                                              width: bounds.width, height: sheetView.bounds.height)
        maskLayer.frame = surfaceView.bounds
        borderLayer.frame = sheetView.bounds
        controller.topBleed = topBleed

        controller.configure(full: maxHeight, mid: max(260, maxHeight * 0.5),
                             collapsed: SearchSheetInteractionController.collapsedVisibleHeight)
        // Attach to the content scroll view's pan as soon as SwiftUI has built it, so the very first
        // content drag at full is handled (accidental-tap cancellation + immediate hand-off).
        controller.attachScrollViewIfNeeded()
    }

    /// Breadth-first search for the content's main vertical scroll view (the outer `ScrollView`;
    /// the horizontal carousels are descendants, so the outer one is found first).
    private func findScrollView() -> UIScrollView? {
        var queue: [UIView] = [hostingController.view]
        while !queue.isEmpty {
            let v = queue.removeFirst()
            if let sv = v as? UIScrollView { return sv }
            queue.append(contentsOf: v.subviews)
        }
        return nil
    }
}
