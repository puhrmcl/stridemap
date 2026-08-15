import Foundation
import MapKit

/// World country boundary geometry, embedded directly in the binary (`WorldCountryBoundaryData`)
/// rather than loaded from a bundled resource — the same approach as `USStateBoundaries`, which
/// proved that loose files / asset catalogs don't reliably reach the app. Powers the "countries
/// you've run in" choropleth and attributes each run to a country by point-in-polygon, so it
/// works offline and even for runs whose reverse-geocoded country name never resolved.
///
/// Immutable after `init`, so it's safe to touch from map delegate callbacks and any actor —
/// hence `@unchecked Sendable`.
final class WorldCountryBoundaries: @unchecked Sendable {

    static let shared = WorldCountryBoundaries()

    struct CountryBoundary {
        let name: String
        let polygons: [MKPolygon]
        let boundingMapRect: MKMapRect
    }

    /// All boundaries. Empty only if the embedded data can't be decoded (shouldn't happen) — the
    /// feature degrades to an empty map rather than crashing.
    let boundaries: [CountryBoundary]

    private init() {
        boundaries = WorldCountryBoundaries.load()
    }

    /// The bounding map rect of a named country, for framing a jump-to-country zoom.
    func boundingMapRect(for name: String) -> MKMapRect? {
        boundaries.first { $0.name == name }?.boundingMapRect
    }

    /// The country name containing `coordinate`, or nil if none (e.g. mid-ocean).
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

    /// One country as stored in the embedded blob: name `n`, and exterior rings `r`, each a flat
    /// array of [lon, lat, lon, lat, …].
    private struct RawCountry: Decodable {
        let n: String
        let r: [[Double]]
    }

    private static func load() -> [CountryBoundary] {
        guard let data = Data(base64Encoded: WorldCountryBoundaryData.base64),
              let countries = try? JSONDecoder().decode([RawCountry].self, from: data) else {
            return []
        }
        var result: [CountryBoundary] = []
        for country in countries {
            var polygons: [MKPolygon] = []
            for flat in country.r where flat.count >= 6 {
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
            result.append(CountryBoundary(name: country.n, polygons: polygons, boundingMapRect: rect))
        }
        return result
    }
}
