import Foundation

/// Small, evidence-backed observations about the imported record, not coaching or fitness claims.
/// Uses completed calendar periods, deduplicated activity IDs and active days. No network or LLM.
struct DailyStoryEngine {
    struct Mark: Identifiable {
        let label: String
        let value: Int
        var id: String { label }
    }
    struct Story: Identifiable {
        let id: String
        let eyebrow: String
        let title: String
        let message: String
        let prompt: String
        let symbol: String
        let run: Run
        let evidence: [String]
        var marks: [Mark] = []
        var shareText: String { "\(title)\n\n\(message)\n\nBased on my activity history in Etch." }
    }

    static func stories(in runs: [Run], scope: ActivityScope, now: Date = Date(),
                        calendar: Calendar = .current) -> [Story] {
        var seen = Set<UUID>()
        let history = runs.scoped(to: scope).filter {
            !$0.excludedFromTotals && !$0.isHiddenFromMemories && $0.startDate < now
                && seen.insert($0.id).inserted
        }.sorted { $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate }
        guard let earliest = history.first,
              let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let weekStart = calendar.date(byAdding: .weekOfYear, value: -8, to: weekEnd),
              let recentStart = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: now)) else { return [] }
        var result: [Story] = []
        let completed = history.filter { $0.startDate >= weekStart && $0.startDate < weekEnd }
        if earliest.startDate <= weekStart, let representative = completed.last {
            let marks = (0..<8).compactMap { offset -> Mark? in
                guard let start = calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart),
                      let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
                let days = Set(completed.filter { $0.startDate >= start && $0.startDate < end }
                    .map { calendar.startOfDay(for: $0.startDate) }).count
                return Mark(label: start.formatted(date: .abbreviated, time: .omitted), value: days)
            }
            let active = marks.filter { $0.value > 0 }.count
            if active >= 6 {
                result.append(Story(id: "consistency", eyebrow: "THE BIGGER PICTURE",
                    title: "You keep making room.",
                    message: "You recorded activity in \(active) of the last 8 complete weeks. Small days count toward that rhythm, too.",
                    prompt: "What has made it easier to keep showing up? Add a note to a recent outing.",
                    symbol: "calendar", run: representative,
                    evidence: ["\(active) active weeks out of 8 completed weeks.",
                               "Bars show distinct active days per week; multiple activities on a day count once.",
                               "The current, unfinished week is excluded."], marks: marks))
            }
        }
        let recent = history.filter { $0.startDate >= recentStart }
        let days = Set(recent.map { calendar.startOfDay(for: $0.startDate) })
        let weekdayCounts = Dictionary(grouping: days, by: { calendar.component(.weekday, from: $0) }).mapValues(\.count)
        if days.count >= 8, let first = recent.first,
           (calendar.dateComponents([.day], from: first.startDate, to: now).day ?? 0) >= 42,
           let winner = weekdayCounts.keys.sorted(by: {
               weekdayCounts[$0, default: 0] == weekdayCounts[$1, default: 0] ? $0 < $1
                   : weekdayCounts[$0, default: 0] > weekdayCounts[$1, default: 0]
           }).first,
           let count = weekdayCounts[winner], count >= 6, Double(count) / Double(days.count) >= 0.35,
           let representative = recent.last(where: { calendar.component(.weekday, from: $0.startDate) == winner }) {
            let name = calendar.weekdaySymbols[winner - 1]
            let marks = (0..<7).map { offset -> Mark in
                let day = (calendar.firstWeekday - 1 + offset) % 7 + 1
                return Mark(label: calendar.weekdaySymbols[day - 1], value: weekdayCounts[day, default: 0])
            }
            result.append(Story(id: "weekday", eyebrow: "YOUR OWN RHYTHM",
                title: "\(name) has a pattern.",
                message: "\(count) of your \(days.count) active days in the last 90 days fell on a \(name). It’s your most frequent day in this history.",
                prompt: "Is there something about this day you want to make time for again?",
                symbol: "sun.max", run: representative,
                evidence: ["\(count) distinct \(name) dates among \(days.count) active dates.",
                           "A 90-day window, using your calendar and timezone.",
                           "Multiple imports or activities on the same date do not inflate the day count."], marks: marks))
        }
        // Require older history before describing a place as newly represented in the record.
        if earliest.startDate < recentStart {
            let located = history.filter { cityKey($0) != nil }
            let places = Dictionary(grouping: located, by: { cityKey($0)! })
            let newPlaces = places.values.compactMap { visits -> Run? in
                guard let first = visits.first, first.startDate >= recentStart else { return nil }
                return first
            }.sorted { $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate }
            if let representative = newPlaces.last {
                let count = newPlaces.count
                result.append(Story(id: "discovery", eyebrow: "YOUR WORLD IS GROWING",
                    title: count == 1 ? "A new place in your story." : "\(count) new places in your story.",
                    message: "\(representative.placeLabel)\(count > 1 ? " and \(count - 1) more" : "") first appeared in your imported activity history in the last 90 days.",
                    prompt: "What do you remember noticing there? Revisit the activity and save that detail.",
                    symbol: "map", run: representative,
                    evidence: newPlaces.map { "\($0.placeLabel) · first recorded \(Format.date($0.startDate))" }
                        + ["Cities are matched by city, region and country labels. Missing labels are excluded.",
                           "This means new to the history in Etch, not necessarily your first visit."]))
            }
        }
        return result
    }

    private static func cityKey(_ run: Run) -> String? {
        func normalized(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let city = normalized(run.city), country = normalized(run.country)
        guard !city.isEmpty, !country.isEmpty else { return nil }
        return "\(city)|\(normalized(run.state))|\(country)"
    }
}
