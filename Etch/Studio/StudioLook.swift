import SwiftUI

/// A coordinated *look* — one tap that sets the map treatment, the ground, the type colour and the
/// route together, the way a designer would move them.
///
/// This is the control the old editor never had. It offered eleven free axes and no opinion, so a
/// user who wanted "make it dark" had to know that meant Streets Noir *and* a bone ink *and* a
/// white route — three separate rows in two separate tabs, each of which looks wrong until the
/// other two are also right. Most combinations of eleven axes are worse than any authored one.
///
/// A Look never touches content. Titles, data slots, photographs and the frame arrangement all
/// survive it, so trying one is cheap and reversible — which is the whole point of putting it
/// first.
enum StudioLook: String, CaseIterable, Identifiable {
    case light, dark, mono, warm
    var id: String { rawValue }

    /// Harbor's slate-navy, written once. Both `applied` and `matches` compare against it, and a
    /// preset that set one literal while testing against a second would simply never light up.
    static let warmGround = Color(red: 0.16, green: 0.20, blue: 0.30)

    var name: String {
        switch self {
        case .light: return "Light"
        case .dark:  return "Dark"
        case .mono:  return "Mono"
        case .warm:  return "Warm"
        }
    }

    /// The swatch pair shown in the picker: ground behind, route in front.
    var groundSwatch: Color {
        switch self {
        case .light, .mono: return Theme.Palette.bone
        case .dark:         return Theme.Palette.ink
        case .warm:         return StudioLook.warmGround
        }
    }
    var routeSwatch: Color {
        switch self {
        case .light: return Theme.Palette.blue
        case .dark:  return Theme.Palette.bone
        case .mono:  return Theme.Palette.ink
        case .warm:  return Theme.Palette.brass
        }
    }

    /// Applied to a recipe. Colours are written explicitly rather than left on `nil`/auto so the
    /// look holds when the user later changes the map — a Look is a decision, not a default.
    ///
    /// The map is re-resolved through its *material* rather than replaced. A Look used to name a
    /// map style outright, so switching to Dark silently threw away a chosen Contour and handed
    /// back Streets Noir; now Contour stays contour and simply goes dark. That is what makes these
    /// two controls independent instead of overlapping.
    func applied(to base: PosterConfig) -> PosterConfig {
        var c = base
        if c.family == .map {
            c.mapStyle = MapMaterial.of(c.mapStyle).style(for: self)
        }
        switch self {
        case .light:
            c.monochrome = false
            c.groundColor = Theme.Palette.bone
            c.textColor = Theme.Palette.ink
            c.routeColor = Theme.Palette.blue
        case .dark:
            c.monochrome = false
            c.groundColor = Theme.Palette.ink
            c.textColor = Theme.Palette.bone
            c.routeColor = Theme.Palette.bone
        case .mono:
            c.monochrome = true
            c.groundColor = Theme.Palette.bone
            c.textColor = Theme.Palette.ink
            c.routeColor = Theme.Palette.ink
        case .warm:
            c.monochrome = false
            c.groundColor = StudioLook.warmGround
            c.textColor = Theme.Palette.bone
            c.routeColor = Theme.Palette.brass
        }
        return c
    }

    /// Whether a recipe currently reads as this look. Everything else is "Custom", which is a real
    /// state rather than a fallback: a user who has hand-picked a route colour should not see a
    /// preset claiming credit for it.
    func matches(_ c: PosterConfig) -> Bool {
        let target = applied(to: c)
        return c.monochrome == target.monochrome
            && c.groundColor == target.groundColor
            && c.textColor == target.textColor
            && c.routeColor == target.routeColor
            && (c.family != .map || c.mapStyle == target.mapStyle)
    }

    static func current(for c: PosterConfig) -> StudioLook? {
        allCases.first { $0.matches(c) }
    }
}

/// A colour palette — the three ink decisions (type, ground, route) as one coordinated choice.
///
/// Sits a level below `StudioLook`: a Look also moves the map treatment and is the fast start,
/// while a Palette is the colour-only refinement offered inside Customize. Selecting **Custom**
/// hands over the three individual pickers, which is where the old editor started everybody.
enum StudioPalette: String, CaseIterable, Identifiable {
    case classic, etch, warm, mono
    var id: String { rawValue }

    var name: String {
        switch self {
        case .classic: return "Classic"
        case .etch:    return "Etch"
        case .warm:    return "Warm"
        case .mono:    return "Mono"
        }
    }

    /// (text, ground, route) — the palette's three inks, in the order the swatch draws them.
    var colors: (text: Color, ground: Color, route: Color) {
        switch self {
        case .classic: return (Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.ink)
        case .etch:    return (Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.blue)
        case .warm:    return (Theme.Palette.bone, StudioLook.warmGround, Theme.Palette.brass)
        case .mono:    return (Theme.Palette.bone, Theme.Palette.ink, Theme.Palette.bone)
        }
    }

    func applied(to base: PosterConfig) -> PosterConfig {
        var c = base
        let p = colors
        c.textColor = p.text
        c.groundColor = p.ground
        c.routeColor = p.route
        return c
    }

    func matches(_ c: PosterConfig) -> Bool {
        let p = colors
        return c.textColor == p.text && c.groundColor == p.ground && c.routeColor == p.route
    }

    static func current(for c: PosterConfig) -> StudioPalette? {
        allCases.first { $0.matches(c) }
    }
}

/// A coordinated type system — the face plus the rhythm that suits it, as one choice.
///
/// The three faces already existed; what did not was any link between choosing a serif and the
/// tracking a serif wants. Picking a system here sets the face and resets the per-element sizes to
/// that system's balance, so "Editorial" is a finished typographic decision rather than the first
/// of five.
enum StudioTypeSystem: String, CaseIterable, Identifiable {
    case editorial, modern, poster
    var id: String { rawValue }

    var name: String {
        switch self {
        case .editorial: return "Editorial"
        case .modern:    return "Modern"
        case .poster:    return "Poster"
        }
    }

    var font: PosterFont {
        switch self {
        case .editorial: return .editorial
        case .modern:    return .modern
        case .poster:    return .poster
        }
    }

    /// The per-element balance each system opens on. A poster face wants a bigger headline and
    /// quieter supporting lines; an editorial serif wants them closer together.
    private var balance: (title: CGFloat, hero: CGFloat, stat: CGFloat) {
        switch self {
        case .editorial: return (1.0, 1.0, 1.0)
        case .modern:    return (1.0, 1.05, 1.0)
        case .poster:    return (1.15, 1.15, 0.85)
        }
    }

    func applied(to base: PosterConfig) -> PosterConfig {
        var c = base
        c.font = font
        let b = balance
        c.titleScale = b.title
        c.heroScale = b.hero
        c.statScale = b.stat
        return c
    }

    func matches(_ c: PosterConfig) -> Bool {
        let b = balance
        return c.font == font
            && abs(c.titleScale - b.title) < 0.01
            && abs(c.heroScale - b.hero) < 0.01
            && abs(c.statScale - b.stat) < 0.01
    }

    static func current(for c: PosterConfig) -> StudioTypeSystem? {
        allCases.first { $0.matches(c) }
    }
}
