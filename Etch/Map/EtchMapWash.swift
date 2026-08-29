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
/// What it does instead: a wash laid over the basemap, in Etch's own tone, using MapKit's own
/// overlay levels rather than anything private. `.color` blending keeps the map's luminosity —
/// every road, block and coastline stays exactly where it was and reads exactly as legibly — and
/// replaces its hue with the brand's. Apple's map becomes an Etch map without a single tile
/// being redrawn.
///
/// Two things keep it honest:
///
///   · The wash sits at `.aboveRoads`, which is *below* MapKit's labels, so place names stay
///     crisp and dark rather than being tinted into the paper.
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

    /// How much of the map's own hue survives. Not 1.0 on purpose: a complete replacement makes
    /// water and land the same colour, and a map where you cannot find the coastline is a worse
    /// map however handsome it is. At this strength the sea keeps just enough blue in it to read
    /// as sea, and everything else lands firmly on Etch's warm neutral.
    static let strength: CGFloat = 0.76

    /// A second, much lighter pass in `multiply`, which puts the paper's warmth back into the
    /// whites that `.color` leaves untouched — a `.color` blend cannot tint pure white, and
    /// Apple's map has a lot of near-white in it.
    static let paperDepth: CGFloat = 0.12

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

/// Draws the wash: one flat fill per tile, twice, in two blend modes.
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
        let rect = self.rect(for: mapRect)

        // Hue and saturation from the wash, luminosity from the map. This is the pass that does
        // the work: the map's structure is entirely preserved and only its colour changes.
        context.saveGState()
        context.setBlendMode(.color)
        context.setAlpha(EtchMapWash.strength)
        context.setFillColor(tone.cgColor)
        context.fill(rect)
        context.restoreGState()

        // `.color` leaves white white, and Apple's map is largely near-white. This is what stops
        // the result reading as "a grey map" and makes it read as ink on warm paper.
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setAlpha(EtchMapWash.paperDepth)
        context.setFillColor(tone.cgColor)
        context.fill(rect)
        context.restoreGState()
    }
}
