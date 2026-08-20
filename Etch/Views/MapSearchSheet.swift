import SwiftUI
import SwiftData
import UIKit

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Changes each time the sheet settles into a detent — drives the settle haptic.
    @State private var snappedDetent: CGFloat = 60
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
    /// Whether the expanded page's scroll view is at its top — gates the swipe-to-collapse hand-off.
    @State private var scrollAtTop = true

    private var collapsed: CGFloat { 62 }
    private var mid: CGFloat { max(260, maxHeight * 0.5) }
    private var full: CGFloat { maxHeight }
    private var detents: [CGFloat] { [collapsed, mid, full] }

    /// True once the sheet has been lifted off its collapsed rest — the scrollable content
    /// only exists (and takes layout space) here.
    private var isExpanded: Bool { height > collapsed + 20 }

    /// Phase 1 — collapsed → mid: the floating capsule opens into a floating rounded card.
    private var p1: CGFloat { min(1, max(0, (height - collapsed) / max(1, mid - collapsed))) }
    /// Phase 2 — mid → full: the floating card runs edge-to-edge down into a full bottom page.
    private var p2: CGFloat { min(1, max(0, (height - mid) / max(1, full - mid))) }

    /// The rounded-card corner radius at rest — a true capsule collapsed (≈ half the compact
    /// height), easing to a large radius by the mid rest so the partial card's corners echo the
    /// iPhone display's rounded corners.
    private var restingRadius: CGFloat { (collapsed / 2) * (1 - p1) + 44 * p1 }   // 38 → 44

    /// Top corners: the card radius while floating, easing to a sheet radius as it reaches full.
    private var topRadius: CGFloat { restingRadius * (1 - p2) + 22 * p2 }

    /// Bottom corners: the card radius (contouring the screen) through the partial state, squaring
    /// off only as the page reaches full — where the display's own rounded corners mask them.
    private var bottomRadius: CGFloat { restingRadius * (1 - p2) }

    /// The morphing container outline — a floating capsule, then a floating rounded card, then a
    /// bottom-anchored full page.
    private func containerShape() -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )
    }

    /// Inset from the screen edges as a floating pill/card; edge-to-edge once fully extended.
    private var horizontalInset: CGFloat {
        let resting = 16 * (1 - p1) + 12 * p1   // 16 → 12
        return resting * (1 - p2)               // 12 → 0
    }

    /// The screen's bottom safe-area inset, so the float can be measured against the physical
    /// bottom edge rather than the safe-area line the overlay anchors to.
    private var bottomSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    /// The floating card sits the *same* distance off the bottom as off the sides — measured from
    /// the physical bottom edge, so it isn't pushed up by the home-indicator safe area.
    private var bottomInset: CGFloat { horizontalInset - bottomSafeArea }

    /// Extra material extended below the sheet as it reaches full, so the page bleeds past the
    /// home indicator to the physical bottom edge (no map ever shows beneath it) while its top
    /// edge stays put. Generous enough to cover any device's bottom safe area.
    private var bleed: CGFloat { 90 * p2 }

    private var results: [Run] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.lowercased()
        return runs.filter { RunSearch.matches($0, query: q) }
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
                    // Generous tail space so the last section (Achievements) can scroll up fully
                    // into view above the bottom edge.
                    .padding(.bottom, 160)
                    // Track whether the page is scrolled to its top, so a downward swipe from the
                    // top hands off to the sheet (collapse) instead of scrolling.
                    .background(
                        GeometryReader { g in
                            Color.clear.onChange(of: g.frame(in: .named("sheetScroll")).minY) { _, y in
                                scrollAtTop = y >= -1
                            }
                        }
                    )
                }
                .coordinateSpace(name: "sheetScroll")
                // Don't scroll the contents until the page is fully expanded — a swipe up first
                // drives the sheet to full, then subsequent swipes scroll.
                .scrollDisabled(height < full - 1)
                // Scrolling the page dismisses the keyboard so the tiles behind it are visible.
                .scrollDismissesKeyboard(.immediately)
                // A tap anywhere on the page also dismisses the keyboard (buttons still fire).
                .simultaneousGesture(TapGesture().onEnded {
                    if searchFocused { searchFocused = false }
                })
            }
        }
        // Top-aligned once expanded (field pinned above the scroll); centred while collapsed so the
        // search pill and avatar sit in the middle of the floating container. The bleed extends the
        // material below the frame so the full page runs off the bottom edge.
        .frame(height: height + bleed, alignment: isExpanded ? .top : .center)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: containerShape())
        .clipShape(containerShape())
        .overlay(
            containerShape()
                .strokeBorder(.separator.opacity(0.4), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, y: 3)
        // The whole control is draggable: collapsed it's the pill; expanded, a downward swipe from
        // the top of the page collapses it (the scroll view keeps its own drags otherwise).
        .simultaneousGesture(dragGesture(gated: isExpanded), including: .all)
        // Widen as the sheet rises — inset as a floating pill, full width when fully extended.
        .padding(.horizontal, horizontalInset)
        // Negative bleed pulls the extended material's bottom below the screen edge while the top
        // stays where the drag height puts it.
        .padding(.bottom, bottomInset - bleed)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: searchFocused) { _, focused in
            if focused { snap(to: full) }
        }
        // A soft tactile settle as the sheet lands on a detent (Apple Maps-style).
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: snappedDetent)
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
            // The grabber always drives the sheet directly, regardless of scroll position.
            .gesture(dragGesture(gated: false))
            // Tap the grabber to peek the explore page (no keyboard); tap again to collapse.
            .onTapGesture {
                searchFocused = false
                snap(to: height <= collapsed + 1 ? mid : collapsed)
            }
    }

    /// Apple Maps-style search row: an inset search-field capsule with the profile avatar as a
    /// separate circle beside it, both sitting on the larger outer pill/sheet.
    private var searchField: some View {
        HStack(spacing: 10) {
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
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(.separator.opacity(0.35), lineWidth: 0.5))

            Button { appModel.presentedSurface = .profile } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        // Tighter gap between the outer pill and the search field + avatar inside it.
        .padding(.horizontal, 8)
        // Gap before the scroll content when expanded; none when collapsed so the row centres.
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
        PageShortcut(surface: .filters, title: "Filter", icon: "line.3.horizontal.decrease")
    ]

    /// A row of circular page shortcuts (Timeline, Achievements, Studio, Filter), sitting above
    /// Recent like Apple Maps' quick actions — Etch-blue-to-ink circles with white glyphs.
    private var pagesSection: some View {
        HStack(spacing: 0) {
            ForEach(pageShortcuts) { item in
                Button {
                    searchFocused = false
                    appModel.presentedSurface = item.surface
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: item.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(
                                LinearGradient(
                                    colors: [Theme.accent, Theme.Palette.ink],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                in: .circle
                            )
                        Text(item.title)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)   // spread the four evenly across the width
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
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
                    .foregroundStyle(Theme.accent)
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
                                // Tapping a thumbnail opens that poster's project; the section
                                // header's chevron opens the Studio page.
                                Button { appModel.studioPoster = poster } label: {
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
            // mapFallback renders the route over a MapKit snapshot — a real map behind the thumbnail.
            RunTileImage(run: run, mapFallback: true)
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

    /// The sheet drag. `gated` (used on the expanded page body) only lets a drag drive the sheet
    /// when it begins as a downward swipe from the top of the scroll — so a swipe down anywhere on
    /// the page collapses it, while normal scrolling stays with the scroll view. Ungated (the
    /// grabber and the collapsed pill) always drives the sheet.
    private func dragGesture(gated: Bool) -> some Gesture {
        // A non-zero threshold so a tap on the pill focuses the field (and expands the page)
        // instead of being captured as a zero-distance drag that snaps it back to collapsed.
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if gated {
                    let atFull = height >= full - 1
                    let verticalDominant = abs(value.translation.height) > abs(value.translation.width)
                    // Below full, a vertical drag drives the sheet (expand up / collapse down) —
                    // the scroll is disabled there. At full, only a downward swipe from the very top
                    // hands back to the sheet (to collapse); everything else scrolls.
                    let engage = dragStart != nil
                        || (!atFull && verticalDominant)
                        || (atFull && scrollAtTop && value.translation.height > 0)
                    guard engage else { return }
                }
                let start = dragStart ?? height
                if dragStart == nil { dragStart = start }
                height = min(full, max(collapsed, start - value.translation.height))
            }
            .onEnded { value in
                guard dragStart != nil else { return }
                dragStart = nil
                // Project a little momentum, then snap to the nearest detent.
                let projected = height - value.predictedEndTranslation.height * 0.25 + value.translation.height * 0.25
                let target = detents.min(by: { abs($0 - projected) < abs($1 - projected) }) ?? collapsed
                if target <= collapsed + 1 { searchFocused = false }
                snap(to: target)
            }
    }

    private func snap(to target: CGFloat) {
        snappedDetent = target   // triggers a soft settle haptic when the detent actually changes
        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.2)
            : .spring(response: 0.34, dampingFraction: 0.86)
        withAnimation(animation) { height = target }
    }
}
