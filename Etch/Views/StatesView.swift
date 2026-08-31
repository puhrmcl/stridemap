import SwiftUI
import SwiftData

/// "States you've run in": a shaded US map plus a ranked list. A state fills in the moment
/// any run started inside it; deeper blue means more runs there.
struct StatesView: View {
    @Query private var runs: [Run]

    @State private var counts: [String: Int] = [:]
    @State private var didCompute = false

    private var maxCount: Int { counts.values.max() ?? 1 }

    /// Boundary name → √-compressed fill intensity, so a single-run state is clearly visible
    /// while heavily-run states read deeper without swamping everything else.
    private var intensities: [String: Double] {
        counts.mapValues { min(1, (Double($0) / Double(maxCount)).squareRoot()) }
    }

    /// Distinct *states* visited (DC / territories excluded from the 50-state goal).
    private var visitedStates: Int {
        counts.keys.filter { USStateBoundaries.shared.isState($0) }.count
    }

    private var percent: Int {
        Int((Double(visitedStates) / Double(USStateBoundaries.shared.stateGoal) * 100).rounded())
    }

    private var ranked: [(name: String, count: Int)] {
        counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                StatesMapView(intensities: intensities)
                    .frame(height: 360)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .overlay(alignment: .bottom) {
                        if didCompute && counts.isEmpty { emptyHint }
                    }
                if !ranked.isEmpty { stateList }
            }
            .padding(20)
        }
        .navigationTitle("States")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !didCompute else { return }
            computeCounts()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(visitedStates)")
                    .font(.etch(size: 44, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text("of \(USStateBoundaries.shared.stateGoal) states")
                    .font(.etch(.title3, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(visitedStates), total: Double(USStateBoundaries.shared.stateGoal))
                .tint(Theme.accent)
            Text("\(percent)% of the map")
                .font(.etch(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cardRadius))
    }

    private var stateList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where you've been")
                .font(.etch(.title3, weight: .bold))

            ForEach(ranked, id: \.name) { item in
                StateRow(name: item.name, count: item.count,
                         fraction: Double(item.count) / Double(maxCount),
                         scope: ActivityScope.of(runs))
                    .id(item.name)
            }
        }
    }

    private var emptyHint: some View {
        Text("States appear once your activities have GPS locations.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(10)
            .glassBackground(cornerRadius: 14)
            .padding(.bottom, 12)
    }

    /// Attributes each run's start point to a state via point-in-polygon. Bounded work
    /// (bounding-box prefiltered), run once when the screen appears.
    private func computeCounts() {
        var result: [String: Int] = [:]
        for run in runs {
            guard let coordinate = run.startCoordinate,
                  let name = USStateBoundaries.shared.region(containing: coordinate) else { continue }
            result[name, default: 0] += 1
        }
        counts = result
        didCompute = true
    }
}

/// One state's row: name, run count, and a bar showing its share relative to your top state.
private struct StateRow: View {
    let name: String
    let count: Int
    let fraction: Double
    /// The word this list counts in, worked out once by the parent from the whole history.
    ///
    /// One noun for the whole list rather than one per state. A state could hold nothing but
    /// hikes while the history is mixed, and naming each row from its own activities would be
    /// more precise and read as broken — "12 hikes" above "9 activities" above "4 runs" looks
    /// like a bug, not like precision.
    let scope: ActivityScope

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.etch(.subheadline, weight: .semibold))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Theme.accent)
                            .frame(width: max(6, geo.size.width * max(0.03, fraction)))
                    }
                }
                .frame(height: 6)
            }
            Text("\(count)")
                .font(.etch(.headline))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(scope.noun(count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
