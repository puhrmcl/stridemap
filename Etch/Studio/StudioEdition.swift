import SwiftUI

/// A curated Etch Studio *edition* — the brand's "choose an edition, not a template." Each is
/// a finished composition with its own material feel; the user picks one, they don't configure
/// it. Editions carry only presentation tokens (never workout data), so the same run renders
/// through any edition.
///
/// Per the brand system, geography stays muted and Etch Blue is a deliberate signal, not a
/// flood — so most editions keep the map quiet and reserve colour for the route.
struct StudioEdition: Identifiable, Equatable {

    enum ID: String, CaseIterable, Identifiable {
        case gallery, terrain, minimal, night, relief
        var id: String { rawValue }
    }

    /// How the art panel treats the map behind the route.
    enum Surface: Equatable {
        case map(dark: Bool)   // muted Apple Maps snapshot, light or dark
        case paper             // no map — the route on a plain material ground
    }

    let id: ID
    let name: String
    /// A short, editorial descriptor shown under the name in the picker.
    let descriptor: String

    let surface: Surface
    /// Poster background / paper colour.
    let ground: Color
    /// Colour washed over the map to unify it toward the material (map surfaces only).
    let mapWash: Color
    let mapWashAlpha: CGFloat

    let route: Color
    /// Optional under-stroke drawn beneath the route so it reads on any ground.
    let casing: Color?
    let routeWidth: CGFloat
    /// A soft glow beneath the route (used by Night).
    let glow: Bool

    let ink: Color          // primary type
    let subtle: Color       // metadata type
    let accent: Color       // hairlines, the "Etched." mark, small signals

    var usesMap: Bool { if case .map = surface { return true }; return false }
    var isDark: Bool { if case .map(let dark) = surface { return dark }; return false }

    // MARK: The collection

    static let all: [StudioEdition] = [.gallery, .terrain, .minimal, .night, .relief]

    static func edition(_ id: ID) -> StudioEdition { all.first { $0.id == id }! }

    /// Gallery — the house edition. A muted street map on Bone, the route in Etch Blue. The
    /// default; always looks composed.
    static let gallery = StudioEdition(
        id: .gallery, name: "Gallery",
        descriptor: "Muted map, route in Etch Blue, on gallery paper.",
        surface: .map(dark: false),
        ground: Theme.Palette.bone, mapWash: Theme.Palette.bone, mapWashAlpha: 0.24,
        route: Theme.Palette.blue, casing: .white, routeWidth: 11, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.blue
    )

    /// Terrain — geography as the material. The map reads more, washed toward Sage/earth, the
    /// route quiet ink over it.
    static let terrain = StudioEdition(
        id: .terrain, name: "Terrain",
        descriptor: "The land itself, muted, with the route drawn over it.",
        surface: .map(dark: false),
        ground: Theme.Palette.bone, mapWash: Theme.Palette.sage, mapWashAlpha: 0.30,
        route: Theme.Palette.ink, casing: Theme.Palette.bone, routeWidth: 10, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.brass
    )

    /// Minimal — gallery typography and a single fine line. No map. The most restrained.
    static let minimal = StudioEdition(
        id: .minimal, name: "Minimal",
        descriptor: "Just the line and the type. Nothing else.",
        surface: .paper,
        ground: Theme.Palette.bone, mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.ink, casing: nil, routeWidth: 6, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.5), accent: Theme.Palette.blue
    )

    /// Night — Etch Ink ground, the route glowing Etch Blue. For race mornings and dark runs.
    static let night = StudioEdition(
        id: .night, name: "Night",
        descriptor: "The route glowing on deep ink.",
        surface: .map(dark: true),
        ground: Theme.Palette.ink, mapWash: Theme.Palette.ink, mapWashAlpha: 0.42,
        route: Theme.Palette.blue, casing: nil, routeWidth: 10, glow: true,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.blue
    )

    /// Relief — monochrome, the route pressed into the paper like an etching. No colour, all
    /// material.
    static let relief = StudioEdition(
        id: .relief, name: "Relief",
        descriptor: "The route embossed into the paper, like an etching.",
        surface: .paper,
        ground: Theme.Palette.stone, mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.bone, casing: nil, routeWidth: 12, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.5), accent: Theme.Palette.ink
    )

    static func == (lhs: StudioEdition, rhs: StudioEdition) -> Bool { lhs.id == rhs.id }
}
