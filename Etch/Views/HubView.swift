import SwiftUI

/// The map's "explore" hub — an Apple Maps-style sheet opened from the bottom bar, giving access
/// to every Etch surface grouped in sections. Selecting an item swaps this sheet for that surface
/// (both ride the map's single sheet, keyed by `presentedSurface`). Profile is reachable from the
/// bottom bar's always-visible avatar, and also here.
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section(_ title: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 60) }
                    row(item)
                }
            }
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
        }
    }

    private func row(_ item: Item) -> some View {
        Button {
            // Swap this sheet for the chosen surface by re-pointing the single presented surface.
            appModel.presentedSurface = item.surface
        } label: {
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
        .buttonStyle(.plain)
    }
}
