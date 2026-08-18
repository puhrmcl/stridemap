import SwiftUI
import SwiftData

/// The map's bottom sheet — an Apple Maps-style live search that slides up. A search field heads
/// the sheet; focusing it expands the sheet to full height (keyboard and all) and shows live run
/// results as you type. When empty it shows Explore shortcuts and recent runs. Explore pages push
/// within the same sheet; tapping a result opens that run.
struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var detent: PresentationDetent = .medium

    /// One Explore destination (a pushable surface).
    private struct Item: Identifiable {
        let surface: AppModel.Surface
        let title: String
        let subtitle: String
        let icon: String
        var id: String { surface.rawValue }
    }

    private let exploreSection: [Item] = [
        Item(surface: .timeline, title: "Timeline", subtitle: "Browse your history by year", icon: "square.grid.2x2"),
        Item(surface: .highlights, title: "Achievements", subtitle: "Records, reach, and recaps", icon: "trophy"),
        Item(surface: .studio, title: "Studio", subtitle: "Turn a run into a print", icon: "photo.artframe"),
        Item(surface: .filters, title: "Filter", subtitle: "Activity, distance, time, location…", icon: "line.3.horizontal.decrease")
    ]

    private var results: [Run] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if query.isEmpty {
                        exploreList
                        recentRuns
                    } else {
                        resultsList
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { searchHeader }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppModel.Surface.self) { destination(for: $0) }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Focusing the field slides the sheet up to full height (Apple Maps behaviour).
        .onChange(of: searchFocused) { _, focused in
            if focused { withAnimation { detent = .large } }
        }
    }

    // MARK: Search header

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Search runs, places, dates…", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.regularMaterial, in: .capsule)

            Button { appModel.presentedSurface = .profile } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.bar)
    }

    // MARK: Empty state

    private var exploreList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore")
                .font(.system(.title3, design: .rounded).weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(exploreSection.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 60) }
                    NavigationLink(value: item.surface) { row(item) }
                        .buttonStyle(.plain)
                }
            }
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var recentRuns: some View {
        let recent = Array(runs.prefix(8))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, run in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Button { open(run) } label: { RunRow(run: run).padding(.horizontal, 12).padding(.vertical, 8) }
                            .buttonStyle(.plain)
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 18))
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, run in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Button { open(run) } label: { RunRow(run: run).padding(.horizontal, 12).padding(.vertical, 8) }
                            .buttonStyle(.plain)
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 18))
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func destination(for surface: AppModel.Surface) -> some View {
        switch surface {
        case .filters:    FilterView(embedded: true)
        case .timeline:   TimelineView(embedded: true)
        case .highlights: HighlightsView(embedded: true)
        case .studio:     StudioHomeView(embedded: true)
        default:          EmptyView()
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accentOnGlass)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func open(_ run: Run) {
        appModel.select(run)
        appModel.presentedSurface = nil
    }
}
