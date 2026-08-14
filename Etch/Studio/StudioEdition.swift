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
        case gallery, atlas, atlasDark, terrain, minimal, night, topographic, memory
        var id: String { rawValue }
    }

    /// Which real map renders behind the route.
    enum MapKind: Equatable {
        case streetsLight   // muted standard map, light
        case streetsDark    // muted standard map, dark
        case satellite      // real terrain imagery (desaturated, muted) — actual topography
        case standardLight  // full-colour Apple Maps, light
        case standardDark   // full-colour Apple Maps, dark
    }

    /// How the art panel treats the ground behind the route.
    enum Surface: Equatable {
        case map(MapKind)   // a real Apple Maps snapshot (route embedded)
        case paper          // no map — the route on a plain material ground
        case photo          // the run's own photo, with the route etched over it
        case contour        // real terrain contour lines traced behind the route
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

    /// The art panel is a pre-rendered image (map snapshot, photo, or contour field), not a plain
    /// vector ground.
    var usesImagePanel: Bool {
        switch surface { case .map, .photo, .contour: return true; case .paper: return false }
    }
    var mapKind: MapKind? { if case .map(let kind) = surface { return kind }; return nil }
    var isPhoto: Bool { surface == .photo }
    var isContour: Bool { surface == .contour }
    var isDark: Bool { mapKind == .streetsDark || mapKind == .standardDark }
    /// Editions whose ground shows behind vector/contour art, so a user ground colour is
    /// meaningful (and offered in Customize).
    var groundIsCanvas: Bool { surface == .paper || surface == .contour }

    // MARK: The collection

    static let all: [StudioEdition] = [.gallery, .atlas, .atlasDark, .terrain, .minimal, .night, .topographic, .memory]

    static func edition(_ id: ID) -> StudioEdition { all.first { $0.id == id }! }

    /// Editions offered for a given run. Memory needs a photo, so it's only offered when the
    /// run has one.
    static func available(for run: Run) -> [StudioEdition] {
        all.filter { $0.id != .memory || !run.photoReferences.isEmpty }
    }

    /// Gallery — the house edition. A muted street map on Bone, the route in Etch Blue. The
    /// default; always looks composed.
    static let gallery = StudioEdition(
        id: .gallery, name: "Gallery",
        descriptor: "Muted map, route in Etch Blue, on gallery paper.",
        surface: .map(.streetsLight),
        ground: Theme.Palette.bone, mapWash: Theme.Palette.bone, mapWashAlpha: 0.24,
        route: Theme.Palette.blue, casing: .white, routeWidth: 11, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.blue
    )

    /// Atlas — the classic Apple Maps look in full daylight colour (no muting), route in Etch
    /// Blue over it. For when the geography itself should read.
    static let atlas = StudioEdition(
        id: .atlas, name: "Atlas",
        descriptor: "Classic Apple Maps colours, in daylight.",
        surface: .map(.standardLight),
        ground: Theme.Palette.bone, mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.blue, casing: .white, routeWidth: 11, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.blue
    )

    /// Atlas Dark — the classic Apple Maps look in full dark-mode colour, route in Etch Blue.
    static let atlasDark = StudioEdition(
        id: .atlasDark, name: "Atlas Dark",
        descriptor: "Classic Apple Maps colours, after dark.",
        surface: .map(.standardDark),
        ground: Theme.Palette.ink, mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.blue, casing: .white, routeWidth: 11, glow: false,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.blue
    )

    /// Terrain — geography as the material. The map reads more, washed toward Sage/earth, the
    /// route quiet ink over it.
    static let terrain = StudioEdition(
        id: .terrain, name: "Terrain",
        descriptor: "The land itself, muted, with the route drawn over it.",
        surface: .map(.streetsLight),
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
        descriptor: "The route in Etch Blue on deep ink.",
        surface: .map(.streetsDark),
        ground: Theme.Palette.ink, mapWash: Theme.Palette.ink, mapWashAlpha: 0.42,
        route: Theme.Palette.blue, casing: nil, routeWidth: 10, glow: false,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.blue
    )

    /// Topographic — real terrain contour lines traced behind the route, pen-plotted style. The
    /// ground defaults to deep ink but is customizable; the route sits over the contours.
    static let topographic = StudioEdition(
        id: .topographic, name: "Topographic",
        descriptor: "Real elevation contours, pen-plotted behind your route.",
        surface: .contour,
        ground: Theme.Palette.ink,
        mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.blue, casing: .white, routeWidth: 10, glow: false,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.brass
    )

    /// Memory — the run's own photograph fills the panel, with the route etched over it in Etch
    /// Blue. Route + photograph + the details beneath. Only offered when the run has a photo.
    static let memory = StudioEdition(
        id: .memory, name: "Memory",
        descriptor: "Your photo from the day, with the route etched over it.",
        surface: .photo,
        ground: Theme.Palette.ink,
        mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.blue, casing: .white, routeWidth: 9, glow: false,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.blue
    )

    static func == (lhs: StudioEdition, rhs: StudioEdition) -> Bool { lhs.id == rhs.id }
}
