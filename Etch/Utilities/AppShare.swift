import UIKit

/// Presents the system share sheet with a mix of item types (e.g. a text summary *and* an image),
/// which `ShareLink` can't do in a single share. Presented over whatever is currently on screen.
enum AppShare {

    @MainActor
    static func present(_ items: [Any]) {
        guard !items.isEmpty else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.keyWindow ?? scene?.windows.first,
              var top = window.rootViewController else { return }
        // Present from the topmost view controller so it appears over any sheet already up.
        while let presented = top.presentedViewController { top = presented }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a popover anchor; centre it so it never crashes.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }
}
