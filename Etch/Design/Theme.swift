import SwiftUI

/// Visual language for Etch: calm, premium, minimal. Colours are tuned to sit
/// beautifully on top of both light and dark Apple Maps.
enum Theme {

    /// Route colour palette — a warm-to-cool gradient keyed off recency.
    /// Recent runs use the vivid "ember" tones; older runs cool toward slate.
    enum Route {
        /// The signature Strava-adjacent ember used for the freshest routes.
        static let recent = Color(red: 1.0, green: 0.357, blue: 0.169)
        static let warm = Color(red: 0.98, green: 0.55, blue: 0.30)
        static let mid = Color(red: 0.42, green: 0.62, blue: 0.90)
        static let old = Color(red: 0.45, green: 0.52, blue: 0.62)

        /// Interpolates a route colour based on age. `t` runs 0 (today) → 1 (oldest).
        static func color(forAgeFraction t: Double) -> Color {
            let clamped = min(max(t, 0), 1)
            if clamped < 0.5 {
                return blend(recent, warm, clamped / 0.5)
            } else {
                let inner = (clamped - 0.5) / 0.5
                return blend(mid, old, inner)
            }
        }

        private static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
            let ca = a.rgba, cb = b.rgba
            return Color(
                red: ca.r + (cb.r - ca.r) * t,
                green: ca.g + (cb.g - ca.g) * t,
                blue: ca.b + (cb.b - ca.b) * t
            )
        }
    }

    static let accent = Color(red: 1.0, green: 0.357, blue: 0.169)

    /// Corner radius used for floating glass controls.
    static let controlRadius: CGFloat = 22
    static let cardRadius: CGFloat = 28

    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    static let gentle = Animation.easeInOut(duration: 0.35)
}

extension Color {
    var rgba: (r: Double, g: Double, b: Double, a: Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #else
        return (0, 0, 0, 1)
        #endif
    }
}
