import Foundation
import CoreLocation

/// Decodes Google's Encoded Polyline Algorithm Format, which Strava uses for its
/// `summary_polyline` field.
///
/// Reference: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
enum PolylineDecoder {

    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }

        var coordinates: [CLLocationCoordinate2D] = []
        let bytes = Array(encoded.utf8)
        var index = 0
        var lat = 0
        var lon = 0

        while index < bytes.count {
            guard let latDelta = nextValue(bytes, &index) else { break }
            lat += latDelta
            guard let lonDelta = nextValue(bytes, &index) else { break }
            lon += lonDelta

            coordinates.append(
                CLLocationCoordinate2D(
                    latitude: Double(lat) * 1e-5,
                    longitude: Double(lon) * 1e-5
                )
            )
        }
        return coordinates
    }

    /// Reads one varint-encoded, zig-zag signed value from the byte stream.
    private static func nextValue(_ bytes: [UInt8], _ index: inout Int) -> Int? {
        var result = 0
        var shift = 0
        var byte: Int

        repeat {
            guard index < bytes.count else { return nil }
            byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20

        // Zig-zag decode.
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }

    // MARK: Encoding

    /// Encodes coordinates into Google's polyline format, so routes coming from providers
    /// that give raw GPS (e.g. HealthKit workout routes) can be stored the same way as
    /// Strava's `summary_polyline`.
    static func encode(_ coordinates: [CLLocationCoordinate2D]) -> String {
        var result = ""
        var previousLat = 0
        var previousLon = 0

        for coordinate in coordinates {
            let lat = Int((coordinate.latitude * 1e5).rounded())
            let lon = Int((coordinate.longitude * 1e5).rounded())
            result += encodeValue(lat - previousLat)
            result += encodeValue(lon - previousLon)
            previousLat = lat
            previousLon = lon
        }
        return result
    }

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? (value << 1) ^ (~0) : (value << 1)
        var output = ""
        while v >= 0x20 {
            let chunk = (0x20 | (v & 0x1F)) + 63
            output.append(Character(UnicodeScalar(chunk)!))
            v >>= 5
        }
        output.append(Character(UnicodeScalar(v + 63)!))
        return output
    }
}

/// Small geometry helper shared by importers.
enum RouteGeometry {
    struct BoundingBox {
        var minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
    }

    static func boundingBox(
        of coordinates: [CLLocationCoordinate2D],
        fallbackStart: CLLocationCoordinate2D? = nil
    ) -> BoundingBox {
        if coordinates.isEmpty {
            let lat = fallbackStart?.latitude ?? 0
            let lon = fallbackStart?.longitude ?? 0
            return BoundingBox(minLat: lat, maxLat: lat, minLon: lon, maxLon: lon)
        }
        var box = BoundingBox(
            minLat: coordinates[0].latitude, maxLat: coordinates[0].latitude,
            minLon: coordinates[0].longitude, maxLon: coordinates[0].longitude
        )
        for c in coordinates {
            box.minLat = min(box.minLat, c.latitude); box.maxLat = max(box.maxLat, c.latitude)
            box.minLon = min(box.minLon, c.longitude); box.maxLon = max(box.maxLon, c.longitude)
        }
        return box
    }
}
