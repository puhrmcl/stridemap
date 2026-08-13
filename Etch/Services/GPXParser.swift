import Foundation
import CoreLocation

/// Parses GPX 1.1 track files (the most universal fitness export) into `ImportedActivity`.
/// Each `<trk>` becomes one activity; distance and elevation gain are computed from the point
/// stream, since GPX carries no summary totals. Heart rate is read from the common
/// `gpxtpx:hr` / `hr` track-point extension when present.
///
/// Streaming SAX (`XMLParser`) so even a long track parses with flat memory.
struct GPXParser: ActivityFileParser {
    static let fileExtensions = ["gpx"]

    func parse(data: Data, fileName: String) throws -> [ImportedActivity] {
        guard !data.isEmpty else { throw ActivityFileError.empty }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ActivityFileError.corrupt(parser.parserError?.localizedDescription ?? "invalid GPX")
        }
        let activities = delegate.tracks.compactMap { $0.makeActivity(creator: delegate.creator) }
        guard !activities.isEmpty else { throw ActivityFileError.empty }
        return activities
    }

    // MARK: SAX delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        var creator: String?
        var tracks: [Track] = []

        private var stack: [String] = []
        private var text = ""
        private var current: Track?
        private var point: Track.Point?
        private var metadataTime: Date?

        private func local(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let name = local(elementName)
            stack.append(name)
            text = ""
            switch name {
            case "gpx":
                creator = attributeDict["creator"]
            case "trk":
                current = Track()
            case "trkpt":
                if let latS = attributeDict["lat"], let lonS = attributeDict["lon"],
                   let lat = Double(latS), let lon = Double(lonS) {
                    point = Track.Point(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let name = local(elementName)
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { if stack.last == name { stack.removeLast() }; text = "" }

            switch name {
            case "trkpt":
                if let point { current?.points.append(point) }
                point = nil
            case "ele":
                if point != nil { point?.elevation = Double(value) }
            case "time":
                if point != nil { point?.time = ActivityDate.parse(value) }
                else if stack.dropLast().last == "metadata" { metadataTime = ActivityDate.parse(value) }
            case "hr":
                if point != nil { point?.heartRate = Double(value) }
            case "name":
                if stack.dropLast().last == "trk" { current?.name = value.isEmpty ? nil : value }
            case "type":
                if stack.dropLast().last == "trk" { current?.type = value.isEmpty ? nil : value }
            case "trk":
                if let current { current.metadataTime = metadataTime; tracks.append(current) }
                current = nil
            default:
                break
            }
        }
    }

    // MARK: Accumulator

    private final class Track {
        struct Point {
            var coordinate: CLLocationCoordinate2D
            var elevation: Double? = nil
            var time: Date? = nil
            var heartRate: Double? = nil
        }
        var name: String?
        var type: String?
        var points: [Point] = []
        var metadataTime: Date?

        func makeActivity(creator: String?) -> ImportedActivity? {
            let coordinates = points.map(\.coordinate)
            let times = points.compactMap(\.time)
            guard !coordinates.isEmpty || metadataTime != nil else { return nil }

            let start = times.first ?? metadataTime ?? Date()
            let elapsed = (times.first != nil && times.last != nil)
                ? Int(times.last!.timeIntervalSince(times.first!)) : 0
            let distance = RouteMetrics.distance(of: coordinates)
            let elevations = points.compactMap(\.elevation)
            let heartRates = points.compactMap(\.heartRate)

            let origin = ActivitySource.detect(fromSourceName: creator)
            var activity = ImportedActivity(
                provider: origin,
                externalID: "gpx:\(ISO8601DateFormatter().string(from: start)):\(Int(distance.rounded()))",
                startDate: start,
                distance: distance,
                movingTime: elapsed,
                elapsedTime: elapsed,
                coordinates: coordinates
            )
            // Only claim an origin app when the file actually named its creator.
            activity.originApp = origin == .unknown ? nil : origin
            activity.importMethod = .gpxFile
            activity.activityType = ActivityType.parse(type)
            activity.sportType = type ?? "Run"
            activity.name = name
            activity.elevationGain = RouteMetrics.elevationGain(of: elevations)
            if !heartRates.isEmpty {
                activity.averageHeartRate = heartRates.reduce(0, +) / Double(heartRates.count)
                activity.maxHeartRate = heartRates.max()
            }
            return activity
        }
    }
}
