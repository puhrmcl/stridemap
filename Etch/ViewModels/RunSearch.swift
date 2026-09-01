import Foundation

/// Matches a run against a free-text query across all of its detail attributes — name, notes,
/// place, date, and the *formatted* metrics (distance, time, pace, elevation, activity type). So
/// typing "3.2" finds 3.2-mile runs, "27:" finds ~27-minute runs, "hike" finds hikes, and so on.
enum RunSearch {

    /// True when `query` (already lowercased/trimmed) appears anywhere in the run's searchable text.
    static func matches(_ run: Run, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return haystack(for: run).contains(query)
    }

    /// Every searchable attribute of a run, joined and lowercased. Metrics are included both as the
    /// user sees them (e.g. "3.2 mi", "27:24", "8:34 /mi") and as a couple of extra precisions so
    /// partial numeric queries still match.
    static func haystack(for run: Run) -> String {
        var parts: [String] = [run.name]
        if let notes = run.notes { parts.append(notes) }
        if let city = run.city { parts.append(city) }
        if let state = run.state { parts.append(state) }
        if let country = run.country { parts.append(country) }

        parts.append(Format.date(run.startDate))

        // Distance at 1 and 2 decimals so "3.2" and "3.25" both hit.
        parts.append(Format.distance(run.distance, decimals: 1))
        parts.append(Format.distance(run.distance, decimals: 2))

        parts.append(Format.duration(run.movingTime))

        if run.distance > 0 {
            let secondsPerKm = Double(run.movingTime) / (run.distance / 1000)
            parts.append(Format.pace(secondsPerKm: secondsPerKm))
        }
        if run.elevationGain > 0 {
            parts.append(Format.elevationGain(run.elevationGain))
        }

        parts.append(run.activityType.detailLabel)
        parts.append(run.sportType)
        if run.isRace { parts.append("race") }

        return parts.joined(separator: " ").lowercased()
    }
}
