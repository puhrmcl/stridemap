import Foundation
import SwiftUI

/// What the Milestones page can chart. Each case is one honest reduction of an activity to a
/// number, so every chart, scrubber readout and comparison on the page reads the same quantity.
enum MilestoneMetric: String, CaseIterable, Identifiable, Codable {
    case distance, climb, time, activities

    var id: String { rawValue }

    var label: String {
        switch self {
        case .distance:   return "Distance"
        case .climb:      return "Climb"
        case .time:       return "Time"
        case .activities: return "Activities"
        }
    }

    var icon: String {
        switch self {
        case .distance:   return "arrow.left.and.right"
        case .climb:      return "mountain.2"
        case .time:       return "clock"
        case .activities: return "figure.mixed.cardio"
        }
    }

    /// One activity's contribution, in the metric's own base unit (metres, metres, seconds, count).
    func value(of run: Run) -> Double {
        switch self {
        case .distance:   return run.distance
        case .climb:      return run.elevationGain
        case .time:       return Double(run.movingTime)
        case .activities: return 1
        }
    }

    /// A climb total in the reader's unit. `Format.elevation` is built for a single activity's
    /// gain — hundreds, ungrouped — and a lifetime total is five or six digits, where "41230 ft"
    /// is a number nobody reads at a glance.
    private func climbValue(_ meters: Double) -> Double {
        UnitSystem.current == .miles ? meters * 3.28084 : meters
    }

    private var climbSuffix: String { UnitSystem.current == .miles ? "ft" : "m" }

    /// A total, phrased for a readout.
    func format(_ total: Double) -> String {
        switch self {
        case .distance:
            return Format.distance(total, decimals: total < 10_000 ? 1 : 0)
        case .climb:
            return "\(Int(climbValue(total).rounded()).formatted(.number.grouping(.automatic))) \(climbSuffix)"
        case .time:
            return Format.duration(Int(total.rounded()))
        case .activities:
            return Int(total.rounded()).formatted()
        }
    }

    /// The same total with no unit, for an axis.
    func axisLabel(_ total: Double) -> String {
        switch self {
        case .distance:
            return Format.distanceValue(total).formatted(.number.precision(.fractionLength(0)))
        case .climb:
            return Int(climbValue(total).rounded()).formatted(.number.notation(.compactName))
        case .time:
            return "\(Int(total / 3600))h"
        case .activities:
            return Int(total.rounded()).formatted()
        }
    }
}

/// How much history a chart looks at. Each range implies its own shape, which is why they are not
/// interchangeable: a year is a race against the year before it, a rolling window is a set of
/// months, a lifetime is a set of years.
enum MilestoneRange: String, CaseIterable, Identifiable, Codable {
    /// This calendar year so far, cumulative, against last year on the same day.
    case year
    /// The trailing twelve months, month by month.
    case months
    /// Every year on record.
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .year:   return "This year"
        case .months: return "12 months"
        case .all:    return "All time"
        }
    }
}

/// The derivations behind the Milestones page.
///
/// All of it is pure: values in, values out, no view state and no I/O, which is what lets the
/// behavioural check drive the same functions the page draws from rather than a restatement of
/// them. The page's job is to render these; the judgement about what is true lives here.
enum MilestoneInsights {

    // MARK: Shared admission

    /// The activities any of this is allowed to count. Totals exclusions are honoured — an
    /// activity the reader kept out of their totals must not reappear inside a chart of those
    /// totals — and so is the ordering, so every series below is chronological by construction.
    static func admitted(_ runs: [Run]) -> [Run] {
        runs.countingTotals.sorted { $0.startDate < $1.startDate }
    }

    // MARK: The cumulative race

    struct Point: Identifiable, Equatable {
        /// The day *is* the identity. A fresh UUID per instance looks harmless on a value type
        /// and is ruinous here: these points are rebuilt whenever the series is, so a UUID makes
        /// every rebuild a completely new set of elements, and SwiftUI tears down and re-animates
        /// the entire plot rather than updating it in place.
        var id: Int { day }
        /// Position along the year, 1...366. The axis both series share. Unique within a series
        /// by construction — several activities on one date are folded into one point.
        let day: Int
        let date: Date
        /// The running total at this point.
        let value: Double

        static func == (a: Point, b: Point) -> Bool {
            a.day == b.day && a.value == b.value
        }
    }

    struct Series: Identifiable, Equatable {
        let id: String
        let label: String
        let points: [Point]
        var total: Double { points.last?.value ?? 0 }

        /// The running total on or before a given day — what the scrubber reads.
        func value(onOrBefore day: Int) -> Double {
            var carried = 0.0
            for point in points where point.day <= day { carried = point.value }
            return carried
        }
    }

    /// This year and last year as two cumulative curves on a shared day-of-year axis.
    ///
    /// Plotting both against day-of-year rather than date is the whole point: it puts 12 March on
    /// top of 12 March and turns two totals into a race the reader can actually read. Days are
    /// taken from the calendar's own ordinal, so a leap year does not shift autumn by a day
    /// against the year beside it.
    static func race(_ runs: [Run], metric: MilestoneMetric, now: Date = .now,
                     calendar: Calendar = .current) -> [Series] {
        let thisYear = calendar.component(.year, from: now)
        let admitted = admitted(runs)
        return [thisYear, thisYear - 1].compactMap { year -> Series? in
            let inYear = admitted.filter { calendar.component(.year, from: $0.startDate) == year }
            guard !inYear.isEmpty else { return nil }
            var carried = 0.0
            var points: [Point] = []
            for run in inYear {
                guard let day = calendar.ordinality(of: .day, in: .year, for: run.startDate) else { continue }
                carried += metric.value(of: run)
                // One point per day: several activities on one day are one step on the curve, so
                // the line does not stack vertical segments on a single x.
                if let last = points.last, last.day == day {
                    points[points.count - 1] = Point(day: day, date: run.startDate, value: carried)
                } else {
                    points.append(Point(day: day, date: run.startDate, value: carried))
                }
            }
            guard !points.isEmpty else { return nil }
            return Series(id: "\(year)", label: "\(year)", points: points)
        }
    }

    /// How far ahead (or behind) this year is against last year *on the same day* — the only
    /// comparison that is fair in October, and the one a bare year-to-date total gets wrong.
    static func pacing(_ series: [Series], now: Date = .now,
                       calendar: Calendar = .current) -> (delta: Double, lastYearToDate: Double)? {
        guard series.count == 2,
              let today = calendar.ordinality(of: .day, in: .year, for: now) else { return nil }
        let thisYear = series[0].total
        let lastYearToDate = series[1].value(onOrBefore: today)
        return (thisYear - lastYearToDate, lastYearToDate)
    }

    // MARK: Buckets — months and years

    struct Bucket: Identifiable, Equatable {
        let id: String
        /// The axis label: "Mar", or "2024".
        let label: String
        let value: Double
        let count: Int
        /// The current month or year, which the chart lights up.
        let isCurrent: Bool
    }

    /// The trailing twelve months, oldest first, including the months with nothing in them — a
    /// gap is information, and a chart that silently drops empty months misreports a quiet spring
    /// as a busy one.
    static func months(_ runs: [Run], metric: MilestoneMetric, now: Date = .now,
                       calendar: Calendar = .current) -> [Bucket] {
        let admitted = admitted(runs)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM"
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        return (0..<12).reversed().compactMap { back -> Bucket? in
            guard let start = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let inMonth = admitted.filter { $0.startDate >= start && $0.startDate < end }
            let components = calendar.dateComponents([.year, .month], from: start)
            return Bucket(id: "\(components.year ?? 0)-\(components.month ?? 0)",
                          label: formatter.string(from: start),
                          value: inMonth.reduce(0) { $0 + metric.value(of: $1) },
                          count: inMonth.count,
                          isCurrent: back == 0)
        }
    }

    /// Every year on record, oldest first. Empty years inside the span are kept for the same
    /// reason the months are.
    static func years(_ runs: [Run], metric: MilestoneMetric, now: Date = .now,
                      calendar: Calendar = .current) -> [Bucket] {
        let admitted = admitted(runs)
        guard let first = admitted.first?.startDate, let last = admitted.last?.startDate else { return [] }
        let firstYear = calendar.component(.year, from: first)
        let lastYear = max(calendar.component(.year, from: last), calendar.component(.year, from: now))
        let thisYear = calendar.component(.year, from: now)
        guard lastYear >= firstYear, lastYear - firstYear < 80 else { return [] }

        return (firstYear...lastYear).map { year in
            let inYear = admitted.filter { calendar.component(.year, from: $0.startDate) == year }
            return Bucket(id: "\(year)", label: "\(year)",
                          value: inYear.reduce(0) { $0 + metric.value(of: $1) },
                          count: inYear.count,
                          isCurrent: year == thisYear)
        }
    }

    // MARK: Rhythm — when you actually move

    /// Four parts of a day. Coarser than hours on purpose: an hourly chart of a few hundred
    /// activities is noise, and nobody thinks of themselves as "a 06:00–07:00 person".
    enum Band: Int, CaseIterable, Identifiable {
        case early, morning, afternoon, evening
        var id: Int { rawValue }

        /// The hour this band starts at.
        var start: Int {
            switch self {
            case .early:     return 0
            case .morning:   return 6
            case .afternoon: return 12
            case .evening:   return 18
            }
        }

        var label: String {
            switch self {
            case .early:     return "Night"
            case .morning:   return "Morning"
            case .afternoon: return "Afternoon"
            case .evening:   return "Evening"
            }
        }

        static func of(hour: Int) -> Band {
            switch hour {
            case 6..<12:  return .morning
            case 12..<18: return .afternoon
            case 18..<24: return .evening
            default:      return .early
            }
        }
    }

    struct Rhythm: Equatable {
        /// `counts[weekdayIndex][band]`, weekday 0 = Monday.
        var counts: [[Int]]
        var total: Int
        /// The busiest cell, when one stands out at all.
        var peak: (weekday: Int, band: Band, count: Int)?

        static func == (a: Rhythm, b: Rhythm) -> Bool {
            a.counts == b.counts && a.total == b.total
        }

        func count(weekday: Int, band: Band) -> Int {
            guard counts.indices.contains(weekday),
                  counts[weekday].indices.contains(band.rawValue) else { return 0 }
            return counts[weekday][band.rawValue]
        }

        var busiest: Int { counts.flatMap { $0 }.max() ?? 0 }
    }

    /// When the reader moves, as a week × part-of-day grid.
    ///
    /// Monday-first regardless of locale: this grid is read as a working week, and a Sunday-first
    /// layout splits the weekend across the two ends of it.
    static func rhythm(_ runs: [Run], calendar: Calendar = .current) -> Rhythm {
        var counts = Array(repeating: Array(repeating: 0, count: Band.allCases.count), count: 7)
        var total = 0
        for run in admitted(runs) {
            let components = calendar.dateComponents([.weekday, .hour], from: run.startDate)
            guard let weekday = components.weekday, let hour = components.hour else { continue }
            // Calendar weekday is 1 = Sunday; shift so 0 = Monday.
            let index = (weekday + 5) % 7
            let band = Band.of(hour: hour)
            counts[index][band.rawValue] += 1
            total += 1
        }
        var peak: (weekday: Int, band: Band, count: Int)?
        for (index, row) in counts.enumerated() {
            for band in Band.allCases where row[band.rawValue] > (peak?.count ?? 0) {
                peak = (index, band, row[band.rawValue])
            }
        }
        // A peak only means something if it actually leads. With a handful of activities, or a
        // dead-flat spread, naming one cell would invent a habit the history does not show.
        if let found = peak, total < 8 || found.count < 2 { peak = nil }
        return Rhythm(counts: counts, total: total, peak: peak)
    }

    static func weekdayName(_ index: Int, short: Bool = false) -> String {
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let abbreviations = ["M", "T", "W", "T", "F", "S", "S"]
        guard names.indices.contains(index) else { return "" }
        return short ? abbreviations[index] : names[index]
    }

    /// The sentence over the rhythm grid. Nil when the history has not earned a claim.
    static func rhythmHeadline(_ rhythm: Rhythm) -> String? {
        guard let peak = rhythm.peak, rhythm.total > 0 else { return nil }
        let share = Double(peak.count) / Double(rhythm.total)
        let day = weekdayName(peak.weekday)
        let when = peak.band.label.lowercased()
        if share >= 0.25 {
            return "\(day) \(when)s are yours — \(Int((share * 100).rounded()))% of everything you do."
        }
        return "You move most on \(day) \(when)s."
    }

    // MARK: Perspective — numbers at human scale

    /// One rung on a ladder of real-world distances or heights, with how far the reader is along
    /// it. The point is not gamification: a number like "41,000 ft climbed" means nothing until
    /// it is put beside something a person can picture.
    struct Comparison: Identifiable, Equatable {
        let id: String
        /// What the total is being measured against.
        let subject: String
        /// The reader's own figure.
        let total: String
        /// "1.4 ×" when the rung is passed, else nil.
        let multiple: String?
        /// Progress toward the rung, 0...1. Full when passed.
        let progress: Double
        let caption: String
    }

    /// Heights worth picturing, in metres, smallest first. Figures are the commonly cited
    /// elevations above sea level.
    private static let climbs: [(String, Double)] = [
        ("the Eiffel Tower", 330),
        ("Ben Nevis", 1_345),
        ("Mount Fuji", 3_776),
        ("Mont Blanc", 4_808),
        ("Kilimanjaro", 5_895),
        ("Everest", 8_849)
    ]

    /// Journeys worth picturing, in metres.
    private static let journeys: [(String, Double)] = [
        ("a marathon", 42_195),
        ("the length of Manhattan, ten times", 211_000),
        ("London to Paris", 344_000),
        ("Land's End to John o' Groats", 1_407_000),
        ("Route 66", 3_940_000),
        ("the width of the Atlantic", 5_600_000),
        ("the circumference of the Earth", 40_075_000)
    ]

    /// Two comparisons: how far, and how high. Each picks the biggest rung the reader has passed
    /// and shows their progress toward the next one — so there is always something cleared and
    /// something ahead, and neither is invented.
    static func perspective(_ runs: [Run]) -> [Comparison] {
        let admitted = admitted(runs)
        guard !admitted.isEmpty else { return [] }
        let distance = admitted.reduce(0) { $0 + $1.distance }
        let climb = admitted.reduce(0) { $0 + $1.elevationGain }
        var out: [Comparison] = []
        if let far = rung(total: distance, ladder: journeys, id: "distance",
                          metric: .distance, verb: "covered") { out.append(far) }
        if climb >= 100, let high = rung(total: climb, ladder: climbs, id: "climb",
                                         metric: .climb, verb: "climbed") { out.append(high) }
        return out
    }

    private static func rung(total: Double, ladder: [(String, Double)], id: String,
                             metric: MilestoneMetric, verb: String) -> Comparison? {
        guard total > 0 else { return nil }
        let cleared = ladder.last { total >= $0.1 }
        let next = ladder.first { total < $0.1 }

        if let cleared {
            let times = total / cleared.1
            let multiple = times >= 1.1
                ? "\(times.formatted(.number.precision(.fractionLength(1))))×"
                : nil
            let caption: String
            if let next {
                let share = Int(((total / next.1) * 100).rounded())
                caption = "\(share)% of the way to \(next.0)."
            } else {
                caption = "Nothing on the list is further."
            }
            return Comparison(id: id, subject: cleared.0, total: metric.format(total),
                              multiple: multiple,
                              progress: next.map { min(1, total / $0.1) } ?? 1,
                              caption: caption)
        }

        // Nothing cleared yet — report honest progress toward the first rung rather than
        // claiming an achievement.
        guard let next = ladder.first else { return nil }
        return Comparison(id: id, subject: next.0, total: metric.format(total), multiple: nil,
                          progress: min(1, total / next.1),
                          caption: "\(Int(((total / next.1) * 100).rounded()))% of the way there.")
    }
}
