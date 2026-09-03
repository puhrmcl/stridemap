import SwiftUI
import UIKit

/// Calm, spare, one typeface. Every colour is defined once for light and once
/// for dark so the app reads the same in either.
enum Theme {
    // Surfaces and ink
    static let background = adaptive(light: 0xF7F6F2, dark: 0x111311)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B1D1A)
    static let ink = adaptive(light: 0x1E211D, dark: 0xECEEE9)
    static let inkSoft = adaptive(light: 0x6C7268, dark: 0x969C91)
    static let hairline = adaptive(light: 0xE3E1D9, dark: 0x2B2E2A)
    static let accent = adaptive(light: 0x5F7B62, dark: 0x8FAC90)

    // Day marks. Never alarm red, never a shame colour.
    /// none — deepest quiet, muted sage
    static let quietMark = adaptive(light: 0x5F7B62, dark: 0x6E8C70)
    /// low — still quiet, lighter sage
    static let lowMark = adaptive(light: 0xA6C0A2, dark: 0x8CA889)
    /// mid — warm sand
    static let midMark = adaptive(light: 0xD9BF8C, dark: 0xC0A26C)
    /// high — muted clay
    static let highMark = adaptive(light: 0xBC8770, dark: 0xB07A64)
    /// A day that person did not log
    static let emptyMark = adaptive(light: 0xEBE9E1, dark: 0x242723)

    // Layout
    static let gutter: CGFloat = 24
    static let corner: CGFloat = 20

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension Bucket {
    var color: Color {
        switch self {
        case .none: return Theme.quietMark
        case .low: return Theme.lowMark
        case .mid: return Theme.midMark
        case .high: return Theme.highMark
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255
        let green = CGFloat((rgb >> 8) & 0xFF) / 255
        let blue = CGFloat(rgb & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
