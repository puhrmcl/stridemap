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
}
