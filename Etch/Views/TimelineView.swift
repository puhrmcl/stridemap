import SwiftUI
import SwiftData

/// Scrollable running history grouped by month (and year). Tap any run to zoom the map.
struct TimelineView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    private var groups: [RunStatistics.MonthGroup] { RunStatistics(runs).monthGroups }

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView("No Runs Yet", systemImage: "calendar", description: Text("Sync with Strava to build your timeline."))
                } else {
                    List {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.runs) { run in
                                    Button { open(run) } label: { RunRow(run: run) }
                                        .buttonStyle(.plain)
                                }
                            } header: {
                                HStack {
                                    Text(Format.monthYear(group.date))
                                    Spacer()
                                    Text("\(group.runs.count) · \(Format.distance(group.totalDistance, decimals: 0))")
                                        .foregroundStyle(.secondary)
                                }
                                .textCase(nil)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func open(_ run: Run) {
        appModel.select(run)
        appModel.presentedSurface = nil
        dismiss()
    }
}
