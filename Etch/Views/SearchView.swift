import SwiftUI
import SwiftData

/// Search across activity names, cities, states, races, and dates. Tap a result to zoom.
struct SearchView: View {
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var query = ""

    /// The legacy/modal search uses the same visibility contract as the main scoped search: hidden
    /// activities and activity types disabled in Settings do not get a second life through Search.
    private var searchableRuns: [Run] {
        let scope = ActivitySettings.isVisible(appModel.activityScope) ? appModel.activityScope : .all
        return runs.scoped(to: scope)
    }

    private var results: [Run] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(searchableRuns.prefix(30)) }
        let q = trimmed.lowercased()
        return searchableRuns.filter { RunSearch.matches($0, query: q) }
    }

    var body: some View {
        NavRoot(embedded) {
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
