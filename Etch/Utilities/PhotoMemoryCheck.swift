import SwiftUI
import SwiftData

/// Executes the production association/memory functions, including a disk-store reopen.
/// No photo permission or real user images are needed for these fixtures.
@MainActor
struct PhotoMemoryCheckView: View {
    @State private var report = "Running photo memory checks…"
    private static let expectedChecks = 26

    var body: some View {
        ScrollView { Text(report).font(.system(.caption, design: .monospaced)).padding() }
            .task { runChecks() }
    }

    private func fixture(_ date: Date) -> Run {
        Run(provider: .healthKit, name: "Memory fixture", startDate: date,
            distance: 5000, movingTime: 1500, elapsedTime: 1800, elevationGain: 0,
            summaryPolyline: "", photoReferences: ["cover", "second"])
    }

    private func runChecks() {
        var results: [(String, Bool)] = []
        func check(_ name: String, _ passed: Bool) { results.append((name, passed)) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ year: Int, _ month: Int = 9, _ day: Int = 7, _ hour: Int = 12) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let defaults = UserDefaults.standard
        let keys = ["includeRuns", "includeHikes", "includeRides", "includeWalks"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.set(true, forKey: key) }
        let run = fixture(date(2025))
        check("New models have empty correction lists", run.rejectedPhotoReferences.isEmpty && run.memoryHiddenPhotoReferences.isEmpty)
        run.attachPhotos(["cover", "second", "cover"], manually: false)
        check("Automatic attachment is idempotent", run.photoReferences == ["cover", "second"])
        let index = run.rejectPhoto("cover")!
        check("Reject removes association", run.photoReferences == ["second"])
        let assets = ["cover", "second"].map { PhotoLibrary.AssetInfo(id: $0, date: run.startDate, coordinate: nil) }
        check("Bulk matching excludes rejected asset", PhotoLibrary.match(run: run, in: assets) == ["second"])
        run.attachPhotos(["cover"], manually: false)
        check("Rescan cannot restore rejection", run.photoReferences == ["second"])
        let other = fixture(date(2025))
        check("Reject does not affect another activity", other.photoReferences.contains("cover"))
        check("Gallery identity carries activity", GalleryPhoto(photoID: "cover", run: run).id != GalleryPhoto(photoID: "cover", run: other).id)
        run.restorePhoto("cover", at: index)
        check("Undo restores cover order", run.photoReferences == ["cover", "second"])
        check("Undo clears rejection", run.rejectedPhotoReferences.isEmpty)
        run.setPhotoHiddenFromMemories("cover", hidden: true)
        check("Hide chooses next memory cover", run.memoryPhotoReferences == ["second"])
        check("Hide keeps activity association", run.photoReferences == ["cover", "second"])
        run.setPhotoHiddenFromMemories("cover", hidden: false)
        check("Memory hiding is reversible", run.memoryPhotoReferences == run.photoReferences)
        run.rejectPhoto("cover")
        run.attachPhotos(["cover"], manually: true)
        check("Manual re-add intentionally clears rejection", run.photoReferences.contains("cover") && run.rejectedPhotoReferences.isEmpty)

        let now = date(2026)
        func memories(_ activities: [Run], at day: Date? = nil, scope: ActivityScope = .all) -> [PhotoMemory] {
            PhotoMemories.onThisDay(in: activities, scope: scope, now: day ?? now, calendar: calendar)
        }
        check("Exact anniversary is one year", memories([run]).first?.yearsAgo == 1)
        check("Same-year activity is not an anniversary", memories([fixture(now)]).isEmpty)
        check("Neighboring dates are not on this day", memories([fixture(date(2025, 9, 6))]).isEmpty)
        run.excludedFromTotals = true
        check("Excluded totals do not erase memories", memories([run]).count == 1)
        run.isHidden = true
        check("Hidden activity stays out", memories([run]).isEmpty)
        run.isHidden = false
        run.isHiddenFromMemories = true
        check("Dismissed memory stays out", memories([run]).isEmpty)
        run.isHiddenFromMemories = false
        for id in run.photoReferences { run.setPhotoHiddenFromMemories(id, hidden: true) }
        check("All photos hidden gives no photo memory", memories([run]).isEmpty)
        for id in run.photoReferences { run.setPhotoHiddenFromMemories(id, hidden: false) }
        defaults.set(false, forKey: "includeRuns")
        check("Disabled type stays out", memories([run]).isEmpty)
        defaults.set(true, forKey: "includeRuns")
        check("Explicit empty scope stays empty", memories([run], scope: .hikes).isEmpty)
        let leap = fixture(date(2024, 2, 29))
        check("Leap anniversary not invented on February 28", memories([leap], at: date(2025, 2, 28)).isEmpty)
        check("Leap anniversary on exact leap day", memories([leap], at: date(2028, 2, 29)).first?.yearsAgo == 4)
        var pacific = calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let nearMidnight = fixture(date(2025, 9, 8, 1))
        check("Calendar timezone controls the remembered date", PhotoMemories.onThisDay(in: [nearMidnight], scope: .all, now: now, calendar: pacific).count == 1)

        do {
            check("Corrections survive a disk store reopen", try persistenceCheck(date: date(2025)))
        } catch {
            check("Corrections survive a disk store reopen: \(error)", false)
        }
        var lines = results.map { "\($0.1 ? "PASS" : "FAIL") \($0.0)" }
        lines.append("EXPECTED_CHECKS: \(Self.expectedChecks)")
        lines.append("RAN_CHECKS: \(results.count)")
        lines.append(results.count == Self.expectedChecks && results.allSatisfy { $0.1 } ? "RESULT: ALL PASS" : "RESULT: FAIL")
        report = lines.joined(separator: "\n")
        do {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try report.write(to: directory.appendingPathComponent("photo-memory-report.txt"), atomically: true, encoding: .utf8)
        } catch { report += "\nCould not write report: \(error)" }
    }

    private func writeFixture(url: URL, date: Date) throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let run = fixture(date)
        context.insert(run)
        run.rejectPhoto("cover")
        run.setPhotoHiddenFromMemories("second", hidden: true)
        run.isHiddenFromMemories = true
        try context.save()
    }

    private func persistenceCheck(date: Date) throws -> Bool {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("memory.store")
        try writeFixture(url: url, date: date)
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        guard let run = try context.fetch(FetchDescriptor<Run>()).first else { return false }
        run.attachPhotos(["cover"], manually: false)
        return run.photoReferences == ["second"] && run.rejectedPhotoReferences == ["cover"]
            && run.memoryHiddenPhotoReferences == ["second"] && run.isHiddenFromMemories
    }
}
