import Foundation
import CoreLocation

/// Turns the bytes of a single activity file into normalized `ImportedActivity` values. One
/// conformer per format (GPX, TCX, and later FIT); the file-import service picks the right one
/// by extension. Parsers are provider-agnostic — a Nike TCX and a Garmin TCX use the same
/// `TCXParser`; "Nike" is just the creator name detected inside the file.
///
/// Not actor-isolated: parsing is pure and can run off the main actor. A file may contain
/// several activities (a multi-track GPX, a multi-activity TCX), so `parse` returns an array.
protocol ActivityFileParser {
    /// Lowercased extensions this parser handles, e.g. `["gpx"]`.
    static var fileExtensions: [String] { get }
    func parse(data: Data, fileName: String) throws -> [ImportedActivity]
}

enum ActivityFileError: Error, LocalizedError {
    case unsupportedFormat(String)
    case empty
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "Unsupported file type: .\(ext)"
        case .empty: return "No activities found in the file"
        case .corrupt(let why): return "Couldn't read the file: \(why)"
        }
    }
}

/// Dispatches a file to the parser that handles its extension. FIT is recognised but not yet
/// parsed (Phase 3); it surfaces a clear "unsupported" rather than failing silently.
enum ActivityFileParsing {

    /// Extensions the import UI should accept, including archives handled elsewhere.
    static let supportedExtensions = ["gpx", "tcx"]

    static func parser(forExtension ext: String) -> ActivityFileParser? {
        switch ext.lowercased() {
        case "gpx": return GPXParser()
        case "tcx": return TCXParser()
        default: return nil
        }
    }

    static func parse(data: Data, fileName: String) throws -> [ImportedActivity] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let parser = parser(forExtension: ext) else {
            throw ActivityFileError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
        }
        return try parser.parse(data: data, fileName: fileName)
    }
}

// MARK: - Shared parsing helpers

/// Parses the ISO-8601 timestamps used by GPX/TCX, with and without fractional seconds.
enum ActivityDate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

/// Geometry math shared by the file parsers: track distance and elevation gain from the raw
/// point streams, since neither is reliably present in the file's summary fields.
enum RouteMetrics {

    /// Total great-circle distance along the coordinate stream, in metres.
    static func distance(of coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var total = 0.0
        var previous = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        for coordinate in coordinates.dropFirst() {
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            total += current.distance(from: previous)
            previous = current
        }
        return total
    }

    /// Cumulative ascent from an elevation stream (metres), summing only positive deltas.
    /// A small threshold ignores GPS altitude jitter.
    static func elevationGain(of elevations: [Double]) -> Double {
        guard elevations.count > 1 else { return 0 }
        var gain = 0.0
        for i in 1..<elevations.count {
            let delta = elevations[i] - elevations[i - 1]
            if delta > 0.5 { gain += delta }
        }
        return gain
    }
}
