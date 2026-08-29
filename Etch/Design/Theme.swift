import SwiftUI
import UIKit

/// Etch's colour system.
///
/// Three layers, and code should reach for the lowest one it can:
///
///   1. `Theme.Brand` — the six brand constants and the handful of tones derived from them.
///      These are the only literal colours in the app. Nothing else may define a hex.
///   2. `Theme.Surface` / `.Ink` / `.Line` / `.accent` — the semantic tokens the interface is
///      built from. Every one resolves per appearance, so a view written against them is
///      correct in light and dark without a single `colorScheme` check.
///   3. `Theme.Artwork` — the poster palette. Deliberately separate: a print is a product with
///      its own paper and ink, not a piece of interface chrome, and it does not follow the UI
///      into dark mode.
///
/// Colour balance follows the brand: warm neutrals carry the surface area, Etch Ink carries the
/// type and the few solid dark elements, and Etch Blue appears only where something is live —
/// selection, focus, the route itself. Blue is an accent, never a ground.
enum Theme {

    // MARK: - Layer 1: brand constants

    /// The Etch Brand System palette, plus the tones derived from it that a two-appearance
    /// interface needs. Nothing here is arbitrary — each derived value states what it is for.
    enum Brand {
        /// #17212B — primary brand colour: logo, headings, dark UI.
        static let ink = Color(hex: 0x17212B)
        /// #4A8EAE — signature accent. Interaction and focus, used sparingly.
        static let blue = Color(hex: 0x4A8EAE)
        /// #F3F0E9 — primary light background.
        static let canvas = Color(hex: 0xF3F0E9)
        /// #FBFAF7 — cards, surfaces, print grounds, elevated moments.
        static let galleryWhite = Color(hex: 0xFBFAF7)
        /// #4A5055 — secondary text, icons, subtle UI elements.
        static let graphite = Color(hex: 0x4A5055)
        /// #C9CDCE — dividers, inactive states, borders, map UI.
        static let mist = Color(hex: 0xC9CDCE)

        // Derived tones. Each exists because a semantic token below needs it and the six
        // brand colours alone cannot express it.

        /// Ink taken a step deeper, so an Ink card can sit *on* something in dark mode and
        /// still read as raised. Dark mode's ground.
        static let inkDeep = Color(hex: 0x10181F)
        /// Deeper still — wells, fields and inset areas on a dark ground.
        static let inkWell = Color(hex: 0x0B1116)
        /// Canvas taken a step down, for the same job in light mode.
        static let canvasSunken = Color(hex: 0xE9E5DB)
        /// Etch Blue lifted for dark grounds. #4A8EAE on Etch Ink is 4.48:1 — a hair under AA
        /// for body text — so dark mode uses this instead and clears 6.8:1.
        static let blueLift = Color(hex: 0x6FB2D1)
        /// Etch Blue lifted further, for blue text on a dark ground.
        static let blueLiftText = Color(hex: 0x8AC3DE)
        /// Etch Blue deepened just enough that a Gallery White label on a solid blue button
        /// clears 4.5:1. The brand blue itself is 3.53:1 against white — fine for an icon or a
        /// stroke, not for a label sitting on top of it.
        static let blueFill = Color(hex: 0x3D7B99)
        /// Etch Blue deepened for blue *text* on Warm Canvas: 4.86:1.
        static let blueText = Color(hex: 0x35708B)
        /// Graphite lightened for tertiary type that must still clear 4.5:1 on Canvas.
        static let graphiteLight = Color(hex: 0x6E7479)
        /// Mist darkened for a hairline that stays visible on Gallery White.
        static let mistDeep = Color(hex: 0xB9BEC0)
    }

    // MARK: - Layer 2: semantic tokens

    /// Grounds, in order of elevation. `background` is the page; `raised` is what sits on it;
    /// `sunken` is what is cut into it.
    enum Surface {
        /// The page itself.
        static let background = dynamic(light: Brand.canvas, dark: Brand.inkDeep)
        /// Cards, sheets, tiles, list rows — anything that lifts off the page.
        static let raised = dynamic(light: Brand.galleryWhite, dark: Brand.ink)
        /// Wells, text fields, segmented-control troughs, inactive tracks.
        static let sunken = dynamic(light: Brand.canvasSunken, dark: Brand.inkWell)
        /// A ground that reverses out of the page: filled tabs, dark chips, the selected pill.
        static let inverse = dynamic(light: Brand.ink, dark: Brand.canvas)
        /// Behind translucent map chrome, where a material needs something to sit on.
        static let chrome = dynamic(light: Brand.galleryWhite, dark: Brand.ink)
    }

    /// Type and icon colours. Named for what they say, not what they look like.
    enum Ink {
        /// Headlines, body copy, values — anything the eye is meant to land on.
        static let primary = dynamic(light: Brand.ink, dark: Brand.canvas)
        /// Supporting copy, units, secondary icons.
        static let secondary = dynamic(light: Brand.graphite, dark: Brand.mist)
        /// Metadata, timestamps, placeholder text, disabled labels.
        static let tertiary = dynamic(light: Brand.graphiteLight, dark: Brand.graphiteLight)
        /// Type sitting on `accentFill`.
        static let onAccent = dynamic(light: Brand.galleryWhite, dark: Brand.inkDeep)
        /// Type sitting on `Surface.inverse`.
        static let onInverse = dynamic(light: Brand.canvas, dark: Brand.ink)
    }

    /// Rules and borders. Etch draws hairlines rather than boxes wherever it can.
    enum Line {
        /// The default separator — a rule you notice only when you look for it.
        static let hairline = dynamic(light: Brand.mist.opacity(0.7), dark: Brand.graphite.opacity(0.55))
        /// A border that has to hold an edge: card outlines, input frames.
        static let strong = dynamic(light: Brand.mistDeep, dark: Brand.graphite)
    }

    // MARK: - Accent

    /// Etch Blue, for non-text interface: icons, strokes, selection marks, the route line.
    /// Clears the 3:1 that non-text UI needs on both grounds.
    static let accent = dynamic(light: Brand.blue, dark: Brand.blueLift)

    /// Etch Blue for a *solid* control that carries a label — deepened in light mode so the
    /// label on top clears AA. Use with `Ink.onAccent`.
    static let accentFill = dynamic(light: Brand.blueFill, dark: Brand.blueLift)

    /// Etch Blue as *text*: links, active labels, the value in a highlighted stat.
    static let accentText = dynamic(light: Brand.blueText, dark: Brand.blueLiftText)

    /// Etch Blue on translucent chrome floating over a map, where the ground underneath is a
    /// map rather than a surface token. Same values as `accent`; kept as its own name because
    /// the reason it lifts in dark mode is the map, not the appearance.
    static let accentOnGlass = accent

    /// Achievement moments — PRs, milestones, edition seals. Deliberately *not* a second
    /// accent hue: the brand has one accent, and a milestone earns weight, not colour.
    static let achievement = Ink.primary

    // MARK: - Layer 3: poster artwork

    /// The print palette. These are paper and ink, not interface: they render identically
    /// whatever appearance the phone is in, because a poster is the same poster at night.
    enum Artwork {
        /// Warm paper — the default poster ground.
        static let paper = Brand.canvas
        /// The brightest paper, for prints that want more light in them.
        static let paperBright = Brand.galleryWhite
        /// Paper with the tone pulled up, for panels and insets inside a print.
        static let paperDeep = Brand.canvasSunken
        /// Print ink.
        static let ink = Brand.ink
        /// Secondary print ink — captions, keys, coordinates.
        static let inkSoft = Brand.graphite
        /// Hairlines and graticules inside artwork.
        static let rule = Brand.mist
        /// The route, and the single blue dot that signs a piece.
        static let mark = Brand.blue
        /// A dark poster ground.
        static let inkGround = Brand.inkDeep

        // Retained tones for prints whose whole point is a different ground. These are print
        // stock choices offered to the customer, not interface colour, and the brand system
        // governs the app rather than the catalogue of papers.
        /// Deep topographic ground.
        static let topo = Color(hex: 0x1D342E)
        /// Muted green, for terrain fills.
        static let terrain = Color(hex: 0xBBC8B2)
        /// Warm metallic, for edition seals and foil-look details.
        static let seal = Color(hex: 0xB08D57)
    }

    // MARK: - Compatibility

    /// Older call sites still reach for `Theme.Palette.*`. Every name here now resolves to a
    /// brand or artwork token — there are no legacy values left behind these — and new code
    /// should use the semantic layer above instead.
    enum Palette {
        static let ink = Brand.ink
        static let blue = Brand.blue
        static let bone = Brand.canvas
        static let paper = Brand.galleryWhite
        static let stone = Brand.mist
        static let mist = Brand.mist
        static let graphite = Brand.graphite
        static let navy = Brand.ink
        static let blueBright = Brand.blueLift
        static let sage = Artwork.terrain
        static let brass = Artwork.seal
        static let forest = Artwork.topo
    }

    // MARK: - Route colour

    /// Routes render in Etch Blue. The age ramp keeps the same hue and walks it toward
    /// Graphite, so a wall of runs reads as one family rather than a heat map.
    enum Route {
        static let recent = Brand.blue
        static let warm = Color(hex: 0x5A93AC)
        static let mid = Color(hex: 0x6C8A99)
        static let old = Brand.graphite

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

    // MARK: - Shape and motion

    /// Corner radius used for floating glass controls.
    static let controlRadius: CGFloat = 22
    static let cardRadius: CGFloat = 28

    /// Snappy, Apple-Maps-like spring for chrome (dropdowns, capsules, map-option toggles) — a
    /// short response so controls feel immediate rather than lagging behind the tap.
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.86)
    /// Quick ease for view/mode changes — fast enough to feel responsive, still smooth.
    static let gentle = Animation.easeInOut(duration: 0.2)

    // MARK: - Appearance resolution

    /// Builds a colour that resolves per appearance. Every semantic token goes through here,
    /// which is why no view in the app has to branch on `colorScheme` to be correct.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    /// The one place a hex literal becomes a colour. Confined to `Theme.Brand` by convention.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

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
