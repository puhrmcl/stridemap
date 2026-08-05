import Foundation

/// Builds a single multi-track GPX 1.1 file from the user's runs. Because Strava's
/// summary polyline carries only latitude/longitude, exported tracks contain positions
/// (and per-run start time) but not per-point elevation or timestamps.
enum GPXExporter {

    static func makeGPX(from runs: [Run]) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(#"<gpx version="1.1" creator="StrideMap" xmlns="http://www.topografix.com/GPX/1/1">"#)
        lines.append("  <metadata><name>StrideMap Export</name><time>\(iso.string(from: Date()))</time></metadata>")

        for run in runs where run.hasRoute {
            let coords = run.coordinates
            guard coords.count > 1 else { continue }
            lines.append("  <trk>")
            lines.append("    <name>\(escape(run.name))</name>")
            lines.append("    <time>\(iso.string(from: run.startDate))</time>")
            lines.append("    <trkseg>")
            for c in coords {
                lines.append(String(format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\"></trkpt>", c.latitude, c.longitude))
            }
            lines.append("    </trkseg>")
            lines.append("  </trk>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }

    /// Writes the GPX to a temporary file and returns its URL, suitable for `ShareLink`.
    static func writeTemporaryFile(for runs: [Run]) throws -> URL {
        let gpx = makeGPX(from: runs)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrideMap-\(Int(Date().timeIntervalSince1970)).gpx")
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
