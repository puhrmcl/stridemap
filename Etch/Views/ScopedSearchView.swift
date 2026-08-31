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
                if trimmed.isEmpty {
                    starter
                } else {
                    // Records lead from Achievements, because on that tab they *are* the answer —
                    // "furthest" is a question about the history, not about one activity.
                    if !matchingRecords.isEmpty && includesRecords {
                        Section("Records") {
                            ForEach(matchingRecords) { record in
                                Button { open(record.run) } label: { recordRow(record) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
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
                    if matchingRuns.isEmpty && matchingProducts.isEmpty && matchingRecords.isEmpty {
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

    // MARK: Before anything is typed

    /// What the screen offers instead of nothing.
    ///
    /// An empty search page was a black rectangle, which is a waste of the one surface every tab
    /// leads to — and worse than a waste here, because this search is far wider than it looks.
    /// `haystack(for:)` matches a name, a place, a date, a year, a distance in two forms, an
    /// elevation, an activity type, the word "race" — and an activity's own **notes**. Nobody
    /// would guess any of that from a prompt reading "Search your activities".
    ///
    /// So the empty state teaches, using this person's own history as the examples: every chip is
    /// a query drawn from what they actually have, which means none of them can return nothing.
    @ViewBuilder private var starter: some View {
        if !suggestions.isEmpty {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { term in
                            Button { query = term } label: {
                                Text(term)
                                    .font(.etch(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 13).padding(.vertical, 7)
                                    .background(Theme.accent.opacity(0.12), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            } header: {
                Text("Try these")
            } footer: {
                Text("Search covers names, places, dates, distances and activity types — and anything you wrote in an activity's notes.")
            }
        }

        // From Achievements the records are the shelf worth opening on — the whole page is
        // records, and a search reached from it should not start by offering last Tuesday's run.
        if includesRecords, !records.isEmpty {
            Section("Records") {
                ForEach(records.prefix(6)) { record in
                    Button { open(record.run) } label: { recordRow(record) }
                        .buttonStyle(.plain)
                }
            }
        }

        if includesActivities, !recent.isEmpty {
            Section("Recent") {
                ForEach(recent, id: \.id) { run in
                    Button { open(run) } label: { runRow(run) }
                        .buttonStyle(.plain)
                }
            }
        }

        // Studio excludes activities from its results, so offering recent ones there would promise
        // something a search from this scope will not deliver. The catalogue is the useful answer
        // from a storefront anyway.
        if includesProducts, !catalogue.isEmpty {
            Section("Products") {
                ForEach(catalogue, id: \.self) { name in
                    Button { query = name } label: {
                        Label(name, systemImage: "photo.artframe")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The eight most recent activities — "the one from Tuesday" is the commonest reason anyone
    /// opens a search, and it needs no typing at all.
    private var recent: [Run] { Array(runs.prefix(8)) }

    private var catalogue: [String] { StudioProduct.offered.map(\.name) }

    /// Example queries, each drawn from this history so each one returns results.
    ///
    /// Ordered by how much they teach: a place and a year are what people expect to work; a bare
    /// distance figure and an activity type are the two that surprise them.
    private var suggestions: [String] {
        var out: [String] = []
        let stats = RunStatistics(runs)

        if let city = stats.travelPlaces.first?.label
            .components(separatedBy: ", ").first, !city.isEmpty {
            out.append(city)
        }
        if let year = stats.years.first { out.append(String(year)) }
        if runs.contains(where: \.isRace) { out.append("race") }

        // From Achievements, lead with the words that find a record. They are the reason someone
        // reached for search from that page, and they are also the least guessable thing here.
        if includesRecords, !records.isEmpty {
            out.insert(contentsOf: ["furthest", "fastest"].filter { term in
                records.contains { $0.haystack.contains(term) }
            }, at: 0)
        }

        // A distance they own, in the form the app prints it — which is the form that matches.
        if let longest = runs.max(by: { $0.distance < $1.distance }) {
            let figure = String(format: "%.1f", Format.distanceValue(longest.distance))
            if figure != "0.0" { out.append(figure) }
        }

        // A type they actually have, and not the one they have most of — the point is to show
        // that type is searchable at all.
        let types: [ActivityScope] = [.hikes, .rides, .walks, .runs]
        if let other = types.first(where: { scope in
            guard let type = scope.activityType else { return false }
            return runs.contains { $0.activityType == type }
        }) {
            out.append(other.singularNoun)
        }

        // A second place, if there is one worth naming.
        if stats.travelPlaces.count > 1,
           let second = stats.travelPlaces.dropFirst().first?.label
            .components(separatedBy: ", ").first, !second.isEmpty, !out.contains(second) {
            out.append(second)
        }

        return Array(out.prefix(6))
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

    /// Records answer from Achievements, and from an unscoped search. They are deliberately not
    /// offered from the Map or Studio: a record is a fact about the whole history, and a search
    /// scoped to a storefront that returned "Fastest Pace" would be answering a question nobody
    /// standing there asked.
    private var includesRecords: Bool {
        guard let activeScope else { return true }
        return activeScope == .achievements
    }

    /// The records this history holds, from the same list Achievements renders.
    private var records: [RunStatistics.Record] {
        RunStatistics(runs.countingTotals).records(usesPace: appModel.activityScope.usesPace)
    }

    private var matchingRecords: [RunStatistics.Record] {
        let q = trimmed.lowercased()
        guard !q.isEmpty else { return [] }
        return records.filter { $0.haystack.contains(q) }
    }

    private func recordRow(_ record: RunStatistics.Record) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(record.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(record.value)
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .contentShape(.rect)
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
