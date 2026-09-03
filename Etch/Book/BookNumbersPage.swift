import SwiftUI

/// THE NUMBERS — the ledger the review page is too emotional for. Nine cards of derived
/// insight, spoken in the marks page's card language so the book stays one voice: time in
/// motion, active days, the biggest week, the average, the total climb, the earliest start,
/// the busiest day of the week, the weekend share. Pure derivation over the plan's runs, so
/// it works identically for a year and for a collection.
extension BookPageView {

    var numbersPage: some View {
        let cards = BookNumbers.insights(runs: plan.runs)
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 34), count: 3)

        return VStack(spacing: 44) {
            pageHeader("WHAT IT ADDED UP TO", subtitle: "THE NUMBERS")
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 48) {
                ForEach(cards) { card in
                    VStack(spacing: 8) {
                        Text(card.value)
                            .font(.etch(size: 40, weight: .bold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(card.title)
                            .font(.etch(size: 13, weight: .semibold)).tracking(3)
                            .foregroundStyle(accent)
                        Text(card.detail.uppercased())
                            .font(.etch(size: 11, weight: .medium)).tracking(1.2)
                            .foregroundStyle(subtle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(margin)
    }
}

/// The derivations behind THE NUMBERS. Everything is phrased here (value/title/detail), so the
/// page renders cards without re-deriving — the same contract the StoryEngine keeps.
enum BookNumbers {

    struct Insight: Identifiable {
        let id: String
        let value: String
        let title: String
        let detail: String
    }

    static func insights(runs: [Run]) -> [Insight] {
        guard !runs.isEmpty else { return [] }
        let calendar = Calendar.current
        var cards: [Insight] = []
        let unit = UnitSystem.current.label.uppercased()

        // Time in motion — the sum nobody sees while it accumulates.
        let seconds = runs.reduce(0) { $0 + $1.movingTime }
        cards.append(.init(id: "motion", value: motionText(seconds),
                           title: "TIME IN MOTION", detail: "Moving time, summed"))

        // Active days, against the span they happened in.
        let days = Set(runs.map { calendar.startOfDay(for: $0.startDate) })
        if let first = runs.map(\.startDate).min(), let last = runs.map(\.startDate).max() {
            let span = (calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                                to: calendar.startOfDay(for: last)).day ?? 0) + 1
            cards.append(.init(id: "days", value: "\(days.count)",
                               title: days.count == 1 ? "ACTIVE DAY" : "ACTIVE DAYS",
                               detail: "Of \(span) in the span"))
        }

        // The biggest week.
        if let week = biggestWeek(runs, calendar) {
            cards.append(.init(id: "week", value: "\(week.miles) \(unit)",
                               title: "BIGGEST WEEK", detail: week.range))
        }

        // The average — the honest middle of it all.
        let totalMiles = runs.reduce(0.0) { $0 + Format.distanceValue($1.distance) }
        let average = (totalMiles / Double(runs.count))
            .formatted(.number.precision(.fractionLength(1)))
        cards.append(.init(id: "average", value: "\(average) \(unit)",
                           title: "THE AVERAGE", detail: "Per activity"))

        // Total ascent, with the mountain for scale when it's earned one.
        let climbMeters = runs.reduce(0.0) { $0 + $1.elevationGain }
        if climbMeters >= 100 {
            let everests = climbMeters / 8_849
            let detail = everests >= 1
                ? "\(everests.formatted(.number.precision(.fractionLength(1))))× Everest"
                : "Every foot counted"
            cards.append(.init(id: "climb", value: Format.elevation(climbMeters),
                               title: "TOTAL ASCENT", detail: detail))
        }

        // The earliest start — the alarm that actually went off.
        if let earliest = runs.min(by: { minutesIntoDay($0.startDate, calendar)
                                       < minutesIntoDay($1.startDate, calendar) }) {
            cards.append(.init(id: "earliest", value: clockText(earliest.startDate),
                               title: "EARLIEST START", detail: shortDate(earliest.startDate)))
        }

        // The busiest day of the week.
        if let busiest = busiestWeekday(runs, calendar) {
            cards.append(.init(id: "weekday", value: busiest.name.uppercased(),
                               title: "THE USUAL DAY",
                               detail: "\(busiest.count) starts"))
        }

        // Where the miles sat in the week.
        let weekend = runs.filter {
            let day = calendar.component(.weekday, from: $0.startDate)
            return day == 1 || day == 7
        }.count
        let share = Int((Double(weekend) / Double(runs.count) * 100).rounded())
        cards.append(.init(id: "weekend", value: "\(share)%",
                           title: "ON WEEKENDS",
                           detail: "\(weekend) of \(runs.count) starts"))

        // The longest thing that isn't already a mark: distance covered per active day.
        if !days.isEmpty {
            let perDay = (totalMiles / Double(days.count))
                .formatted(.number.precision(.fractionLength(1)))
            cards.append(.init(id: "perday", value: "\(perDay) \(unit)",
                               title: "PER ACTIVE DAY", detail: "When you went, you went"))
        }

        return Array(cards.prefix(9))
    }

    // MARK: Helpers

    private static func motionText(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)D \(hours)H" }
        if hours > 0 { return "\(hours)H \(minutes)M" }
        return "\(minutes)M"
    }

    private static func biggestWeek(_ runs: [Run], _ calendar: Calendar)
        -> (miles: String, range: String)? {
        let byWeek = Dictionary(grouping: runs) {
            calendar.dateInterval(of: .weekOfYear, for: $0.startDate)?.start ?? $0.startDate
        }
        guard byWeek.count > 1,
              let best = byWeek.max(by: { lhs, rhs in
                  lhs.value.reduce(0.0) { $0 + $1.distance } < rhs.value.reduce(0.0) { $0 + $1.distance }
              }) else { return nil }
        let meters = best.value.reduce(0.0) { $0 + $1.distance }
        let miles = Format.distanceValue(meters).formatted(.number.precision(.fractionLength(0)))
        let end = calendar.date(byAdding: .day, value: 6, to: best.key) ?? best.key
        return (miles, "\(shortDate(best.key)) – \(shortDate(end))")
    }

    private static func busiestWeekday(_ runs: [Run], _ calendar: Calendar)
        -> (name: String, count: Int)? {
        let counts = Dictionary(grouping: runs) { calendar.component(.weekday, from: $0.startDate) }
            .mapValues(\.count)
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        let formatter = DateFormatter()
        let name = formatter.weekdaySymbols[best.key - 1]
        return (name, best.value)
    }

    private static func minutesIntoDay(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
