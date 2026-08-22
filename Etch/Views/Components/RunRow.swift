import SwiftUI

/// A compact list row for a single run — used in Timeline, Search, and Travel details.
struct RunRow: View {
    let run: Run
    var showPlace: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            // The "etched" tile: the route as a blue line on a dark vector ground. The earlier map
            // snapshots rendered light (bone-washed) and glared against the dark sheet — three
            // bright squares dominating the page. The etched tile matches the sheet's theme, speaks
            // the brand (ink ground, Etch-Blue line), and is pure vector — no MapKit snapshot at
            // all, so rows cost nothing beyond decoding the route.
            RouteThumbnail(run: run)
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 14))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
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
