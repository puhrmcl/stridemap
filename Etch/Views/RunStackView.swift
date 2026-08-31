import SwiftUI

/// A pick-list for runs stacked at (nearly) the same start location, so overlapping pins can
/// be told apart. Shown when a tight map cluster is tapped; each row opens that run's detail.
struct RunStackView: View {
    let runs: [Run]

    var body: some View {
        NavigationStack {
            List(runs, id: \.id) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    RunStackRow(run: run)
                }
            }
            .listStyle(.plain)
            .navigationTitle("\(runs.count) \(ActivityScope.noun(for: runs)) here")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct RunStackRow: View {
    let run: Run

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.run")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.accent, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.name)
                    .font(.etch(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text(Format.date(run.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.distance(run.distance))
                    .font(.etch(.subheadline, weight: .semibold))
                Text(Format.duration(run.movingTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
