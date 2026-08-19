import Foundation
import CoreLocation

/// Parses Nike Run Club activity JSON — the format inside a Nike "Get a copy of your data"
/// export (each run is a JSON file, not TCX/GPX). Latitude and longitude arrive as separate
/// time-stamped metric streams, paired here by timestamp into a route.
///
/// Defensive by design: it self-validates (returns nothing for JSON that isn't a Nike
/// activity), tolerates missing fields, and — because Etch's enrichment can attach GPS later
/// from another source — still imports a run with only date/distance/duration when the file
/// has no location stream.
///
/// NOTE: validated against the documented NRC export schema; confirm against a real export
/// before relying on the finer fields (calories, per-sample HR).
struct NikeActivityParser: ActivityFileParser {
    static let fileExtensions = ["json"]

    func parse(data: Data, fileName: String) throws -> [ImportedActivity] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        // A Nike activity always has a start time and metric streams; bail on anything else so
        // this never mis-claims an unrelated JSON file.
        guard let startMs = num(root["start_epoch_ms"]) else { return [] }
        let metrics = root["metrics"] as? [[String: Any]] ?? []
        guard root["type"] != nil || !metrics.isEmpty else { return [] }

        let start = Date(timeIntervalSince1970: startMs / 1000)
        let endMs = num(root["end_epoch_ms"])
        let activeMs = num(root["active_duration_ms"])

        // Metric streams (each a list of { start_epoch_ms, value }).
        let lat = samples(named: "latitude", in: metrics)
        let lon = samples(named: "longitude", in: metrics)
        let elevation = samples(named: "elevation", in: metrics).map(\.value)
        let heartRates = samples(named: "heart_rate", in: metrics).map(\.value)

        let coordinates = pairCoordinates(latitude: lat, longitude: lon)

        // Distance: Nike summaries report total kilometres; fall back to the track length.
        let summaryKm = summaryValue(root, metric: "distance")
        var distance = (summaryKm ?? 0) * 1000
        if distance <= 0 { distance = RouteMetrics.distance(of: coordinates) }

        let elapsed = (endMs.map { Int(($0 - startMs) / 1000) }) ?? 0
        let moving = activeMs.map { Int($0 / 1000) } ?? elapsed

        let id = root["id"] as? String
        let idBase = id ?? "\(Int(startMs)):\(Int(distance.rounded()))"

        var activity = ImportedActivity(
            provider: .nikeRunClub,
            externalID: "nike:\(idBase)",
            startDate: start,
            distance: distance,
            movingTime: moving,
            elapsedTime: max(elapsed, moving),
            coordinates: coordinates
        )
        activity.originApp = .nikeRunClub
        activity.importMethod = .zipArchive
        activity.activityType = ActivityType.parse(root["type"] as? String)
        activity.sportType = (root["type"] as? String)?.capitalized ?? "Run"
        activity.name = activityName(root)
        activity.notes = activityNotes(root)
        activity.elevationGain = RouteMetrics.elevationGain(of: elevation)
        activity.elevationSeries = elevation
        if let calories = summaryValue(root, metric: "calories"), calories > 0 {
            activity.activeEnergy = calories
        }
        if let meanHR = summaryValue(root, metric: "heart_rate"), meanHR > 0 {
            activity.averageHeartRate = meanHR
        } else if !heartRates.isEmpty {
            activity.averageHeartRate = heartRates.reduce(0, +) / Double(heartRates.count)
        }
        activity.maxHeartRate = heartRates.max()
        return [activity]
    }

    // MARK: Metric helpers

    private struct Sample { let time: Double; let value: Double }

    /// The `values` array of the named metric, mapped to (timestamp, value) pairs.
    private func samples(named name: String, in metrics: [[String: Any]]) -> [Sample] {
        guard let metric = metrics.first(where: { ($0["type"] as? String) == name }),
              let values = metric["values"] as? [[String: Any]] else { return [] }
        return values.compactMap { entry in
            guard let value = num(entry["value"]) else { return nil }
            let time = num(entry["start_epoch_ms"]) ?? 0
            return Sample(time: time, value: value)
        }
    }

    /// Pairs latitude and longitude samples by timestamp, preserving chronological order.
    private func pairCoordinates(latitude: [Sample], longitude: [Sample]) -> [CLLocationCoordinate2D] {
        guard !latitude.isEmpty, !longitude.isEmpty else { return [] }
        // Index longitudes by their (integer-millisecond) timestamp for O(1) pairing.
        var lonByTime: [Int: Double] = [:]
        lonByTime.reserveCapacity(longitude.count)
        for sample in longitude { lonByTime[Int(sample.time)] = sample.value }

        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(latitude.count)
        for sample in latitude {
            if let lon = lonByTime[Int(sample.time)] {
                coordinates.append(CLLocationCoordinate2D(latitude: sample.value, longitude: lon))
            }
        }
        // If timestamps didn't line up but the streams are the same length, pair by index.
        if coordinates.isEmpty, latitude.count == longitude.count {
            for i in 0..<latitude.count {
                coordinates.append(CLLocationCoordinate2D(latitude: latitude[i].value, longitude: longitude[i].value))
            }
        }
        return coordinates
    }

    /// A run's total for a summary metric (distance in km, calories, mean heart rate, …).
    private func summaryValue(_ root: [String: Any], metric: String) -> Double? {
        guard let summaries = root["summaries"] as? [[String: Any]] else { return nil }
        let matches = summaries.filter { ($0["metric"] as? String) == metric }
        // Prefer an explicit total/mean summary when several are present.
        let preferred = matches.first { ["total", "mean", "average"].contains($0["summary"] as? String ?? "") }
        return num((preferred ?? matches.first)?["value"])
    }

    private func activityName(_ root: [String: Any]) -> String? {
        if let tags = root["tags"] as? [String: Any], let name = tags["com.nike.name"] as? String, !name.isEmpty {
            return name
        }
        return (root["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A run's free-text note, if the NRC export carries one. Nike stores per-run metadata as
    /// `com.nike.*` tags (that's where the name lives); the note key isn't documented, so this
    /// checks the most plausible tag keys and a couple of top-level fields. A no-op when absent —
    /// confirm the real key against an actual export to be certain.
    private func activityNotes(_ root: [String: Any]) -> String? {
        func nonEmpty(_ any: Any?) -> String? {
            guard let s = any as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return s
        }
        if let tags = root["tags"] as? [String: Any] {
            for key in ["com.nike.note", "com.nike.notes", "com.nike.running.note", "note", "notes"] {
                if let s = nonEmpty(tags[key]) { return s }
            }
        }
        for key in ["note", "notes", "description"] {
            if let s = nonEmpty(root[key]) { return s }
        }
        return nil
    }

    /// JSON numbers decode as `NSNumber`; also accept numeric strings just in case.
    private func num(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
