import SwiftUI

/// Proves the shared activity-scope rule, on a simulator, in CI.
///
/// Map, Timeline, Milestones, Search, Studio and Profile all have to answer "which activities is
/// the reader looking at?" the same way. They previously did not: four surfaces carried their own
/// copy of a "if only one type has activities, use that one" shortcut that ran *before* consulting
/// the selection, while Search and Profile honoured the selection directly. With a runs-only
/// library and Hikes enabled, choosing Hikes left the map showing runs and Search showing nothing.
///
/// `ActivitySettings.resolvedScope` is now the single answer, and it is pure logic over values —
/// which makes it exactly the thing worth pinning down. There is no test target in this project,
/// so this runs as a preview screen (`ETCH_PREVIEW=scope-rule`) and reports on screen and as text,
/// the same way `PrintEngineCheckView` does.
@MainActor
struct ScopeRuleCheckView: View {

    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    @State private var results: [Result] = []
    @State private var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scope rule")
                    .font(.etch(.title2, weight: .bold))
                Spacer()
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Text(results.allSatisfy(\.passed) ? "ALL PASS" : "FAIL")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(results.allSatisfy(\.passed) ? .green : .red, in: .capsule)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.etch(size: 13, weight: .semibold))
                                Text(result.detail)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .task { run() }
    }

    // MARK: Fixtures

    /// A minimal in-memory activity. Never inserted into a `ModelContext` — the scope rule only
    /// reads stored properties, so a bare instance is the whole fixture.
    private func activity(_ type: ActivityType, hidden: Bool = false,
                          excludedFromTotals: Bool = false) -> Run {
        let run = Run(
            provider: .healthKit,
            name: "check-\(type.rawValue)",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            distance: 5_000, movingTime: 1_500, elapsedTime: 1_500,
            elevationGain: 0, summaryPolyline: "",
            sportType: type.rawValue,
            excludedFromTotals: excludedFromTotals
        )
        run.activityType = type
        run.isHidden = hidden
        return run
    }

    /// Runs the body with the four Settings toggles forced, then restores them. The check screen
    /// only ever runs in a throwaway simulator, but leaving a reader's settings rewritten would be
    /// unacceptable even there.
    private func withTypes(runs: Bool = true, hikes: Bool = true, rides: Bool = true,
                           walks: Bool = false, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = ["includeRuns", "includeHikes", "includeRides", "includeWalks"]
            .map { ($0, defaults.object(forKey: $0)) }
        defaults.set(runs, forKey: "includeRuns")
        defaults.set(hikes, forKey: "includeHikes")
        defaults.set(rides, forKey: "includeRides")
        defaults.set(walks, forKey: "includeWalks")
        body()
        for (key, value) in previous {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    // MARK: The checks

    private func run() {
        var out: [Result] = []

        func expect(_ name: String, _ actual: some Equatable, _ wanted: some Equatable, _ note: String) {
            let passed = "\(actual)" == "\(wanted)"
            out.append(Result(name: name, passed: passed,
                              detail: passed ? note : "expected \(wanted), got \(actual) — \(note)"))
        }

        let runsOnly = [activity(.run), activity(.run)]
        let mixed = [activity(.run), activity(.hike)]

        withTypes(runs: true, hikes: true) {
            // The reported bug: an explicit, enabled, *empty* selection must survive.
            expect("Explicit empty type survives",
                   ActivitySettings.resolvedScope(.hikes, in: runsOnly), ActivityScope.hikes,
                   "runs-only library, Hikes enabled and selected → stays Hikes, shows an honest empty state")

            // …and must remain escapable, or the reader is stranded in an empty scope.
            expect("Chooser stays offered in an empty scope",
                   ActivitySettings.offersActivityChoice(.hikes, in: runsOnly), true,
                   "the switcher is the only way back out of an intentionally empty scope")

            // The presentation shortcut is still allowed — but only for All.
            expect("All collapses to the sole populated type",
                   ActivitySettings.resolvedScope(.all, in: runsOnly), ActivityScope.runs,
                   "identical sets, so this is presentation rather than filtering")

            expect("No chooser when there is nothing to choose",
                   ActivitySettings.offersActivityChoice(.all, in: runsOnly), false,
                   "one populated type and no explicit selection → the selector collapses")

            expect("Explicit choice honoured in a mixed library",
                   ActivitySettings.resolvedScope(.hikes, in: mixed), ActivityScope.hikes,
                   "two populated types → the selection is simply obeyed")
        }

        // A type disabled in Settings cannot be the selection, whatever is stored.
        withTypes(runs: true, hikes: false) {
            expect("Disabled type falls back to All",
                   ActivitySettings.resolvedScope(.hikes, in: runsOnly), ActivityScope.all,
                   "Hikes turned off in Settings → the stored scope heals to All")

            expect("Disabled type is not populated",
                   ActivitySettings.populatedScopes(in: mixed).contains(.hikes), false,
                   "a disabled type never counts toward the populated set")
        }

        // Visibility rules outrank everything above.
        withTypes(runs: true, hikes: true) {
            let hiddenHikes = [activity(.run), activity(.hike, hidden: true)]
            expect("Hidden activities do not populate a type",
                   ActivitySettings.populatedScopes(in: hiddenHikes), [ActivityScope.runs],
                   "an activity the reader hid must not make Hikes look populated")

            // Excluded-from-totals is a *counting* rule, not a visibility one: the activity is
            // still on the map, still searchable, still part of its type.
            let notCounted = [activity(.run), activity(.hike, excludedFromTotals: true)]
            expect("Excluded-from-totals still populates its type",
                   ActivitySettings.populatedScopes(in: notCounted), [ActivityScope.runs, ActivityScope.hikes],
                   "kept out of totals, not out of the app")
        }

        results = out
        running = false
        writeReport(out)
    }

    private func writeReport(_ results: [Result]) {
        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        var lines = ["scope-rule \(AppInfo.changeTag)"]
        for result in results {
            lines.append("\(result.passed ? "PASS" : "FAIL")  \(result.name) — \(result.detail)")
        }
        lines.append(results.allSatisfy(\.passed) ? "RESULT: ALL PASS" : "RESULT: FAIL")
        try? lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("scope-rule-report.txt"),
            atomically: true, encoding: .utf8
        )
    }
}
