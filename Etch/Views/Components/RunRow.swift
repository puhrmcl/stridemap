import SwiftUI

/// A compact list row for a single run — used in Timeline, Search, and Travel details.
struct RunRow: View {
    let run: Run
    var showPlace: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            // A cached, static MapKit *snapshot* of the route — not a live `Map`. A list can show
            // dozens of these, and a live `RunPreviewMap` per row spins up an MKMapView each, which
            // both stutters the search sheet during a drag (every row recomposites) and exhausts
            // MapKit on a broad match. `RouteMapTile` draws a placeholder vector route immediately,
            // then swaps in a snapshot cached by `PosterMap.tileImage` (keyed by run + size + edit),
            // so scrolling and dragging stay smooth and repeat views are free.
            RouteMapTile(run: run)
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 14))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.name)
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
                Text(Format.distance(run.distance))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                Text(Format.duration(run.movingTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
