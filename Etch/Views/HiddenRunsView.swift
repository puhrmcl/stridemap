import SwiftUI
import SwiftData

/// Lists runs the user has hidden and lets them bring any back. Hidden runs stay in the store (so a
/// synced run isn't re-imported as new) but are excluded from every browsing surface until unhidden.
struct HiddenRunsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    private var hidden: [Run] { runs.filter(\.isHidden) }

    var body: some View {
        Group {
            if hidden.isEmpty {
                ContentUnavailableView(
                    "No Hidden Runs",
                    systemImage: "eye",
                    description: Text("Runs you hide from the run detail screen appear here, where you can bring them back.")
                )
            } else {
                List {
                    ForEach(hidden) { run in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.name)
                                    .font(.system(.body, design: .default).weight(.medium))
                                Text("\(run.startDate.formatted(date: .abbreviated, time: .omitted)) · \(Format.distance(run.distance, decimals: 1))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unhide") { unhide(run) }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hidden Runs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unhide(_ run: Run) {
        run.isHidden = false
        run.updatedAt = Date()
        try? context.save()
    }
}
