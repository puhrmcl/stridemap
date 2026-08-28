import SwiftUI
import UIKit

/// How much room the floating tab bar takes at the foot of the screen.
///
/// The bar is a capsule that hovers over the content rather than a bar the content sits on top
/// of, and anything the app docks to the bottom itself — the Map Type sheet, the Activity Type
/// and Activity View sheets — has to clear it deliberately.
///
/// Those sheets cannot simply respect the safe area, which is the answer that ought to work.
/// They are overlays on `HomeView`, whose whole body ignores the safe area so the map can run
/// under the status bar and the home indicator; an overlay inherits that, so there is no inset
/// left to read by the time the sheet is laid out. Ignoring the safe area is right for the map
/// and wrong for a card of controls, and this is the seam between the two.
///
/// So the clearance is stated rather than inherited: the bar's own height and the gap it floats
/// in, added to the window's real bottom inset, which is the part that genuinely varies between
/// a device with a home indicator and one without.
enum FloatingTabBarMetrics {

    /// The capsule's height plus the gap beneath it. Measured against the iOS 26 bar; it is a
    /// layout constant of the system's chrome, not a design choice of ours, which is why it is
    /// written down once here instead of being re-guessed at each call site.
    static let barClearance: CGFloat = 62

    /// The window's own bottom inset — the home indicator, or zero on a device without one.
    static var windowBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    /// What a bottom-docked card must leave below its content so nothing hides behind the bar.
    static var contentClearance: CGFloat { barClearance + windowBottomInset }
}

/// A card docked to the bottom of the screen: its material reaches the physical edge, while its
/// content stops above the floating tab bar.
///
/// Both halves matter. A card that stopped its background at the bar would leave a band of map
/// showing beneath it and read as a floating panel rather than a sheet; a card that ran its
/// *content* to the edge puts a toggle underneath the tab bar, which is what happened to "Show
/// start pins".
struct BottomDockedCard: ViewModifier {
    var cornerRadius: CGFloat = 38

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius,
                               topTrailingRadius: cornerRadius,
                               style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, FloatingTabBarMetrics.contentClearance)
            .frame(maxWidth: .infinity)
            .background {
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.strokeBorder(.separator.opacity(0.3), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 20, y: -2)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
    }
}

extension View {
    /// Docks this content as a bottom sheet card that clears the floating tab bar.
    func bottomDockedCard(cornerRadius: CGFloat = 38) -> some View {
        modifier(BottomDockedCard(cornerRadius: cornerRadius))
    }
}
