import Foundation

/// The `activities.csv` that sits beside the route files in a Strava bulk export.
///
/// Without it a backfilled history arrives anonymous: two thousand entries called "Morning Run",
/// no race flags, no gear, no descriptions — which is most of what makes the Timeline and the
/// books worth looking at. The CSV carries all of it, and the export is something the athlete
/// already owns, so this is the Strava API's metadata without the Strava API's athlete cap.
///
/// Columns are located by header name rather than position: the export's shape has changed
/// between versions and differs by account locale, and a positional reader silently maps
/// descriptions into gear when a column is inserted.
struct StravaExportIndex {

    struct Entry {
        var name: String?
        var type: String?
        var description: String?
        var gear: String?
        var isCommute: Bool?
    }

    /// Keyed by the route file's own name, lowercased — the CSV's `Filename` column holds a path
    /// like `activities/4821.gpx.gz`, while the archive reader knows the entry by its basename.
    private(set) var entries: [String: Entry] = [:]

    var isEmpty: Bool { entries.isEmpty }

    /// The file in an export that this reads. Matched on the basename so it is found whether it
    /// sits at the archive root or inside an `export_12345/` folder.
    static func isIndexFile(_ name: String) -> Bool {
        (name as NSString).lastPathComponent.lowercased() == "activities.csv"
    }

    init(csv: String) {
        let rows = CSVRows.parse(csv)
        guard let header = rows.first else { return }

        let columns = Dictionary(
            header.enumerated().map { ($0.element.trimmed.lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        // The filename column is the join key; with no way to match a row to a file the rest of
        // the table is unusable, so nothing is indexed rather than guessed at.
        guard let fileColumn = columns["filename"] else { return }

        func field(_ row: [String], _ key: String) -> String? {
            guard let index = columns[key], index < row.count else { return nil }
            let value = row[index].trimmed
            return value.isEmpty ? nil : value
        }

        for row in rows.dropFirst() {
            guard fileColumn < row.count else { continue }
            let path = row[fileColumn].trimmed
            guard !path.isEmpty else { continue }
            let key = (path as NSString).lastPathComponent.lowercased()

            let commute = field(row, "commute").map {
                let value = $0.lowercased()
                return value == "true" || value == "1" || value == "yes"
            }
            entries[key] = Entry(name: field(row, "activity name"),
                                 type: field(row, "activity type"),
                                 description: field(row, "activity description"),
                                 gear: field(row, "activity gear"),
                                 isCommute: commute)
        }
    }

    /// Applies what the table knows to an activity parsed from the matching route file.
    ///
    /// Only fills gaps: a value the file itself carried is better evidence than the export's
    /// summary of it, and a GPX that named its track should keep that name.
    func enrich(_ activity: inout ImportedActivity, fileName: String) {
        guard let entry = entries[(fileName as NSString).lastPathComponent.lowercased()] else {
            return
        }
        if activity.name == nil || activity.name?.isEmpty == true { activity.name = entry.name }
        if activity.notes == nil { activity.notes = entry.description }
        if activity.gear == nil { activity.gear = entry.gear }
        if activity.isCommute == nil { activity.isCommute = entry.isCommute }
        if let type = entry.type {
            if activity.sportType == nil { activity.sportType = type }
            // Strava's own label is a better source for the kind than a GPX's generic track type,
            // which is how a kayak outing imports as a run.
            activity.activityType = ActivityType.parse(type)
        }
    }
}

/// A CSV reader that handles the parts of RFC 4180 a real export actually uses: quoted fields,
/// commas and newlines inside quotes, and `""` as an escaped quote.
///
/// A split on commas would be wrong on the first activity anyone has named "Long run, with Dan",
/// and wrong in a way that shifts every later column by one.
enum CSVRows {

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            // A trailing newline would otherwise add a row of one empty field.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"": quoted = true
            case ",":  endField()
            case "\n": endRow()
            case "\r": break                    // CRLF: the \n that follows ends the row
            default:   field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}

/// Deliberately file-scoped: a bare `trimmed` on every String in the app is a wide thing to add
/// for one reader's convenience.
private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
