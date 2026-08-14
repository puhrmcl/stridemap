import SwiftUI
import UIKit

extension Color {
    /// Perceived luminance in 0…1, resolved through UIColor so any Color (including brand
    /// tokens and user picks) can be judged. Used to keep type and contour lines legible on a
    /// user-chosen ground.
    var estimatedLuminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// True when the colour is dark enough that light ink reads better than dark ink over it.
    var isDarkGround: Bool { estimatedLuminance < 0.5 }
}
