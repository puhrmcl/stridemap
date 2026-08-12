import Foundation
import MapKit

/// US state (+ DC / territories) boundary geometry, embedded directly in the binary
/// (`USStateBoundaryData`) rather than loaded from a bundled resource — the loose file and
/// the asset catalog both failed to reach the app, leaving the States map empty. Powers the
/// "states you've run in" map and attributes each run to a state by point-in-polygon —
/// independent of geocoding, so it works offline and even for runs whose place names never
/// resolved.
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

    /// All boundaries. Built from embedded data, so this is only empty if that data can't be
    /// decoded (shouldn't happen) — the feature degrades to an empty map rather than crashing.
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

    /// One state as stored in the embedded blob: name `n`, and rings `r`, each a flat array of
    /// [lon, lat, lon, lat, …] exterior-ring coordinates.
    private struct RawState: Decodable {
        let n: String
        let r: [[Double]]
    }

    /// Decodes the embedded base64 → JSON → `MKPolygon`s. No bundle/resource dependency, so it
    /// works regardless of how the app was built.
    private static func load() -> [StateBoundary] {
        guard let data = Data(base64Encoded: USStateBoundaryData.base64),
              let states = try? JSONDecoder().decode([RawState].self, from: data) else {
            return []
        }
        var result: [StateBoundary] = []
        for state in states {
            var polygons: [MKPolygon] = []
            for flat in state.r where flat.count >= 6 {
                var coordinates: [CLLocationCoordinate2D] = []
                coordinates.reserveCapacity(flat.count / 2)
                var i = 0
                while i + 1 < flat.count {
                    coordinates.append(CLLocationCoordinate2D(latitude: flat[i + 1], longitude: flat[i]))
                    i += 2
                }
                guard coordinates.count >= 3 else { continue }
                polygons.append(MKPolygon(coordinates: coordinates, count: coordinates.count))
            }
            guard !polygons.isEmpty else { continue }
            let rect = polygons.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
            result.append(StateBoundary(name: state.n, polygons: polygons, boundingMapRect: rect))
        }
        return result
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
