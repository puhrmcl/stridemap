import SwiftUI

@MainActor
struct DailyStoryCheckView: View {
    @State private var report = "Checking daily stories…"
    var body: some View {
        ScrollView { Text(report).font(.caption.monospaced()).padding() }
            .task { runChecks() }
    }
    private func runChecks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        var results: [(String, Bool)] = []
        func check(_ name: String, _ passed: Bool) { results.append((name, passed)) }
        let oldPreference = UserDefaults.standard.object(forKey: "includeRuns")
        UserDefaults.standard.set(true, forKey: "includeRuns")
        defer {
            if let oldPreference { UserDefaults.standard.set(oldPreference, forKey: "includeRuns") }
            else { UserDefaults.standard.removeObject(forKey: "includeRuns") }
        }
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        let weekEnd = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        func fixture(_ date: Date) -> Run {
            Run(provider: .healthKit, name: "Story fixture", startDate: date, distance: 5000,
                movingTime: 1500, elapsedTime: 1800, elevationGain: 0, summaryPolyline: "", sportType: "Run")
        }
        let old = fixture(calendar.date(byAdding: .year, value: -2, to: now)!)
        let weekly = (1...8).map { fixture(calendar.date(byAdding: .weekOfYear, value: -$0, to: weekEnd)!) }
        let history = [old] + weekly
        func stories(_ runs: [Run], scope: ActivityScope = .runs, cal: Calendar? = nil) -> [DailyStoryEngine.Story] {
            DailyStoryEngine.stories(in: runs, scope: scope, now: now, calendar: cal ?? calendar)
        }
        let base = stories(history)
        let consistency = base.first { $0.id == "consistency" }
        check("Sparse history does not invent patterns", stories([old]).isEmpty)
        check("Eight complete active weeks produce exact marks", consistency?.marks.map(\.value) == Array(repeating: 1, count: 8))
        check("Current week is not compared with complete weeks",
              stories(history + [fixture(weekEnd.addingTimeInterval(3600))]).first { $0.id == "consistency" }?.marks.map(\.value) == consistency?.marks.map(\.value))
        check("Repeated IDs do not inflate stories", stories(history + weekly).map(\.message) == base.map(\.message))
        let sameDay = weekly.map { fixture($0.startDate.addingTimeInterval(3600)) }
        check("Multiple sessions count as one active day", stories(history + sameDay).first { $0.id == "weekday" }?.message == base.first { $0.id == "weekday" }?.message)
        check("Future activities do not create patterns", stories([old, fixture(now.addingTimeInterval(86400))]).isEmpty)
        check("Explicit empty type stays empty", stories(history, scope: .hikes).isEmpty)
        weekly.forEach { $0.isHidden = true }
        check("Hidden activities are excluded", stories(history).isEmpty)
        weekly.forEach { $0.isHidden = false; $0.excludedFromTotals = true }
        check("Counting exclusions cannot inflate a pattern", stories(history).isEmpty)
        weekly.forEach { $0.excludedFromTotals = false; $0.isHiddenFromMemories = true }
        check("Memory dismissals are respected", stories(history).isEmpty)
        weekly.forEach { $0.isHiddenFromMemories = false }
        UserDefaults.standard.set(false, forKey: "includeRuns")
        check("Disabled types are excluded", stories(history).isEmpty)
        UserDefaults.standard.set(true, forKey: "includeRuns")
        var pacific = calendar; pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        check("Weekday observations use the reader's timezone",
              stories(history, cal: pacific).first { $0.id == "weekday" }?.title == "Sunday has a pattern.")
        old.city = "Mesa"; old.state = "Arizona"; old.country = "United States"
        let repeatCity = fixture(now.addingTimeInterval(-86400))
        repeatCity.city = " MESA "; repeatCity.state = "arizona"; repeatCity.country = "united states"
        check("City spelling case and whitespace do not invent exploration",
              !stories([old, repeatCity]).contains { $0.id == "discovery" })
        let newCity = fixture(now.addingTimeInterval(-2 * 86400))
        newCity.city = "Paullina"; newCity.state = "Iowa"; newCity.country = "United States"
        check("New city evidence links to its first recorded activity",
              stories([old, repeatCity, newCity]).first { $0.id == "discovery" }?.run.id == newCity.id)
        newCity.country = nil
        check("Incomplete city labels are not invented",
              !stories([old, newCity]).contains { $0.id == "discovery" })
        newCity.country = "United States"
        check("A new import library is not called new exploration", stories([newCity, repeatCity]).isEmpty)
        let expected = 16
        var lines = results.map { "\($0.1 ? "PASS" : "FAIL") \($0.0)" }
        lines += ["EXPECTED_CHECKS: \(expected)", "RAN_CHECKS: \(results.count)",
                  results.count == expected && results.allSatisfy { $0.1 } ? "RESULT: ALL PASS" : "RESULT: FAIL"]
        report = lines.joined(separator: "\n")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("daily-story-report.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}
