import SwiftUI

/// Proves the Milestones derivations, on a simulator, in CI.
///
/// Everything the new page draws comes out of `MilestoneInsights`, which is pure logic over
/// values — exactly the thing worth pinning down, and exactly the thing a screenshot cannot
/// check. A chart that renders beautifully from a wrong series looks fine in a review and lies to
/// the reader about their own history.
///
/// The claims that matter here are honesty claims: a cumulative curve must never go down, the two
/// years of the race must be compared on the same day rather than on their totals, activities the
/// reader kept out of their totals must not reappear inside a chart of those totals, and a
/// perspective rung must never be claimed before it is passed.
@MainActor
struct MilestoneInsightsCheckView: View {

    static let expectedChecks = 20

    @State private var report = "Checking milestone insights…"

    var body: some View {
        ScrollView { Text(report).font(.system(size: 11, design: .monospaced)).padding() }
            .task { run() }
    }

    private func run() {
        var results: [(String, Bool, String)] = []
        func expect(_ name: String, _ passed: Bool, _ note: String) {
            results.append((name, passed, note))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // A fixed clock. Anchoring to the real date makes the suite's fixtures drift out from
        // under it as the year turns, which is how a check quietly starts testing nothing.
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12))!
        let thisYear = calendar.component(.year, from: now)

        func activity(_ date: Date, distance: Double = 5_000, climb: Double = 100,
                      seconds: Int = 1_800, excluded: Bool = false) -> Run {
            let run = Run(provider: .healthKit, name: "check",
                          startDate: date, distance: distance, movingTime: seconds,
                          elapsedTime: seconds, elevationGain: climb, summaryPolyline: "",
                          sportType: "Run", excludedFromTotals: excluded)
            run.activityType = .run
            return run
        }

        func day(_ year: Int, _ month: Int, _ d: Int, hour: Int = 9) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: d, hour: hour))!
        }

        // ── The cumulative race

        let history = [
            activity(day(thisYear - 1, 2, 1), distance: 10_000),
            activity(day(thisYear - 1, 9, 1), distance: 10_000),   // after today's day-of-year
            activity(day(thisYear, 2, 1), distance: 4_000),
            activity(day(thisYear, 3, 1), distance: 6_000)
        ]
        let race = MilestoneInsights.race(history, metric: .distance, now: now, calendar: calendar)

        expect("Both years appear as their own series", race.count == 2,
               "this year and last year are two curves on one axis")

        let current = race.first
        expect("The curve never goes down",
               current.map { series in
                   zip(series.points, series.points.dropFirst()).allSatisfy { $0.value <= $1.value }
               } ?? false,
               "a cumulative total that dips would be reporting a negative activity")

        expect("The running total is the sum of its parts",
               abs((current?.total ?? 0) - 10_000) < 0.001,
               "4 km then 6 km reads 10 km, not 6")

        expect("Days of the year line up across years",
               race.count == 2 && race[1].points.first?.day == race[0].points.first?.day,
               "1 February is 1 February in both years, which is what makes the race fair")

        // The headline comparison. Last year ended on 20 km, but only 10 km of it was on the
        // board by 2 July — comparing against the full year would report this year as behind
        // when it is exactly level.
        let pace = MilestoneInsights.pacing(race, now: now, calendar: calendar)
        expect("Last year is compared on the same day, not on its total",
               pace.map { abs($0.lastYearToDate - 10_000) < 0.001 } ?? false,
               "the September activity is not yet counted on 2 July")
        expect("Level years report level", pace.map { abs($0.delta) < 0.001 } ?? false,
               "10 km against 10 km is level, however the year ended")

        // ── Admission

        let withExcluded = history + [activity(day(thisYear, 4, 1), distance: 50_000, excluded: true)]
        let excludedRace = MilestoneInsights.race(withExcluded, metric: .distance,
                                                  now: now, calendar: calendar)
        expect("Excluded-from-totals stays out of the totals chart",
               abs((excludedRace.first?.total ?? 0) - 10_000) < 0.001,
               "an activity the reader kept out of their totals cannot reappear inside them")

        expect("An empty history charts nothing rather than crashing",
               MilestoneInsights.race([], metric: .distance, now: now, calendar: calendar).isEmpty,
               "a new library opens on this page too")

        // Several activities in one day are one step on the curve, not several points at one x.
        let sameDay = [activity(day(thisYear, 5, 4), distance: 3_000),
                       activity(day(thisYear, 5, 4, hour: 18), distance: 3_000)]
        let sameDayRace = MilestoneInsights.race(sameDay, metric: .distance, now: now, calendar: calendar)
        expect("A double day is one point carrying both",
               sameDayRace.first?.points.count == 1
               && abs((sameDayRace.first?.total ?? 0) - 6_000) < 0.001,
               "two activities on one date are one step, and the step is their sum")

        // ── Buckets

        let months = MilestoneInsights.months(history, metric: .distance, now: now, calendar: calendar)
        expect("Twelve months are always twelve buckets", months.count == 12,
               "a quiet month is information; dropping it misreports the months around it")
        expect("The trailing window ends on this month", months.last?.isCurrent == true,
               "the current month is the one the chart lights up")

        let years = MilestoneInsights.years(history, metric: .activities, now: now, calendar: calendar)
        expect("Every year between first and last is present",
               years.count == 2 && years.first?.label == "\(thisYear - 1)",
               "a year off still occupies its place on the axis")
        expect("Year buckets count their own activities",
               years.last?.count == 2, "two activities this year")

        // ── Rhythm

        // Eight Monday mornings and one Saturday night: a clear peak, and a total above the floor
        // the headline requires.
        var rhythmRuns: [Run] = []
        for week in 0..<8 { rhythmRuns.append(activity(day(thisYear, 1, 5 + week * 7, hour: 8))) }
        rhythmRuns.append(activity(day(thisYear, 1, 10, hour: 2)))
        let rhythm = MilestoneInsights.rhythm(rhythmRuns, calendar: calendar)

        expect("Every activity lands in exactly one cell",
               rhythm.counts.flatMap { $0 }.reduce(0, +) == rhythmRuns.count,
               "the grid is a partition of the history, not a sample of it")
        expect("Monday is the first column",
               rhythm.count(weekday: 0, band: .morning) == 8,
               "5 January 2026 is a Monday; a Sunday-first week would split the weekend")
        // The night band is the wrap-around case — it is the `default` branch, the one that
        // catches everything the explicit ranges miss, and so the one most able to silently
        // swallow an hour that belongs elsewhere.
        expect("The small hours count as night",
               rhythm.count(weekday: 5, band: .early) == 1,
               "02:00 on a Saturday is night; 18:00-24:00 is evening and is tested by the bands above")
        expect("The peak is named", rhythm.peak?.band == .morning && rhythm.peak?.weekday == 0,
               "eight of nine activities share one cell")

        // A flat, thin history must not be given a habit it has not shown.
        let sparse = [activity(day(thisYear, 1, 5, hour: 8)), activity(day(thisYear, 1, 6, hour: 14))]
        expect("A thin history is not given a pattern",
               MilestoneInsights.rhythmHeadline(MilestoneInsights.rhythm(sparse, calendar: calendar)) == nil,
               "two activities are not a routine, and claiming one would discredit the real ones")

        // ── Perspective

        // 50 km covered, 400 m climbed: past a marathon and past the Eiffel Tower, and nowhere
        // near the rungs above them.
        let modest = [activity(day(thisYear, 3, 1), distance: 50_000, climb: 400)]
        let perspective = MilestoneInsights.perspective(modest)
        expect("Perspective reports the rung actually cleared",
               perspective.first(where: { $0.id == "distance" })?.subject == "a marathon",
               "the largest rung passed, not the most impressive one on the list")
        expect("Progress toward the next rung is a fraction, never over one",
               perspective.allSatisfy { $0.progress >= 0 && $0.progress <= 1 },
               "a bar that overflows its track is reporting a number it does not have")

        // ── The count is itself an assertion.

        if results.count != Self.expectedChecks {
            results.append(("Check count", false,
                            "expected \(Self.expectedChecks) checks, ran \(results.count)"))
        }

        var lines = ["milestone-insights \(AppInfo.changeTag)"]
        for result in results {
            lines.append("\(result.1 ? "PASS" : "FAIL")  \(result.0) — \(result.2)")
        }
        lines.append("EXPECTED_CHECKS: \(Self.expectedChecks)")
        lines.append("RAN_CHECKS: \(results.count)")
        let ok = results.allSatisfy(\.1) && results.count == Self.expectedChecks
        lines.append(ok ? "RESULT: ALL PASS" : "RESULT: FAIL")
        report = lines.joined(separator: "\n")

        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        try? report.write(to: directory.appendingPathComponent("milestone-insights-report.txt"),
                          atomically: true, encoding: .utf8)
    }
}
