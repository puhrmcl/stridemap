import Foundation

/// What the year (or collection) *meant* — derived once, carried by the plan, rendered by pages.
///
/// This is the book's editorial brain. The history says what happened; this reads it and answers
/// what stood out: the marks worth a page, the month that carried the year, the streak, the
/// thresholds crossed, the places seen for the first time. Pure derivation over
/// `(subject's activities, full history)` — the full history is what makes "first time" and
/// "the 1,000th mile" honest, because both are relative to everything before, not just the
/// months inside the covers.
///
/// Deliberately sport-agnostic: it speaks in activities, marks, places and progress, because the
/// same engine will one day read a cycling year or a hiking year. Nothing here says "run" except
/// data that already does.
struct BookStory {

    /// One achievement, phrased and ready to set: the big value, its label, and the line under it.
    struct Mark: Identifiable {
        let id: String
        let value: String    // "3:54:54", "26.2 MI", "14 DAYS"
        let title: String    // "MARATHON BEST", "THE LONGEST", "THE STREAK"
        let detail: String   // "Mesa Marathon · Feb 14"
    }

    /// The marks page's material, editorial order, capped for one page.
    let marks: [Mark]

    /// The month that carried the most distance, phrased ("October", "312 MI").
    let peakMonth: (name: String, value: String)?

    /// Longest chain of consecutive active days.
    let streakDays: Int

    /// Places seen for the first time ever, *during* this book's span.
    let newStates: [String]
    let newCities: [String]

    /// Benchmark bests inside this book (5K/10K/half/marathon…), for the review page.
    let personalRecords: [RunStatistics.DistancePR]

    /// Activities the marks point at — the month pages use this to pick their marquee.
    let markedRunIDs: Set<UUID>

    /// How a chapter should be treated. Phase 1 knows two shapes; photo and feature profiles
    /// arrive with the Moments system.
    enum ChapterProfile: Equatable {
        /// A handful of activities — a grid would be mostly air. One route drawn large,
        /// the rest as a listing.
        case quiet
        /// Enough material for the grid, led by a marquee cell.
        case standard
    }

    static func chapterProfile(for runs: [Run]) -> ChapterProfile {
        runs.count <= 4 ? .quiet : .standard
    }

    /// The activity a chapter page leads with: a race first, then a mark-holder, then simply the
    /// longest. Later phases put the user's own pick above all three.
    func marquee(in runs: [Run]) -> Run? {
        runs.first(where: \.isRace)
            ?? runs.first(where: { markedRunIDs.contains($0.id) })
            ?? runs.max(by: { $0.distance < $1.distance })
    }
}

enum StoryEngine {

    /// Reads a history. `selected` is what the book binds; `history` is everything the person
    /// has, which is what makes firsts and lifetime thresholds truthful.
    static func story(selected: [Run], history: [Run]) -> BookStory {
        let stats = RunStatistics(selected)
        let calendar = Calendar.current

        // Benchmark bests worth a card, biggest event first. 1K/1-mile stay off the marks page —
        // they read as training detail next to a marathon — but remain in personalRecords for
        // the review table.
        let cardWorthy = ["Marathon", "Half Marathon", "10K", "5K"]
        let prs = stats.personalRecords
        let prMarks: [BookStory.Mark] = cardWorthy.compactMap { label in
            guard let pr = prs.first(where: { $0.label == label }) else { return nil }
            return BookStory.Mark(
                id: "pr-\(label)",
                value: duration(pr.run.movingTime),
                title: "\(label.uppercased()) BEST",
                detail: "\(pr.run.name) · \(shortDate(pr.run.startDate))"
            )
        }

        let peak = peakMonth(selected, calendar)
        let streak = longestStreak(selected, calendar)
        let milestone = lifetimeMilestone(selected: selected, history: history)
        let firsts = firstPlaces(selected: selected, history: history)

        var marks: [BookStory.Mark] = []
        marks.append(contentsOf: prMarks.prefix(2))

        if let longest = stats.longestRun {
            marks.append(.init(
                id: "longest",
                value: StatMetric.distance.value(for: longest) ?? "",
                title: "THE LONGEST",
                detail: "\(longest.name) · \(shortDate(longest.startDate))"
            ))
        }
        if let milestone {
            marks.append(milestone)
        }
        if let peak {
            marks.append(.init(id: "peak", value: peak.value, title: "BIGGEST MONTH",
                               detail: peak.name))
        }
        if streak.days >= 3, let end = streak.end,
           let start = calendar.date(byAdding: .day, value: -(streak.days - 1), to: end) {
            marks.append(.init(id: "streak", value: "\(streak.days) DAYS", title: "THE STREAK",
                               detail: "\(shortDate(start)) – \(shortDate(end))"))
        }
        if let climb = stats.highestClimb, climb.elevationGain >= 150 {
            marks.append(.init(
                id: "climb",
                value: Format.elevation(climb.elevationGain),
                title: "THE CLIMB",
                detail: "\(climb.name) · \(shortDate(climb.startDate))"
            ))
        }
        if !firsts.states.isEmpty {
            marks.append(.init(
                id: "new-states",
                value: "\(firsts.states.count)",
                title: firsts.states.count == 1 ? "NEW STATE" : "NEW STATES",
                detail: firsts.states.prefix(3).joined(separator: " · ")
            ))
        }

        let marked = Set(
            [stats.longestRun?.id, stats.highestClimb?.id].compactMap { $0 }
            + prs.map(\.run.id)
        )

        return BookStory(
            marks: Array(marks.prefix(6)),
            peakMonth: peak,
            streakDays: streak.days,
            newStates: firsts.states,
            newCities: firsts.cities,
            personalRecords: prs,
            markedRunIDs: marked
        )
    }

    // MARK: Detections

    private static func peakMonth(_ runs: [Run], _ calendar: Calendar)
        -> (name: String, value: String)? {
        let byMonth = Dictionary(grouping: runs) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.startDate)) ?? $0.startDate
        }
        guard byMonth.count > 1,
              let best = byMonth.max(by: { lhs, rhs in
                  lhs.value.reduce(0) { $0 + $1.distance } < rhs.value.reduce(0) { $0 + $1.distance }
              }) else { return nil }
        let meters = best.value.reduce(0) { $0 + $1.distance }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        let value = Format.distanceValue(meters).formatted(.number.precision(.fractionLength(0)))
        return (formatter.string(from: best.key),
                "\(value) \(UnitSystem.current.label.uppercased())")
    }

    private static func longestStreak(_ runs: [Run], _ calendar: Calendar)
        -> (days: Int, end: Date?) {
        let days = Set(runs.map { calendar.startOfDay(for: $0.startDate) }).sorted()
        guard !days.isEmpty else { return (0, nil) }
        var best = 1, bestEnd = days[0]
        var current = 1
        for index in 1..<days.count {
            let gap = calendar.dateComponents([.day], from: days[index - 1], to: days[index]).day ?? 0
            current = gap == 1 ? current + 1 : 1
            if current > best { best = current; bestEnd = days[index] }
        }
        return (best, bestEnd)
    }

    /// The biggest lifetime-distance threshold crossed during the book's span — "the 1,000th
    /// mile" is a lifetime fact, so the odometer runs over the whole history and only the
    /// crossing has to land inside the covers.
    private static func lifetimeMilestone(selected: [Run], history: [Run]) -> BookStory.Mark? {
        let thresholds: [Double] = [100, 250, 500, 1_000, 2_500, 5_000, 10_000, 25_000]
        let selectedIDs = Set(selected.map(\.id))
        var cumulative = 0.0
        var best: (threshold: Double, run: Run)?
        for run in history.sorted(by: { $0.startDate < $1.startDate }) {
            let before = cumulative
            cumulative += Format.distanceValue(run.distance)
            guard selectedIDs.contains(run.id) else { continue }
            for threshold in thresholds where before < threshold && cumulative >= threshold {
                if best == nil || threshold > best!.threshold { best = (threshold, run) }
            }
        }
        guard let best else { return nil }
        let number = best.threshold.formatted(.number.precision(.fractionLength(0)))
        return BookStory.Mark(
            id: "milestone",
            value: "\(number) \(UnitSystem.current.label.uppercased())",
            title: "LIFETIME MARK",
            detail: "Crossed \(shortDate(best.run.startDate)) · \(best.run.name)"
        )
    }

    /// States and cities whose first-ever visit happened inside this book.
    private static func firstPlaces(selected: [Run], history: [Run])
        -> (states: [String], cities: [String]) {
        let ordered = history.sorted { $0.startDate < $1.startDate }
        let selectedIDs = Set(selected.map(\.id))
        var seenStates: Set<String> = []
        var seenCities: Set<String> = []
        var newStates: [String] = []
        var newCities: [String] = []
        for run in ordered {
            if let state = PlaceNames.canonicalState(run.state), !state.isEmpty {
                if seenStates.insert(state).inserted, selectedIDs.contains(run.id) {
                    newStates.append(state)
                }
            }
            if let city = run.city, !city.isEmpty {
                let key = "\(city)|\(PlaceNames.canonicalState(run.state) ?? "")"
                if seenCities.insert(key).inserted, selectedIDs.contains(run.id) {
                    newCities.append(city)
                }
            }
        }
        return (newStates, newCities)
    }

    // MARK: Phrasing helpers

    private static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, secs = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                         : String(format: "%d:%02d", minutes, secs)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
