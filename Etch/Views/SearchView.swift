import SwiftUI
import SwiftData

/// Search across run names, cities, states, races, and dates. Tap a result to zoom.
struct SearchView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var query = ""

    private var results: [Run] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(runs.prefix(30)) }
        let q = trimmed.lowercased()
        return runs.filter { run in
            run.name.lowercased().contains(q)
                || (run.city?.lowercased().contains(q) ?? false)
                || (run.state?.lowercased().contains(q) ?? false)
                || (run.country?.lowercased().contains(q) ?? false)
                || Format.date(run.startDate).lowercased().contains(q)
                || (run.isRace && "race".contains(q))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Recent") { rows }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("\(results.count) results") { rows }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "City, race, name, date…")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private var rows: some View {
        ForEach(results) { run in
            Button { open(run) } label: { RunRow(run: run) }
                .buttonStyle(.plain)
        }
    }

    private func open(_ run: Run) {
        appModel.select(run)
        appModel.presentedSurface = nil
        dismiss()
    }
}
