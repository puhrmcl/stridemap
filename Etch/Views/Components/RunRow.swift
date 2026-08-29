import SwiftUI

/// A compact list row for a single run — used in Timeline, Search, and Travel details.
struct RunRow: View {
    let run: Run
    var showPlace: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            // A real map behind the route (brand-tinted MapKit snapshot, cached per run + size by
            // PosterMap.tileImage). The vector "etched" tile stands in while the snapshot renders
            // and permanently for indoor runs.
            RouteMapTile(run: run)
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 14))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.displayName)
                    .font(.etch(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text(Format.dateTime(run.startDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showPlace, !run.placeLabel.isEmpty {
                    Text(run.placeLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                // Tabular digits so the metric column aligns optically across rows.
                Text(Format.distance(run.distance))
                    .font(.etch(.subheadline, weight: .bold))
                    .monospacedDigit()
                Text(Format.duration(run.movingTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if run.isRace {
                    Label("Race", systemImage: "flag.checkered")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }
}
