import SwiftUI

/// The map's "explore" hub — an Apple Maps-style sheet opened from the bottom bar, giving access
/// to every Etch surface grouped in sections. Selecting an item *pushes* that surface within this
/// same sheet (a smooth navigation), rather than dismissing and re-presenting a new sheet from the
/// bottom. Profile is reachable from the bottom bar's always-visible avatar, and from here.
struct HubView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    /// One hub destination.
    private struct Item: Identifiable {
        let surface: AppModel.Surface
        let title: String
        let subtitle: String
        let icon: String
        var id: String { surface.rawValue }
    }

    private let findSection: [Item] = [
        Item(surface: .search, title: "Search", subtitle: "Find a run by name, place, or date", icon: "magnifyingglass"),
        Item(surface: .filters, title: "Filter", subtitle: "Activity, distance, time, location…", icon: "line.3.horizontal.decrease")
    ]

    private let exploreSection: [Item] = [
        Item(surface: .timeline, title: "Timeline", subtitle: "Browse your history by year", icon: "square.grid.2x2"),
        Item(surface: .highlights, title: "Achievements", subtitle: "Records, reach, and recaps", icon: "trophy"),
        Item(surface: .studio, title: "Studio", subtitle: "Turn a run into a print", icon: "photo.artframe")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Search & Filter", findSection)
                    section("Explore", exploreSection)
                }
                .padding(20)
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { appModel.presentedSurface = .profile } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Profile")
                }
            }
            // Pushed pages render embedded (no own NavigationStack), so they slide in/out within
            // this sheet rather than re-presenting from the bottom.
            .navigationDestination(for: AppModel.Surface.self) { surface in
                destination(for: surface)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func destination(for surface: AppModel.Surface) -> some View {
        switch surface {
        case .search:     SearchView(embedded: true)
        case .filters:    FilterView(embedded: true)
        case .timeline:   TimelineView(embedded: true)
        case .highlights: HighlightsView(embedded: true)
        case .studio:     StudioHomeView(embedded: true)
        default:          EmptyView()
        }
    }

    private func section(_ title: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 60) }
                    NavigationLink(value: item.surface) { row(item) }
                        .buttonStyle(.plain)
                }
            }
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
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
}
