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
        case gallery, atlas, atlasDark, streets, streetsNoir, harbor, satellite, terrain, trailJournal, midnightAtlas, minimal, night, memory
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
    /// Overrides the contour-line colour on `.contour` editions (e.g. gold on Midnight Atlas).
    /// Nil derives it from the ground — ink on a light ground, bone on a dark one.
    var contourTint: Color? = nil
    /// When set, the map snapshot is desaturated to this level (0 = full monochrome) before the
    /// wash — the "just streets, very minimal" city-print treatment. Nil leaves the map's own
    /// colour (satellite has its own fixed desaturation).
    var panelSaturation: CGFloat? = nil

    /// The art panel is a pre-rendered image (map snapshot, photo, or contour field), not a plain
    /// vector ground.
    var usesImagePanel: Bool {
        switch surface { case .map, .photo, .contour: return true; case .paper: return false }
    }
    var mapKind: MapKind? { if case .map(let kind) = surface { return kind }; return nil }
    /// Whether this edition's artwork may be sold as a print. Editions whose panel is an Apple
    /// Maps snapshot are display-only: Apple licenses map data for in-app use, not for
    /// merchandise. They return to the shop when the self-owned OSM cartography replaces the
    /// snapshot source; contour, paper, and photo panels are ours end to end.
    var printReady: Bool { mapKind == nil }
    var isPhoto: Bool { surface == .photo }
    var isContour: Bool { surface == .contour }
    var isDark: Bool { mapKind == .streetsDark || mapKind == .standardDark }
    /// Editions whose ground shows behind vector/contour art, so a user ground colour is
    /// meaningful (and offered in Customize).
    var groundIsCanvas: Bool { surface == .paper || surface == .contour }

    // MARK: The collection

    static let all: [StudioEdition] = [.gallery, .atlas, .atlasDark, .streets, .streetsNoir, .harbor, .satellite, .terrain, .trailJournal, .midnightAtlas, .minimal, .night, .memory]

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

    /// Streets — the classic city print: streets alone in the palest grey on paper, everything
    /// else silent, the route inked over in near-black. Fully monochrome, made to be framed.
    static let streets = StudioEdition(
        id: .streets, name: "Streets",
        descriptor: "Just the streets, in pale grey — the route inked over.",
        surface: .map(.streetsLight),
        ground: Theme.Palette.bone, mapWash: Theme.Palette.bone, mapWashAlpha: 0.45,
        route: Theme.Palette.ink, casing: .white, routeWidth: 11, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.ink,
        panelSaturation: 0
    )

    /// Streets Noir — the same city print after dark: faint streets on near-black, the route in
    /// bone white. The pair to Streets, for dark walls.
    static let streetsNoir = StudioEdition(
        id: .streetsNoir, name: "Streets Noir",
        descriptor: "Faint streets on near-black, the route in white.",
        surface: .map(.streetsDark),
        ground: Theme.Palette.ink, mapWash: Theme.Palette.ink, mapWashAlpha: 0.40,
        route: Theme.Palette.bone, casing: Theme.Palette.ink, routeWidth: 11, glow: false,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.bone,
        panelSaturation: 0
    )

    /// The Harbor editions' deep slate-navy — between Etch Ink and a nautical chart.
    private static let harborNavy = Color(red: 0.16, green: 0.20, blue: 0.30)

    /// Harbor — the city in deep navy, the route in gold. The desaturated dark map washed toward
    /// slate-navy so streets and water read as tonal texture; brass route, bone type. The premium
    /// marathon-print colourway.
    static let harbor = StudioEdition(
        id: .harbor, name: "Harbor",
        descriptor: "The city in deep navy, the route in gold.",
        surface: .map(.streetsDark),
        ground: harborNavy, mapWash: harborNavy, mapWashAlpha: 0.55,
        route: Theme.Palette.brass, casing: nil, routeWidth: 11, glow: false,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.65), accent: Theme.Palette.brass,
        panelSaturation: 0
    )

    /// Satellite — the route over real aerial imagery, gently deepened so the Etch Blue route
    /// still leads.
    static let satellite = StudioEdition(
        id: .satellite, name: "Satellite",
        descriptor: "The route over real aerial imagery.",
        surface: .map(.satellite),
        ground: Theme.Palette.ink, mapWash: Theme.Palette.ink, mapWashAlpha: 0.14,
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

    /// Trail Journal — hand-drawn terrain contour lines on aged paper, the route inked over. The
    /// classic "great trails" hiking print: quiet, editorial, decor-worthy.
    static let trailJournal = StudioEdition(
        id: .trailJournal, name: "Trail Journal",
        descriptor: "Terrain contour lines on aged paper, the route inked over.",
        surface: .contour,
        ground: Theme.Palette.bone, mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.ink, casing: nil, routeWidth: 8, glow: false,
        ink: Theme.Palette.ink, subtle: Theme.Palette.ink.opacity(0.55), accent: Theme.Palette.brass
    )

    /// Midnight Atlas — gold contour lines across deep ink, the route aglow. The premium,
    /// gift-worthy hiking print.
    static let midnightAtlas = StudioEdition(
        id: .midnightAtlas, name: "Midnight Atlas",
        descriptor: "Gold contour lines across deep ink, the route aglow.",
        surface: .contour,
        ground: Theme.Palette.ink, mapWash: .clear, mapWashAlpha: 0,
        route: Theme.Palette.brass, casing: nil, routeWidth: 9, glow: true,
        ink: Theme.Palette.bone, subtle: Theme.Palette.bone.opacity(0.6), accent: Theme.Palette.brass,
        contourTint: Theme.Palette.brass
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
