import SwiftUI
import SwiftData

/// One search, scoped by where you were standing.
///
/// The scope changes with the tab; the tool never does. That distinction is the whole design: a
/// corner button that finds activities on one tab and *becomes map controls* on another is two
/// buttons wearing one coat, and it destroys the muscle memory a fixed position exists to build.
/// So this always searches, and only its results belong to where you came from.
///
/// The scope is shown, never implied. A chip names where it is looking and turns off to search
/// everything — because scope you cannot see reads as a bug the first time someone looks for their
/// marathon from Studio and is told there is nothing.
struct ScopedSearchView: View {
    /// The tab the person was on when they reached for search.
    var scope: EtchTab

    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var query = ""
    /// False once the chip is dismissed — the search then covers everything.
    @State private var scoped = true

    private var activeScope: EtchTab? { scoped ? scope : nil }

    var body: some View {
        NavigationStack {
            List {
                if !trimmed.isEmpty {
                    if !matchingRuns.isEmpty && includesActivities {
                        Section("Activities") {
                            ForEach(matchingRuns.prefix(20), id: \.id) { run in
                                Button { open(run) } label: { runRow(run) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    if !matchingProducts.isEmpty && includesProducts {
                        Section("Products") {
                            ForEach(matchingProducts, id: \.self) { name in
                                Label(name, systemImage: "photo.artframe")
                            }
                        }
                    }
                    if matchingRuns.isEmpty && matchingProducts.isEmpty {
                        ContentUnavailableView.search(text: trimmed)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            // The mark in place of the word. Search is the one surface reached from every tab,
            // and it was the one with no sign of whose app it belonged to — the field below says
            // "search" more plainly than a title ever did, so the slot is better spent on the
            // brand. The title stays set for VoiceOver, which reads it rather than the image.
            .toolbar {
                // Takes the shared header size rather than a literal of its own. Search sat at
                // 17 while every other page sat at 20, which read as the brand shrinking when
                // you reached the one surface every tab leads to.
                ToolbarItem(placement: .principal) { EtchWordmark(height: EtchHeaderMetrics.mark) }
            }
            .searchable(text: $query, prompt: scope.searchPrompt)
            .safeAreaInset(edge: .top, spacing: 0) {
                if scoped { scopeChip }
            }
        }
    }

    /// "Searching in Studio ⊗" — the scope made visible, and removable.
    private var scopeChip: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { scoped = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: scope.symbol).font(.system(size: 11, weight: .semibold))
                    Text("in \(scope.title)")
                        .font(.etch(.footnote, weight: .semibold))
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.12), in: .capsule)
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Searching in \(scope.title). Tap to search everything.")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: What each scope admits

    /// Activities are the answer nearly everywhere — the Map wants them pinned, the Timeline wants
    /// them by date — so only an unscoped Studio search leaves them out.
    private var includesActivities: Bool {
        guard let activeScope else { return true }
        return activeScope != .studio
    }

    /// The Bag is no longer a tab, so a search can never be scoped to it; Studio is the only
    /// place products are the answer.
    private var includesProducts: Bool {
        guard let activeScope else { return true }
        return activeScope == .studio
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// Everything an activity knows, not just its name and its city.
    ///
    /// The old search read four string fields, which meant the things people actually remember an
    /// activity by were unfindable: how far it was, what they wrote about it afterwards, whether
    /// it was a ride or a hike. "13.1", "marathon", "knee", "2024" and "ride" all now land.
    ///
    /// Numbers are matched on their *formatted* text rather than parsed, so what you can see is
    /// what you can search — "13.1" finds the half because that is what the app printed, and a
    /// unit change moves the search with it instead of leaving it behind.
    private var matchingRuns: [Run] {
        let q = trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return runs.filter { run in
            haystack(for: run).contains(q)
        }
    }

    private func haystack(for run: Run) -> String {
        var parts: [String] = [
            run.name,
            run.city ?? "", run.state ?? "", run.country ?? "",
            run.notes ?? "",
            run.activityType.rawValue,
            Format.date(run.startDate),
            String(Calendar.current.component(.year, from: run.startDate)),
            // Both the number alone and the number with its unit, so "13.1" and "13.1 mi" work.
            Format.distance(run.distance),
            String(format: "%.1f", Format.distanceValue(run.distance)),
            Format.elevationGain(run.elevationGain)
        ]
        if run.isRace { parts.append("race") }
        return parts.joined(separator: " ").lowercased()
    }

    /// The catalogue, by the names a customer would type — the product, not the SKU.
    private var matchingProducts: [String] {
        let q = trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        var names = StudioProduct.offered.map(\.name)
        names += PrintProduct.offered.map(\.name)
        names += PrintProduct.offered.flatMap { product in
            product.sizes.map { "\(product.name) · \($0.label)" }
        }
        return names.filter { $0.lowercased().contains(q) }
    }

    private func runRow(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(run.name)
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
            // Distance is on the row because it is now searchable: a result you matched on
            // "13.1" should show you the 13.1, or the match looks like a mistake.
            Text([Format.date(run.startDate), Format.distance(run.distance), run.city, run.state]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Selecting focuses the map on the run. Search is a way of arriving somewhere, which is the
    /// reason it is a tool beside the tabs rather than a fifth one among them.
    private func open(_ run: Run) {
        appModel.select(run)
    }
}
