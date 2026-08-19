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
    @Query(sort: \SavedPoster.updatedAt, order: .reverse) private var savedPosters: [SavedPoster]

    private var stats: RunStatistics { RunStatistics(runs) }
    /// Saved Studio posters whose run still exists (a deleted run can't be recomposed).
    private var keptPosters: [SavedPoster] {
        savedPosters.filter { poster in runs.contains { $0.id == poster.runID } }
    }
    private func run(for poster: SavedPoster) -> Run? { runs.first { $0.id == poster.runID } }
    /// Recent runs that are records/milestones — the "achievements" thumbnails.
    private var milestoneRuns: [Run] {
        let ids = stats.milestoneRunIDs
        return runs.filter { ids.contains($0.id) }
    }

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var dragStart: CGFloat?

    private var collapsed: CGFloat { 60 }
    private var mid: CGFloat { max(260, maxHeight * 0.5) }
    private var full: CGFloat { maxHeight }
    private var detents: [CGFloat] { [collapsed, mid, full] }

    /// True once the sheet has been lifted off its collapsed rest — the scrollable content
    /// only exists (and takes layout space) here.
    private var isExpanded: Bool { height > collapsed + 20 }

    /// 0 while collapsed → 1 once lifted to the mid rest — drives the pill-to-sheet morph.
    private var lift: CGFloat { min(1, max(0, (height - collapsed) / max(1, mid - collapsed))) }

    /// Top corners: a true capsule radius (≈ half the compact height) while collapsed, easing to
    /// the sheet's rounded top as it rises.
    private var topRadius: CGFloat { (collapsed / 2) * (1 - lift) + 22 * lift }

    /// Bottom corners: rounded to a capsule while collapsed, squaring off as it expands so the full
    /// page runs edge-to-edge into the bottom of the screen (like Apple Maps).
    private var bottomRadius: CGFloat { (collapsed / 2) * (1 - lift) }

    /// The morphing container outline — a floating capsule collapsed, a bottom-anchored page expanded.
    private func containerShape() -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
    }

    /// Float clear of the home indicator while collapsed; run to the very bottom edge once expanded.
    private var bottomInset: CGFloat { 16 * (1 - lift) }

    /// The sheet widens as it rises: inset while it's the floating pill, a little wider at the
    /// mid rest, and edge-to-edge (full screen width) when fully extended — matching Apple Maps.
    private var horizontalInset: CGFloat {
        if height <= mid {
            let f = min(1, max(0, (height - collapsed) / max(1, mid - collapsed)))
            return 20 - 8 * f           // 20 → 12
        } else {
            let f = min(1, max(0, (height - mid) / max(1, full - mid)))
            return 12 * (1 - f)         // 12 → 0
        }
    }

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
            // The grabber only appears once lifted; collapsed, the control is a clean pill you drag
            // directly (no handle), so it doesn't read as a bottom sheet.
            if isExpanded { grabber }
            searchField
            // Only present once expanded, so it doesn't claim layout space in the collapsed pill
            // (which lets the search field centre vertically in the rounded container).
            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if query.isEmpty {
                            pagesSection
                            recentSection
                            studioSection
                            achievementsSection
                        } else {
                            resultsList
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    // Clear the home indicator when the page runs to the bottom edge.
                    .padding(.bottom, 44)
                }
                // Scrolling the page dismisses the keyboard so the tiles behind it are visible.
                .scrollDismissesKeyboard(.immediately)
            }
        }
        // Top-aligned once expanded (field pinned above the scroll); centred while collapsed so the
        // search pill and avatar sit in the middle of the floating container.
        .frame(height: height, alignment: isExpanded ? .top : .center)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: containerShape())
        .clipShape(containerShape())
        .overlay(
            containerShape()
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 3)
        // While collapsed the whole pill is draggable (there's no grabber); once expanded the
        // grabber and the scroll view own the gestures instead.
        .simultaneousGesture(dragGesture, including: isExpanded ? .subviews : .all)
        // Widen as the sheet rises — inset as a floating pill, full width when fully extended.
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, bottomInset)
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
            // Tap the grabber to peek the explore page (no keyboard); tap again to collapse.
            .onTapGesture {
                searchFocused = false
                snap(to: height <= collapsed + 1 ? mid : collapsed)
            }
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
        .padding(.vertical, 5)
        // Expanded, the field is its own inset capsule at the top of the sheet; collapsed, it sits
        // directly on the outer pill so the whole control reads as one soft capsule.
        .background {
            if isExpanded {
                Capsule().fill(.regularMaterial)
                    .overlay(Capsule().strokeBorder(.separator.opacity(0.35), lineWidth: 0.5))
            }
        }
        // Keep content clear of the pill's curved ends when collapsed.
        .padding(.horizontal, isExpanded ? 12 : 18)
        // Gap before the scroll content when expanded; none when collapsed so the pill centres.
        .padding(.bottom, isExpanded ? 10 : 0)
    }

    // MARK: Idle content

    /// One page-shortcut destination shown as a circular icon above Recent.
    private struct PageShortcut: Identifiable {
        let surface: AppModel.Surface
        let title: String
        let icon: String
        var id: String { surface.rawValue }
    }

    private let pageShortcuts: [PageShortcut] = [
        PageShortcut(surface: .timeline, title: "Timeline", icon: "square.grid.2x2"),
        PageShortcut(surface: .highlights, title: "Achievements", icon: "trophy"),
        PageShortcut(surface: .studio, title: "Studio", icon: "photo.artframe"),
        PageShortcut(surface: .filters, title: "Filter", icon: "line.3.horizontal.decrease"),
        PageShortcut(surface: .addHistory, title: "Import", icon: "square.and.arrow.down")
    ]

    /// A row of circular page shortcuts (Timeline, Achievements, Studio, Filter, Import),
    /// sitting above Recent like Apple Maps' quick actions.
    private var pagesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(pageShortcuts) { item in
                    Button {
                        searchFocused = false
                        appModel.presentedSurface = item.surface
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: item.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.accentOnGlass)
                                .frame(width: 58, height: 58)
                                .background(.regularMaterial, in: .circle)
                                .overlay(Circle().strokeBorder(.separator.opacity(0.3), lineWidth: 0.5))
                            Text(item.title)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 72)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// A section title with a right chevron that opens the full surface (Apple's "see all").
    private func sectionHeader(_ title: String, _ surface: AppModel.Surface) -> some View {
        Button { appModel.presentedSurface = surface } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The three most recent activities, with a chevron to the full Timeline.
    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(runs.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Recent", .timeline)
                runList(recent)
            }
        }
    }

    /// Recent Studio creations as poster thumbnails, with a chevron to Studio.
    @ViewBuilder
    private var studioSection: some View {
        let posters = Array(keptPosters.prefix(8))
        if !posters.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Studio", .studio)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(posters) { poster in
                            if let run = run(for: poster) {
                                Button { appModel.presentedSurface = .studio } label: {
                                    SavedPosterCard(run: run, poster: poster)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// Recent records/milestones as route thumbnails, with a chevron to Achievements.
    @ViewBuilder
    private var achievementsSection: some View {
        let milestones = Array(milestoneRuns.prefix(8))
        if !milestones.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Achievements", .highlights)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(milestones) { run in
                            Button { open(run) } label: { achievementCard(run) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func achievementCard(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RunTileImage(run: run)
                .frame(width: 140, height: 104)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topLeading) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Theme.Palette.brass, in: .circle)
                        .padding(6)
                }
            Text(stats.milestoneLabels(for: run).first ?? run.name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
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
                // Cap the rendered rows: each row hosts a live map, so a broad match must not
                // spin up hundreds at once (that exhausts MapKit and crashes the app).
                runList(Array(results.prefix(50)))
            }
        }
    }

    private func runList(_ list: [Run]) -> some View {
        // LazyVStack so each row's live map is only built as it scrolls into view — a plain
        // VStack builds them all up front, which overwhelms MapKit and crashes on a big match.
        LazyVStack(spacing: 0) {
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
