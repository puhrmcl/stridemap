import SwiftUI
import UIKit

/// Etch's own cartography: a MapLibre style built from an edition's palette.
///
/// Apple licenses its map data for display inside an app, not for merchandise, so every edition
/// drawn from an `MKMapSnapshotter` is unsellable — `StudioEdition.printReady` returns false for
/// all five map kinds, which is the largest single gate on the catalogue. Nothing in the print
/// engine moves it. Only owning the cartography does.
///
/// The data is OpenStreetMap, packaged as a Protomaps basemap and served by the fulfilment worker
/// out of R2 (`fulfilment/src/tiles.ts`). What this file supplies is the *look*: a MapLibre style
/// document describing which features to draw and in what colours.
///
/// The style is generated rather than authored as a set of JSON files, and that is the important
/// decision here. Etch has thirteen editions and each one already carries a ground, an ink, a wash
/// and a route colour chosen together. Hand-writing a style per edition would fork that palette
/// into a second place and guarantee they drift — a new edition would look right everywhere except
/// on its own map. Deriving the style from the edition means adding an edition is still a matter
/// of naming four colours, and its map arrives in them.
///
/// Attribution: OpenStreetMap is ODbL. The line travels with anything published, print included.
enum EtchCartography {

    static let attribution = "© OpenStreetMap contributors"

    /// Where the tiles come from — the same worker that holds print assets, so there is one
    /// origin to configure and one to secure.
    static var tileJSONURL: URL {
        CommerceConfig.workerBase.appendingPathComponent("tiles/tiles.json")
    }

    /// A complete MapLibre style document for an edition, as JSON data.
    ///
    /// - Parameter edition: supplies the palette. Only the map surfaces call this.
    /// - Parameter labels: whether place names are drawn. A poster usually wants them off — the
    ///   composition carries the location in type it controls, and a second set of names in a
    ///   font nobody chose is the fastest way to make a print look like a screenshot.
    static func styleJSON(for edition: StudioEdition, labels: Bool = false) -> Data? {
        let palette = Palette(edition: edition)
        let style: [String: Any] = [
            "version": 8,
            "name": "Etch — \(edition.name)",
            "sources": [
                "etch": ["type": "vector", "url": tileJSONURL.absoluteString]
            ],
            "layers": layers(palette: palette, labels: labels)
        ]
        return try? JSONSerialization.data(withJSONObject: style)
    }

    // MARK: The palette a map is drawn in

    /// The six tones a map needs, derived from the four an edition already declares.
    ///
    /// Nothing new is invented: land is the edition's own ground so the map sits on the paper
    /// rather than on top of it, and everything else is the edition's ink at a weight chosen for
    /// how loud that feature should be. The result is a map that recedes — the route is the
    /// subject, the city is context — which is the whole reason these posters read as art rather
    /// than as navigation.
    struct Palette {
        let land: String
        let water: String
        let majorRoad: String
        let minorRoad: String
        let building: String
        let label: String

        init(edition: StudioEdition) {
            let ground = edition.ground
            let ink = edition.isDark ? Color.white : Theme.Palette.ink
            land = Self.hex(ground)
            // Water takes a touch of the route's colour rather than a generic blue: a coastline
            // that quietly rhymes with the run reads as one design, and a stock blue would be the
            // one thing on the sheet nobody chose.
            water = Self.hex(Self.blend(ground, edition.route, 0.16))
            majorRoad = Self.hex(Self.blend(ground, ink, edition.isDark ? 0.34 : 0.26))
            minorRoad = Self.hex(Self.blend(ground, ink, edition.isDark ? 0.20 : 0.14))
            building = Self.hex(Self.blend(ground, ink, edition.isDark ? 0.13 : 0.08))
            label = Self.hex(Self.blend(ground, ink, 0.62))
        }

        /// `amount` of `top` over `base`, in sRGB.
        private static func blend(_ base: Color, _ top: Color, _ amount: CGFloat) -> Color {
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
            UIColor(base).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            UIColor(top).getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            return Color(red: Double(br + (tr - br) * amount),
                         green: Double(bg + (tg - bg) * amount),
                         blue: Double(bb + (tb - bb) * amount))
        }

        private static func hex(_ color: Color) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(format: "#%02X%02X%02X",
                          Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        }
    }

    // MARK: Layers

    /// The style's draw order, bottom to top.
    ///
    /// Deliberately short. A navigation basemap carries thirty-odd layers because it has to answer
    /// "which turn"; a poster carries six because it has to answer "where was this". Land, water,
    /// the shape of the built-up area, two weights of road, and optionally names. Everything else —
    /// transit, POIs, boundaries, landuse tints — is detail the route has to compete with.
    private static func layers(palette: Palette, labels: Bool) -> [[String: Any]] {
        var layers: [[String: Any]] = [
            [
                "id": "ground",
                "type": "background",
                "paint": ["background-color": palette.land]
            ],
            [
                "id": "water",
                "type": "fill",
                "source": "etch",
                "source-layer": "water",
                "paint": ["fill-color": palette.water]
            ],
            [
                "id": "buildings",
                "type": "fill",
                "source": "etch",
                "source-layer": "buildings",
                // Buildings only at close zooms: at city scale they merge into a grey wash that
                // fights the route, and at street scale they are the texture that says "here".
                "minzoom": 14,
                "paint": ["fill-color": palette.building]
            ],
            [
                "id": "roads-minor",
                "type": "line",
                "source": "etch",
                "source-layer": "roads",
                "filter": ["!in", "kind", "highway", "major_road"],
                "minzoom": 12,
                "layout": ["line-cap": "round", "line-join": "round"],
                "paint": [
                    "line-color": palette.minorRoad,
                    // Hairlines that thicken with zoom rather than a fixed weight — a constant
                    // width turns a dense grid into a solid block at low zoom.
                    "line-width": ["interpolate", ["linear"], ["zoom"],
                                   12, 0.3, 15, 0.8, 18, 2.0]
                ]
            ],
            [
                "id": "roads-major",
                "type": "line",
                "source": "etch",
                "source-layer": "roads",
                "filter": ["in", "kind", "highway", "major_road", "medium_road"],
                "layout": ["line-cap": "round", "line-join": "round"],
                "paint": [
                    "line-color": palette.majorRoad,
                    "line-width": ["interpolate", ["linear"], ["zoom"],
                                   6, 0.4, 10, 1.0, 14, 2.2, 18, 5.0]
                ]
            ]
        ]

        if labels {
            layers.append([
                "id": "places",
                "type": "symbol",
                "source": "etch",
                "source-layer": "places",
                "filter": ["in", "kind", "locality", "region"],
                "layout": [
                    "text-field": ["get", "name"],
                    "text-font": ["Noto Sans Regular"],
                    "text-size": ["interpolate", ["linear"], ["zoom"], 6, 10, 12, 14],
                    "text-letter-spacing": 0.08,
                    "text-max-width": 8
                ],
                "paint": [
                    "text-color": palette.label,
                    "text-halo-color": palette.land,
                    "text-halo-width": 1.2
                ]
            ])
        }
        return layers
    }
}
