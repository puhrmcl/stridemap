import SwiftUI

/// Visual language for Etch: calm, premium, minimal. Colours are tuned to sit
/// beautifully on top of both light and dark Apple Maps.
enum Theme {

    /// Official Etch brand palette (from the brand brief). Blue signals activity; Brass is
    /// reserved for achievement moments; Bone/Stone/Sage/Mist are the map-poster neutrals.
    enum Palette {
        static let ink = Color(red: 0.063, green: 0.094, blue: 0.125)   // #101820
        static let blue = Color(red: 0.078, green: 0.451, blue: 0.902)  // #1473E6
        static let bone = Color(red: 0.957, green: 0.945, blue: 0.918)  // #F4F1EA
        static let stone = Color(red: 0.847, green: 0.831, blue: 0.800) // #D8D4CC
        static let sage = Color(red: 0.733, green: 0.784, blue: 0.698)  // #BBC8B2
        static let mist = Color(red: 0.867, green: 0.902, blue: 0.918)  // #DDE6EA
        static let brass = Color(red: 0.690, green: 0.553, blue: 0.341) // #B08D57
    }

    /// Route colour palette. Routes render in the signature Etch Blue; the cooler tones remain
    /// for any age-graded rendering.
    enum Route {
        /// The signature Etch blue used for routes (matches the app accent).
        static let recent = Palette.blue
        static let warm = Color(red: 0.20, green: 0.53, blue: 0.93)
        static let mid = Color(red: 0.33, green: 0.52, blue: 0.82)
        static let old = Color(red: 0.42, green: 0.50, blue: 0.62)

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

    /// Primary/active accent — the official Etch Blue (#1473E6).
    static let accent = Palette.blue

    /// Reserved for achievement moments (PRs, milestones) — used sparingly.
    static let achievement = Palette.brass

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
