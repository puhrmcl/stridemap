import SwiftUI
import SwiftData

/// The Apple Maps-style docked search sheet: always present at the bottom of the map, draggable
/// between a collapsed bar, a mid rest, and full height, with the map live behind it. A search
/// field heads it — focusing expands it; typing shows live run results. When idle it shows Explore
/// shortcuts and recent runs. It's a plain overlay (not a system sheet), so run detail and the
/// other surfaces keep presenting through the map's existing sheet with no conflict.
struct MapSearchSheet: View {
    /// The height available above the top chrome — sets the detent sizes.
    let maxHeight: CGFloat
    /// Reported up so the floating map controls can sit just above the sheet's top edge.
    @Binding var height: CGFloat

    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var dragStart: CGFloat?

    private var collapsed: CGFloat { 96 }
    private var mid: CGFloat { max(260, maxHeight * 0.5) }
    private var full: CGFloat { maxHeight }
    private var detents: [CGFloat] { [collapsed, mid, full] }

    private struct Item: Identifiable {
        let surface: AppModel.Surface
        let title: String
        let icon: String
        var id: String { surface.rawValue }
    }
    private let explore: [Item] = [
        Item(surface: .timeline, title: "Timeline", icon: "square.grid.2x2"),
        Item(surface: .highlights, title: "Achievements", icon: "trophy"),
        Item(surface: .studio, title: "Studio", icon: "photo.artframe"),
        Item(surface: .filters, title: "Filter", icon: "line.3.horizontal.decrease")
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
        VStack(spacing: 0) {
            grabber
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if query.isEmpty {
                        exploreRow
                        recentRuns
                    } else {
                        resultsList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            // Keep the sheet fixed when the keyboard appears (the field stays pinned at the top).
            .opacity(height > collapsed + 20 ? 1 : 0)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 3)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: searchFocused) { _, focused in
            if focused { snap(to: full) }
        }
    }

    // MARK: Header

    private var grabber: some View {
        Capsule()
            .fill(.secondary.opacity(0.4))
            .frame(width: 38, height: 5)
            .padding(.top, 7)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture)
    }

    /// A single Apple Maps-style search pill: magnifier + field, with the profile avatar tucked in
    /// at the trailing edge.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
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
            Button { appModel.presentedSurface = .profile } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: Idle content

    private var exploreRow: some View {
        HStack(spacing: 10) {
            ForEach(explore) { item in
                Button { appModel.presentedSurface = item.surface } label: {
                    VStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.accentOnGlass)
                            .frame(width: 52, height: 52)
                            .background(.regularMaterial, in: .circle)
                        Text(item.title)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var recentRuns: some View {
        let recent = Array(runs.prefix(10))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                runList(recent)
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query).padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                runList(results)
            }
        }
    }

    private func runList(_ list: [Run]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, run in
                if index > 0 { Divider().padding(.leading, 16) }
                Button { open(run) } label: {
                    RunRow(run: run).padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private func open(_ run: Run) {
        searchFocused = false
        snap(to: collapsed)
        appModel.select(run)
    }

    // MARK: Drag / snap

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? height
                if dragStart == nil { dragStart = start }
                height = min(full, max(collapsed, start - value.translation.height))
            }
            .onEnded { value in
                dragStart = nil
                // Project a little momentum, then snap to the nearest detent.
                let projected = height - value.predictedEndTranslation.height * 0.25 + value.translation.height * 0.25
                let target = detents.min(by: { abs($0 - projected) < abs($1 - projected) }) ?? collapsed
                if target <= collapsed + 1 { searchFocused = false }
                snap(to: target)
            }
    }

    private func snap(to target: CGFloat) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { height = target }
    }
}
