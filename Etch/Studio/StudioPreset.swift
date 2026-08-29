import SwiftUI

/// A complete starting point — template, map treatment and colour world decided together, as one
/// finished poster you can tap once and be done with.
///
/// The editor asked three separate questions before it showed anybody anything good: which
/// template, which map style, which look. Each is reasonable alone and each is meaningless alone —
/// Full Bleed over pale Streets is washed out, Nameplate over Satellite is unreadable, and a first
/// time through you have no way to know that except by trying nine combinations. Presets are the
/// combinations that work, chosen in advance, shown as the thing they produce.
///
/// The individual axes stay right underneath for anyone who wants them. This is the fast lane, not
/// a replacement for the controls.
struct StudioPreset: Identifiable {
    let id: String
    let name: String
    let template: MapLayout
    let mapStyle: MapStyle
    let look: StudioLook

    /// A preset applied to a recipe. Content survives — the title, the data, the photographs are
    /// the user's, and a starting point that wiped them would not be a starting point.
    func applied(to base: PosterConfig) -> PosterConfig {
        var c = base
        c.mapLayout = template
        c.mapStyle = mapStyle
        c = look.applied(to: c)
        // Nameplate sets its figures as a row of peers, and a row of one is not a row.
        if template == .nameplate && c.dataSlots.isEmpty {
            c.dataSlots = [.elevationGain, .time]
        }
        return c
    }

    func matches(_ c: PosterConfig) -> Bool {
        c.mapLayout == template && c.mapStyle == mapStyle && look.matches(c)
    }

    /// The seven that carry the range: two quiet papers, two city prints, a trail, a photograph and
    /// a bare line. Deliberately not one per map style — a wall of near-identical greys teaches
    /// nobody anything, and the point of this row is that every card in it is worth printing.
    static let all: [StudioPreset] = [
        StudioPreset(id: "gallery",  name: "Gallery",   template: .nameplate, mapStyle: .streets,     look: .light),
        StudioPreset(id: "noir",     name: "Noir",      template: .nameplate, mapStyle: .streetsNoir, look: .dark),
        StudioPreset(id: "harbor",   name: "Harbor",    template: .nameplate, mapStyle: .harbor,      look: .warm),
        StudioPreset(id: "trail",    name: "Trail",     template: .nameplate, mapStyle: .contour,     look: .warm),
        StudioPreset(id: "terrain",  name: "Terrain",   template: .nameplate, mapStyle: .terrain,     look: .light),
        StudioPreset(id: "fullbleed", name: "Immersive", template: .fullBleed, mapStyle: .satellite,  look: .dark),
        StudioPreset(id: "line",     name: "Line",      template: .minimal,   mapStyle: .none,        look: .mono)
    ]

    static func current(for c: PosterConfig) -> StudioPreset? {
        all.first { $0.matches(c) }
    }
}
