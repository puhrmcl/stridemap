import MapKit
import SwiftUI
import UIKit

/// Puts Etch's palette on the live map.
///
/// The problem this solves: the app's own cartography (`EtchCartography`, OpenStreetMap through
/// MapLibre) is what the *prints* are drawn from, and it is beautiful — but it is gated on the
/// basemap archive being live, and it only renders to snapshots. The screen map is MapKit, and
/// MapKit's standard style is recognisably Apple's: Apple's greens, Apple's blues, Apple's beige.
/// A product whose whole proposition is "your movement, as art" cannot open on somebody else's
/// map.
///
/// What it does instead: a translucent sheet of the brand's paper laid over the basemap, using
/// MapKit's own overlay levels rather than anything private.
///
/// **It is a plain fill, and that is a limitation, not a preference.** The first version of this
/// drew with `CGBlendMode.color`, which keeps a backdrop's luminosity and replaces only its hue —
/// the right tool, and it would have re-inked the map without flattening it. It does not work
/// here. MapKit renders an overlay into its own transparency layer and composites the finished
/// layer onto the map, so a blend mode set inside `draw(_:zoomScale:in:)` blends against the
/// layer's own empty pixels and degrades to source-over.
///
/// That was measured rather than assumed. Sampling the same ocean before and after, a single
/// alpha of ~0.775 explains the red and green channels exactly; a `.color` blend would have
/// landed water near (0.671, 0.738, 0.754) and it landed at (0.847, 0.910, 0.918). One alpha
/// fitting every channel is source-over, and nothing else.
///
/// So this is honest about what it is: a wash. It takes Apple's greens and blues decisively out
/// of the map and puts Etch's paper in their place, at the cost of some of the map's contrast.
/// The map stops being recognisably Apple's. It does not become a piece of Etch cartography —
/// only `EtchCartography` does that, and it needs the basemap archive live.
///
/// Two things still hold, and they are the parts that matter:
///
///   · The wash sits at `.aboveRoads`, which is *below* MapKit's labels, so place names stay
///     crisp rather than being bleached into the paper.
///   · It is inserted at index 0 of that level, so every route polyline added afterwards draws
///     on top of it. Etch Blue stays Etch Blue; the wash never touches the subject.
///
/// This is display only, and stays that way. An Apple snapshot with a colour laid over it is
/// still Apple's map data, so nothing here changes what may be printed — `StudioEdition.printReady`
/// and the basemap gate remain the only answer to that question.
final class EtchMapWash: NSObject, MKOverlay {

    /// The whole world, because the wash has to be there before the user pans to it.
    var boundingMapRect: MKMapRect { .world }

    /// Required by `MKOverlay`; the centre of a world-covering rect is the origin.
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 0, longitude: 0) }

    /// The tone the map is washed toward.
    let tone: UIColor

    /// How opaque the paper is.
    ///
    /// The number is a trade with no clever answer, because a plain fill can only move the map
    /// toward one colour: too little and Apple's green survives, too much and the map bleaches
    /// into a flat sheet. Measured at 0.76 the green was gone and the map had lost more contrast
    /// than it should. 0.68 keeps noticeably more of the coastline and the road structure while
    /// still reading as paper rather than as Apple's map behind a veil.
    static let strength: CGFloat = 0.68

    init(tone: UIColor) {
        self.tone = tone
        super.init()
    }

    /// The wash for a map style, or nil for the styles that should keep their own colour.
    ///
    /// Explore is deliberately excluded: it exists to be Apple's full navigational map, points of
    /// interest and all, and washing it would remove the one thing it is for. Satellite, Hybrid
    /// and Terrain are photographs of real land, and tinting a photograph is a filter, not a
    /// brand.
    @MainActor
    static func tone(for style: MapStyleOption) -> UIColor? {
        switch style {
        case .standard: return UIColor(Theme.Brand.canvas)
        case .night:    return UIColor(Theme.Brand.ink)
        case .explore, .terrain, .satellite, .hybrid: return nil
        }
    }
}

/// Draws the wash: one flat fill per tile.
///
/// Cheap by construction. There is no geometry to rasterise — the renderer fills whatever rect
/// MapKit hands it — so panning and zooming cost the same as they did before.
final class EtchMapWashRenderer: MKOverlayRenderer {

    private let tone: UIColor

    init(wash: EtchMapWash) {
        self.tone = wash.tone
        super.init(overlay: wash)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // One fill, source-over. No blend mode: MapKit composites this renderer's own layer onto
        // the map, so anything set here blends against empty pixels rather than against the
        // cartography, and every mode collapses to this anyway. Writing the honest operation is
        // better than writing an ambitious one that silently is not happening.
        context.setAlpha(EtchMapWash.strength)
        context.setFillColor(tone.cgColor)
        context.fill(self.rect(for: mapRect))
    }
}
