import Foundation
import MapKit
import UIKit

/// US state (+ DC / territories) boundary geometry, loaded once from a bundled GeoJSON.
/// Powers the "states you've run in" map and attributes each run to a state by
/// point-in-polygon — independent of geocoding, so it works offline and even for runs whose
/// place names never resolved.
///
/// Immutable after `init` (boundaries are only ever read), so it's safe to touch from the
/// map's delegate callbacks and any actor — hence `@unchecked Sendable`.
final class USStateBoundaries: @unchecked Sendable {

    static let shared = USStateBoundaries()

    struct StateBoundary {
        let name: String
        let polygons: [MKPolygon]
        let boundingMapRect: MKMapRect
    }

    /// All boundaries. Empty only if the bundled resource is missing (feature degrades
    /// gracefully to an empty map rather than crashing).
    let boundaries: [StateBoundary]

    /// The 50 states used as the "collection" denominator — DC and territories are shown on
    /// the map and listed, but don't count toward the 50.
    let stateGoal = 50
    private static let nonStateNames: Set<String> = ["District of Columbia", "Puerto Rico"]

    private init() {
        boundaries = USStateBoundaries.load()
    }

    /// Whether a boundary name counts toward the 50-state goal.
    func isState(_ name: String) -> Bool { !Self.nonStateNames.contains(name) }

    /// Returns the boundary name containing `coordinate`, or nil if none (e.g. outside the US).
    func region(containing coordinate: CLLocationCoordinate2D) -> String? {
        let point = MKMapPoint(coordinate)
        for boundary in boundaries where boundary.boundingMapRect.contains(point) {
            for polygon in boundary.polygons where polygon.contains(point) {
                return boundary.name
            }
        }
        return nil
    }

    // MARK: Loading

    private static func load() -> [StateBoundary] {
        // Primary: a Data asset in the compiled asset catalog. Asset catalogs are always
        // built into the app (that's how the icon ships), so this is reliable — unlike a loose
        // resource file, which wasn't making it into the bundle and left the map empty.
        // Fallback: the loose bundled file, in case the asset isn't found.
        let data: Data
        if let asset = NSDataAsset(name: "USStates") {
            data = asset.data
        } else if let url = Bundle.main.url(forResource: "us-states", withExtension: "json"),
                  let fileData = try? Data(contentsOf: url) {
            data = fileData
        } else {
            return []
        }
        guard let objects = try? MKGeoJSONDecoder().decode(data) else {
            return []
        }
        var result: [StateBoundary] = []
        for case let feature as MKGeoJSONFeature in objects {
            guard let name = name(of: feature) else { continue }
            var polygons: [MKPolygon] = []
            for geometry in feature.geometry {
                if let polygon = geometry as? MKPolygon {
                    polygons.append(polygon)
                } else if let multi = geometry as? MKMultiPolygon {
                    polygons.append(contentsOf: multi.polygons)
                }
            }
            guard !polygons.isEmpty else { continue }
            let rect = polygons.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            result.append(StateBoundary(name: name, polygons: polygons, boundingMapRect: rect))
        }
        return result
    }

    private static func name(of feature: MKGeoJSONFeature) -> String? {
        guard let data = feature.properties,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["name"] as? String
    }
}

// MARK: - Point-in-polygon

extension MKPolygon {

    /// Ray-casting containment test in projected map space, accounting for holes.
    func contains(_ point: MKMapPoint) -> Bool {
        guard boundingMapRect.contains(point) else { return false }
        guard MKPolygon.ring(points(), pointCount, contains: point) else { return false }
        if let interiors = interiorPolygons {
            for hole in interiors where hole.contains(point) { return false }
        }
        return true
    }

    private static func ring(_ pts: UnsafePointer<MKMapPoint>, _ count: Int, contains p: MKMapPoint) -> Bool {
        guard count > 2 else { return false }
        var inside = false
        var j = count - 1
        for i in 0..<count {
            let a = pts[i], b = pts[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
