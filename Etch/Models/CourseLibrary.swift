import Foundation
import CoreLocation

/// Course geometry that ships as *files* rather than as code.
///
/// A route file dropped into `Etch/Resources/Courses` becomes that event's course on the next
/// build — no Swift change, and no Xcode project change either, because the app target is a
/// synchronized folder that picks up whatever is on disk. That is the whole point: sourcing
/// official courses for a hundred events is a research errand, not a programming one, and it
/// shouldn't need a programmer to land each one. Anyone who can commit a file can add a course,
/// including from GitHub's web editor on a phone.
///
/// Naming:
/// - `<event-id>.gpx` — the course for every year.
/// - `<event-id>-2025.gpx` — overrides that one year, for a race that reroutes.
///
/// `.tcx` and `.fit` work too; the same parsers that read a participant's own export read these.
enum CourseLibrary {

    struct Course {
        var coordinates: [CLLocationCoordinate2D]
        var elevations: [Double]
        /// Measured from the file's own points, which is usually a little over the official
        /// distance — a traced line is not a certified course measurement.
        var distance: Double
    }

    /// The subdirectory in the repository. Synchronized folders flatten resources into the
    /// bundle root, so lookup tries both that and the subdirectory.
    static let folder = "Courses"
    static let fileExtensions = ["gpx", "tcx", "fit"]

    /// The bundled course for an event, preferring a file for that specific year.
    static func course(for eventID: String, year: Int? = nil) -> Course? {
        if let year, let dated = load("\(eventID)-\(year)") { return dated }
        return load(eventID)
    }

    static func hasCourse(for eventID: String) -> Bool { load(eventID) != nil }

    /// Every event id the bundle carries a course for — used by the catalog to report coverage.
    static func bundledEventIDs() -> Set<String> {
        var ids: Set<String> = []
        for ext in fileExtensions {
            let paths = Bundle.main.paths(forResourcesOfType: ext, inDirectory: folder)
                + Bundle.main.paths(forResourcesOfType: ext, inDirectory: nil)
            for path in paths {
                var name = (path as NSString).lastPathComponent
                name = (name as NSString).deletingPathExtension
                // "boston-2025" covers "boston" too.
                if let dash = name.range(of: "-", options: .backwards),
                   Int(name[dash.upperBound...]) != nil {
                    name = String(name[..<dash.lowerBound])
                }
                ids.insert(name)
            }
        }
        return ids
    }

    // MARK: Loading

    private static let lock = NSLock()
    /// Nested optional on purpose: the outer says "we've looked", the inner "we found something".
    /// A miss is cached too, so a hundred event rows don't each hit the filesystem.
    private nonisolated(unsafe) static var cache: [String: Course?] = [:]

    private static func load(_ name: String) -> Course? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        let course = read(name)
        cache[name] = course
        return course
    }

    private static func read(_ name: String) -> Course? {
        for ext in fileExtensions {
            let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: folder)
                ?? Bundle.main.url(forResource: name, withExtension: ext)
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let parsed = try? ActivityFileParsing.parse(data: data, fileName: "\(name).\(ext)"),
                  // A course file occasionally carries several tracks; the longest is the course.
                  let best = parsed.filter({ !$0.coordinates.isEmpty })
                      .max(by: { $0.coordinates.count < $1.coordinates.count })
            else { continue }
            return Course(coordinates: best.coordinates,
                          elevations: best.elevationSeries,
                          distance: best.distance)
        }
        return nil
    }
}
