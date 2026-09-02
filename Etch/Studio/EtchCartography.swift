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

    /// Terrarium-encoded elevation tiles (NASA/USGS, proxied by the worker) — the raster-dem
    /// source MapLibre shades into real relief under the Terrain edition.
    static var terrainTileTemplate: String {
        CommerceConfig.workerBase.absoluteString + "/terrain/{z}/{x}/{y}.png"
    }

    /// USGS aerial photography (public domain, proxied by the worker). This is the imagery that
    /// finally makes Satellite *sellable* — US-government photography carries no merchandising
    /// restriction, where Apple's, Google's and Mapbox's all do.
    static var imageryTileTemplate: String {
        CommerceConfig.workerBase.absoluteString + "/imagery/{z}/{x}/{y}"
    }

    /// A complete MapLibre style document for an edition, as JSON data.
    ///
    /// - Parameter edition: supplies the palette. Only the map surfaces call this.
    /// - Parameter ground: the poster's paper. The map's land layer is set to exactly this, so the
    ///   panel and the sheet around it are one tone and no seam runs across the print. Nil uses
    ///   the edition's authored ground, which is only right when the user has not chosen a paper.
    /// - Parameter labels: whether place names are drawn. A poster usually wants them off — the
    ///   composition carries the location in type it controls, and a second set of names in a
    ///   font nobody chose is the fastest way to make a print look like a screenshot.
    static func styleJSON(for edition: StudioEdition, ground: Color? = nil,
                          labels: Bool = false) -> Data? {
        // Satellite is a different kind of map: photography, not linework. Its style is a
        // raster source and nothing else — the route, wash and type all happen in the app's
        // compositor, same as every other edition.
        if edition.id == .satellite { return satelliteStyleJSON(ground: ground) }

        let palette = Palette(edition: edition, paper: ground)
        var sources: [String: Any] = [
            "etch": ["type": "vector", "url": tileJSONURL.absoluteString]
        ]
        var drawn = layers(palette: palette, labels: labels)

        // The Terrain edition gets what its name promises: hillshade from real elevation,
        // inserted above the ground and parks but under water and roads, so relief reads as
        // the land's texture rather than a filter over the whole sheet.
        if edition.id == .terrain {
            sources["relief"] = [
                "type": "raster-dem",
                "encoding": "terrarium",
                "tiles": [terrainTileTemplate],
                "tileSize": 256,
                "maxzoom": 15
            ]
            let below = drawn.firstIndex { ($0["id"] as? String) == "water" } ?? 1
            drawn.insert([
                "id": "hillshade",
                "type": "hillshade",
                "source": "relief",
                "paint": [
                    "hillshade-exaggeration": 0.55,
                    "hillshade-shadow-color": "#5D6558",
                    "hillshade-highlight-color": "#FFFFFF",
                    "hillshade-accent-color": "#8A9180"
                ]
            ], at: below)
        }

        let style: [String: Any] = [
            "version": 8,
            "name": "Etch — \(edition.name)",
            "sources": sources,
            "layers": drawn
        ]
        return try? JSONSerialization.data(withJSONObject: style)
    }

    /// The Satellite style: USGS photography under a background the colour of the paper, so
    /// out-of-coverage margins come back as sheet rather than as void.
    private static func satelliteStyleJSON(ground: Color?) -> Data? {
        let paper = Palette(edition: .satellite, paper: ground).land
        let style: [String: Any] = [
            "version": 8,
            "name": "Etch — Satellite",
            "sources": [
                "imagery": [
                    "type": "raster",
                    "tiles": [imageryTileTemplate],
                    "tileSize": 256,
                    "maxzoom": 16
                ]
            ],
            "layers": [
                ["id": "ground", "type": "background",
                 "paint": ["background-color": paper]],
                ["id": "photo", "type": "raster", "source": "imagery"]
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: style)
    }

    /// The credit a printed panel must carry, per edition — ODbL for OpenStreetMap linework,
    /// the agencies for elevation and photography. Baked into the panel by the finisher.
    static func printAttribution(for edition: StudioEdition) -> String {
        switch edition.id {
        case .satellite: return "Imagery: USGS · USDA NAIP"
        case .terrain:   return "\(attribution) · Elevation: USGS, NASA"
        default:         return attribution
        }
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
        /// Parks, forests and greens — drawn only by the vivid palette; nil keeps the muted
        /// styles' silence about landuse.
        let park: String?

        /// - Parameter paper: the sheet the poster is printed on. Land is set to it exactly rather
        ///   than to something close, which is what keeps the panel from having an edge. The ink
        ///   is then chosen from the *paper*, not from the edition's authored darkness — a light
        ///   edition on a dark paper needs light linework or the map disappears into the sheet.
        init(edition: StudioEdition, paper: Color? = nil) {
            // Atlas is the one deliberate exception to "geography stays muted": a bright,
            // full-colour daylight map — true-blue water, green parks, amber highways — in
            // Etch's own tones rather than Apple's, which is what makes it sellable. Land still
            // follows the chosen paper so the panel never grows an edge.
            if edition.id == .atlas || edition.id == .atlasDark {
                let ground = paper ?? Color(red: 0.965, green: 0.955, blue: 0.93)
                land = Self.hex(ground)
                water = "#A5C8E8"
                park = "#C6E2BC"
                majorRoad = "#EFC468"
                minorRoad = "#DCD6CA"
                building = "#E9E3D7"
                label = "#6E7378"
                return
            }
            let ground = paper ?? edition.ground
            let ink = ground.isDarkGround ? Color.white : Theme.Palette.ink
            land = Self.hex(ground)
            // Water takes a touch of the route's colour rather than a generic blue: a coastline
            // that quietly rhymes with the run reads as one design, and a stock blue would be the
            // one thing on the sheet nobody chose.
            let dark = ground.isDarkGround
            water = Self.hex(Self.blend(ground, edition.route, 0.16))
            majorRoad = Self.hex(Self.blend(ground, ink, dark ? 0.34 : 0.26))
            minorRoad = Self.hex(Self.blend(ground, ink, dark ? 0.20 : 0.14))
            building = Self.hex(Self.blend(ground, ink, dark ? 0.13 : 0.08))
            label = Self.hex(Self.blend(ground, ink, 0.62))
            park = nil
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

        // Parks, for the vivid palette only. (These tiles were once wrongly convicted: a pbf
        // exception blamed on this layer was actually the worker serving stored-gzip bodies
        // the client never inflated — every layer of every tile decodes fine. Fixed in
        // fulfilment/src/tiles.ts, and the greens belong to Bright again.) Under water, so a
        // riverside park keeps its riverbank; only the unambiguously green kinds, because
        // landuse also carries hospitals and industrial estates nobody wants tinted.
        if let park = palette.park {
            layers.insert([
                "id": "parks",
                "type": "fill",
                "source": "etch",
                "source-layer": "landuse",
                "filter": ["in", "kind",
                           "park", "forest", "wood", "grass", "meadow", "garden", "cemetery",
                           "golf_course", "nature_reserve", "protected_area", "village_green",
                           "recreation_ground", "allotments", "zoo"],
                "paint": ["fill-color": park]
            ], at: 1)
        }

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
