import Foundation
import CoreLocation

/// Parses TCX (Training Center XML) files — the format Nike Run Club and many watches export
/// — into `ImportedActivity`. Each `<Activity>` becomes one activity; lap summaries provide
/// distance, moving time, calories and heart rate, while the trackpoint stream provides the
/// route and elevation. The `<Id>` element is a stable identifier, so re-importing the same
/// export is idempotent.
///
/// Context matters in TCX: `DistanceMeters` and `Value` (heart rate) appear at several depths,
/// so the delegate tracks the element stack and reads each only under the right parent.
struct TCXParser: ActivityFileParser {
    static let fileExtensions = ["tcx"]

    func parse(data: Data, fileName: String) throws -> [ImportedActivity] {
        guard !data.isEmpty else { throw ActivityFileError.empty }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ActivityFileError.corrupt(parser.parserError?.localizedDescription ?? "invalid TCX")
        }
        let activities = delegate.activities.compactMap { $0.makeActivity() }
        guard !activities.isEmpty else { throw ActivityFileError.empty }
        return activities
    }

    // MARK: SAX delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        var activities: [Activity] = []

        private var stack: [String] = []
        private var text = ""
        private var current: Activity?
        private var point: Activity.Point?

        /// The element enclosing the one that just closed (e.g. the parent of a `<Value>`).
        private var parent: String? { stack.count >= 2 ? stack[stack.count - 2] : nil }

        private func local(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let name = local(elementName)
            stack.append(name)
            text = ""
            switch name {
            case "Activity":
                let activity = Activity()
                activity.sport = attributeDict["Sport"]
                current = activity
            case "Lap":
                if current?.startFromLap == nil { current?.startFromLap = ActivityDate.parse(attributeDict["StartTime"]) }
            case "Trackpoint":
                point = Activity.Point()
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
            let parentName = parent
            defer { if stack.last == name { stack.removeLast() }; text = "" }

            switch name {
            case "Id":
                if parentName == "Activity", current?.id == nil { current?.id = value }
            case "TotalTimeSeconds":
                if parentName == "Lap", let v = Double(value) { current?.totalTime += v }
            case "DistanceMeters":
                if parentName == "Lap", let v = Double(value) { current?.totalDistance += v }
            case "Calories":
                if parentName == "Lap", let v = Double(value) { current?.calories += v }
            case "MaximumSpeed":
                // Lap-level top speed (m/s). Keep the fastest across the activity's laps.
                if parentName == "Lap", let v = Double(value) {
                    current?.maxSpeed = max(current?.maxSpeed ?? 0, v)
                }
            case "Value":
                guard let v = Double(value) else { break }
                switch parentName {
                case "AverageHeartRateBpm": current?.lapAvgHR.append(v)
                case "MaximumHeartRateBpm": current?.lapMaxHR.append(v)
                case "HeartRateBpm": point?.heartRate = v   // trackpoint-level HR
                default: break
                }
            case "LatitudeDegrees":
                point?.latitude = Double(value)
            case "LongitudeDegrees":
                point?.longitude = Double(value)
            case "AltitudeMeters":
                if point != nil { point?.elevation = Double(value) }
            case "Time":
                if point != nil { point?.time = ActivityDate.parse(value) }
            case "Name":
                if parentName == "Creator" || parentName == "Author" { current?.creatorName = value }
            case "Notes":
                // TCX carries a free-text note per activity (Garmin and others export it here).
                if parentName == "Activity", !value.isEmpty { current?.notes = value }
            case "Trackpoint":
                if let point { current?.points.append(point) }
                point = nil
            case "Activity":
                if let current { activities.append(current) }
                current = nil
            default:
                break
            }
        }
    }

    // MARK: Accumulator

    private final class Activity {
        struct Point {
            var latitude: Double? = nil
            var longitude: Double? = nil
            var elevation: Double? = nil
            var time: Date? = nil
            var heartRate: Double? = nil
            var coordinate: CLLocationCoordinate2D? {
                guard let latitude, let longitude else { return nil }
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        var sport: String?
        var id: String?
        var creatorName: String?
        var notes: String?
        var startFromLap: Date?
        var totalTime = 0.0
        var totalDistance = 0.0
        var calories = 0.0
        var maxSpeed = 0.0
        var lapAvgHR: [Double] = []
        var lapMaxHR: [Double] = []
        var points: [Point] = []

        func makeActivity() -> ImportedActivity? {
            let coordinates = points.compactMap(\.coordinate)
            let times = points.compactMap(\.time)
            let start = ActivityDate.parse(id) ?? startFromLap ?? times.first
            guard let start else { return nil }

            let elapsed = (times.first != nil && times.last != nil)
                ? Int(times.last!.timeIntervalSince(times.first!)) : 0
            let distance = totalDistance > 0 ? totalDistance : RouteMetrics.distance(of: coordinates)
            let moving = totalTime > 0 ? Int(totalTime) : elapsed
            let origin = ActivitySource.detect(fromSourceName: creatorName)
            let idBase = id ?? "\(ISO8601DateFormatter().string(from: start)):\(Int(distance.rounded()))"

            var activity = ImportedActivity(
                provider: origin,
                externalID: "tcx:\(idBase)",
                startDate: start,
                distance: distance,
                movingTime: moving,
                elapsedTime: max(elapsed, moving),
                coordinates: coordinates
            )
            // Only claim an origin app when the file actually named its creator.
            activity.originApp = origin == .unknown ? nil : origin
            activity.importMethod = .tcxFile
            activity.activityType = ActivityType.parse(sport)
            activity.sportType = sport ?? "Run"
            activity.notes = notes
            let elevations = points.compactMap(\.elevation)
            activity.elevationGain = RouteMetrics.elevationGain(of: elevations)
            activity.elevationSeries = elevations
            if calories > 0 { activity.activeEnergy = calories }
            if maxSpeed > 0 { activity.maxSpeed = maxSpeed }
            if !lapAvgHR.isEmpty {
                activity.averageHeartRate = lapAvgHR.reduce(0, +) / Double(lapAvgHR.count)
            } else {
                let hr = points.compactMap(\.heartRate)
                if !hr.isEmpty { activity.averageHeartRate = hr.reduce(0, +) / Double(hr.count) }
            }
            activity.maxHeartRate = lapMaxHR.max() ?? points.compactMap(\.heartRate).max()
            return activity
        }
    }
}
