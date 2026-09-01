import SwiftUI
import SwiftData
import MapKit

/// Lists route-less runs with no location — indoor/treadmill runs and GPS-less imports — so the
/// user can drop each one onto the map by hand. Etch suggests a nearby spot from recent runs.
struct UnmappedRunsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]
    @State private var picking: Run?

    private var unmapped: [Run] { allRuns.filter { $0.needsLocation && !$0.isHidden } }

    var body: some View {
        List {
            if unmapped.isEmpty {
                ContentUnavailableView(
                    "Everything's on the map",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Activities without GPS — indoor or treadmill efforts — show up here so you can place them on the map.")
                )
            } else {
                Section {
                    ForEach(unmapped) { run in
                        Button { picking = run } label: { row(run) }
                            .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Tap an activity to place it on the map. Etch suggests a nearby spot from your recent activities — confirm it or drag to adjust.")
                }
            }
        }
        .navigationTitle("Unmapped Activities")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picking) { run in
            LocationPickerView(title: run.name, start: suggestion(for: run)) { coordinate in
                run.setManualLocation(coordinate)
                try? context.save()
            }
        }
    }

    private func row(_ run: Run) -> some View {
        HStack(spacing: 12) {
            Image(systemName: run.isIndoor ? IndoorGlyph.symbol : "mappin.slash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text("\(Format.date(run.startDate)) · \(Format.distance(run.distance))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "mappin.and.ellipse").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    /// The most recent located run to seed the pin near — the user's likely gym/home.
    private func suggestion(for run: Run) -> CLLocationCoordinate2D? {
        allRuns
            .filter { $0.id != run.id && $0.startCoordinate != nil }
            .min { abs($0.startDate.timeIntervalSince(run.startDate)) < abs($1.startDate.timeIntervalSince(run.startDate)) }?
            .startCoordinate
    }
}
