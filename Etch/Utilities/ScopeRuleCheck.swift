import SwiftUI

/// Proves the shared activity-scope rule and the reveal lifecycle, on a simulator, in CI.
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
///
/// The second half covers the reveal lifecycle — `Reveal.isRevealable` / `plan` / `next` /
/// `allowsCameraRefit`, which is the same code `HomeView` and `AppModel` call, not a restatement
/// of it. Its defects were all sequencing: completing a reveal against the set a *place overview*
/// shows rather than the route map's own, and clearing the request the instant focus was issued so
/// the filter-refit handler overwrote it in the same update. Both are step sequences over values,
/// so both can be driven here without a map.
///
/// `EXPECTED_CHECKS` is written into the report and asserted by the workflow, so a check that
/// silently stops running is a red job rather than a shorter clean report.
@MainActor
struct ScopeRuleCheckView: View {

    struct Result: Identifiable {
        let id = UUID()
        let name: String
        let passed: Bool
        let detail: String
    }

    /// How many assertions this screen is supposed to make. Written into the report and checked
    /// by the workflow, so a check that stops running — an early return, a block that throws, a
    /// case someone deleted — fails the job instead of producing a shorter all-green report.
    static let expectedChecks = 26

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

        out += revealChecks()

        // The count is itself an assertion, so an on-screen run is as honest as the report.
        if out.count != Self.expectedChecks {
            out.append(Result(name: "Check count",
                              passed: false,
                              detail: "expected \(Self.expectedChecks) checks, ran \(out.count)"))
        }

        results = out
        running = false
        writeReport(out)
    }

    // MARK: The reveal lifecycle

    /// Drives `Reveal` — the same functions `HomeView` and `AppModel` call — through the sequences
    /// that were broken.
    private func revealChecks() -> [Result] {
        var out: [Result] = []

        func expect(_ name: String, _ actual: some Equatable, _ wanted: some Equatable, _ note: String) {
            let passed = "\(actual)" == "\(wanted)"
            out.append(Result(name: name, passed: passed,
                              detail: passed ? note : "expected \(wanted), got \(actual) — \(note)"))
        }

        let target = activity(.run)
        let other = activity(.run)
        let drawn: Set<UUID> = [target.id, other.id]
        let pending = RevealRequest(runID: target.id, token: 1)
        let focused = RevealRequest(runID: target.id, token: 1, phase: .focused)

        withTypes(runs: true, hikes: true) {

            // ── The headline scenario: a result tapped from a location overlay while a browse
            // filter that excludes it is active. Every step in order, on the real functions.

            // A Favourites filter the target does not satisfy is a query, not a preference.
            var conflicting = RunFilter()
            conflicting.mode = .favorites
            expect("Overlay + conflicting filter: the filter is cleared",
                   Reveal.plan(for: target, scope: .all, filter: conflicting).clearsFilter, true,
                   "target is not a favourite, so the browse query is replaced by the reveal")

            // Step 1 — the route map is at opacity 0 behind the overlay. Even though the target is
            // in the set handed in (during an overlay that set is the *scoped* one), the reveal
            // must leave the overlay rather than focus an invisible map.
            expect("Overlay + conflicting filter: step 1 leaves the overlay",
                   Reveal.next(request: pending, showLocations: true,
                               drawnRunIDs: drawn, isAdmissible: true),
                   RevealStep.exitLocationOverlay,
                   "membership is not sufficient while a place overview covers the route map")

            // Step 2 — overlay gone, filter cleared, so the route map's own set now holds it.
            expect("Overlay + conflicting filter: step 2 focuses",
                   Reveal.next(request: pending, showLocations: false,
                               drawnRunIDs: drawn, isAdmissible: true),
                   RevealStep.focus(runID: target.id),
                   "the target is in the route map's input and the map is on screen")

            // Step 3 — the focus is issued but unread. The refit handlers must stay down.
            expect("Overlay + conflicting filter: step 3 protects the focus",
                   Reveal.allowsCameraRefit(request: focused), false,
                   "clearing the request at focus time is how the filter refit used to overwrite it")

            expect("The refit resumes once the map has consumed the command",
                   Reveal.allowsCameraRefit(request: nil), true,
                   "finishReveal is driven by the map clearing `command`, not by issuing it")

            // ── The rest of the lifecycle.

            expect("A focused reveal issues no second command",
                   Reveal.next(request: focused, showLocations: false,
                               drawnRunIDs: drawn, isAdmissible: true),
                   RevealStep.wait,
                   "only a pending request may move the camera")

            expect("Drawable-but-absent waits rather than abandoning",
                   Reveal.next(request: pending, showLocations: false,
                               drawnRunIDs: [other.id], isAdmissible: true),
                   RevealStep.wait,
                   "a rebuild is still coming; the request stays outstanding")

            expect("Inadmissible target abandons rather than hanging",
                   Reveal.next(request: pending, showLocations: false,
                               drawnRunIDs: [], isAdmissible: false),
                   RevealStep.abandon,
                   "nothing will ever make it drawable, so the request must not stay outstanding")

            expect("Abandon outranks the overlay",
                   Reveal.next(request: pending, showLocations: true,
                               drawnRunIDs: [], isAdmissible: false),
                   RevealStep.abandon,
                   "no point leaving a place overview to reach a run that can never be drawn")

            // Repeated selection of the same activity: the token is what makes it a new value, so
            // the second tap is observable even though the id is identical.
            let again = RevealRequest(runID: target.id, token: 2)
            expect("Repeat selection of the same activity re-fires",
                   again == pending, false,
                   "same runID, advanced token — onChange sees a change and re-focuses")
            expect("Repeat selection focuses again",
                   Reveal.next(request: again, showLocations: false,
                               drawnRunIDs: drawn, isAdmissible: true),
                   RevealStep.focus(runID: target.id),
                   "a second tap on the same result must move the camera a second time")

            // ── Visibility outranks Search, checked before anything is assigned.
            expect("A hidden activity is not revealable",
                   Reveal.isRevealable(activity(.run, hidden: true)), false,
                   "rejected before selectedRunID is touched, so a stray result changes nothing")

            expect("A visible activity is revealable",
                   Reveal.isRevealable(target), true,
                   "the ordinary case")

            // A conflicting *type* selection widens to All; it never narrows to a disabled type.
            expect("A conflicting type selection widens to All",
                   Reveal.plan(for: activity(.hike), scope: .runs, filter: RunFilter()).scope,
                   ActivityScope.all,
                   "the smallest change that admits a hike while Runs is selected")

            expect("A matching type selection is left alone",
                   Reveal.plan(for: target, scope: .runs, filter: RunFilter()).scope,
                   ActivityScope.runs,
                   "no reason to widen — the map already draws this type")

            expect("An inactive filter is not cleared",
                   Reveal.plan(for: target, scope: .all, filter: RunFilter()).clearsFilter, false,
                   "a reveal changes only what actually blocks it")
        }

        // A type disabled in Settings is unreachable through Search, whatever the result list says.
        withTypes(runs: true, hikes: false) {
            expect("A disabled type is not revealable",
                   Reveal.isRevealable(activity(.hike)), false,
                   "Settings outranks a search result")
        }

        return out
    }

    private func writeReport(_ results: [Result]) {
        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        var lines = ["scope-rule \(AppInfo.changeTag)"]
        for result in results {
            lines.append("\(result.passed ? "PASS" : "FAIL")  \(result.name) — \(result.detail)")
        }
        // The workflow reads all three: a missing or mismatched count is as much a failure as a
        // FAIL line, because a report that simply stopped early would otherwise look clean.
        lines.append("EXPECTED_CHECKS: \(Self.expectedChecks)")
        lines.append("RAN_CHECKS: \(results.count)")
        let ok = results.allSatisfy(\.passed) && results.count == Self.expectedChecks
        lines.append(ok ? "RESULT: ALL PASS" : "RESULT: FAIL")
        try? lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("scope-rule-report.txt"),
            atomically: true, encoding: .utf8
        )
    }
}
