import SwiftUI
import SwiftData
import UIKit

/// The *content* of the docked search sheet — search field, Explore shortcuts, Recent, Studio,
/// Achievements, and live search results. This is the exact interface from the previous
/// `MapSearchSheet`, preserved verbatim; only the interactive presentation (drag, height, shape,
/// material, shadow) has been lifted out into the UIKit motion shell (`SearchSheetHost` +
/// `SearchSheetInteractionController`).
///
/// This view fills its host (a stable, full-height container) and never resizes itself. It reads
/// only the *discrete* `SearchSheetModel` flags (`isExpanded`, `isAtFull`), so a sheet drag never
/// re-evaluates this body. The scroll view stays mounted; the controller resets its offset directly
/// (no `.id(...)` teardown), and enables/disables scrolling on the underlying `UIScrollView`.
struct SearchSheetContent: View {
    let model: SearchSheetModel
    /// The screen's bottom safe-area inset, so the scroll tail clears the home indicator.
    var bottomSafeArea: CGFloat = 0

    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Query(sort: \SavedPoster.updatedAt, order: .reverse) private var savedPosters: [SavedPoster]

    // Explore derivations (statistics, kept posters, achievement runs, an id→run lookup) cached in
    // @State and recomputed only when the run / poster sets change — never on every body evaluation.
    @State private var cachedStats = RunStatistics([])
    @State private var cachedKeptPosters: [SavedPoster] = []
    @State private var cachedMilestoneRuns: [Run] = []
    @State private var runByID: [UUID: Run] = [:]
    /// Search results for the debounced query, likewise cached off the per-frame path.
    @State private var cachedResults: [Run] = []
    /// The query after a short debounce, so typing doesn't refilter every keystroke.
    @State private var debouncedQuery = ""

    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// Measured height of the pinned header (grabber + search row), so the scrolling content can be
    /// padded to clear it and slide behind it (Apple Maps' pinned search bar).
    @State private var headerHeight: CGFloat = 0

    private var isExpanded: Bool { model.isExpanded }

    private func run(for poster: SavedPoster) -> Run? { runByID[poster.runID] }

    /// Recompute the explore derivations. O(runs) once per data change (not per frame). Poster
    /// matching uses a dictionary lookup, not an O(posters × runs) nested scan.
    private func recomputeDerived() {
        let stats = RunStatistics(runs)
        let byID = Dictionary(runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let milestoneIDs = stats.milestoneRunIDs
        cachedStats = stats
        runByID = byID
        cachedKeptPosters = savedPosters.filter { byID[$0.runID] != nil }
        cachedMilestoneRuns = runs.filter { milestoneIDs.contains($0.id) }
    }

    /// Recompute search results for the current debounced query.
    private func recomputeResults() {
        guard !debouncedQuery.isEmpty else { cachedResults = []; return }
        let q = debouncedQuery.lowercased()
        cachedResults = runs.filter { RunSearch.matches($0, query: q) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // The scrolling page sits *behind* the pinned header and slides under it — the header's
            // glass blurs whatever scrolls beneath, so the search bar and avatar stay put while the
            // content moves (Apple Maps' pinned search). The scroll view is always mounted; the
            // controller resets its offset and toggles scrolling directly on the UIScrollView.
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if debouncedQuery.isEmpty {
                        pagesSection
                        recentSection
                        studioSection
                        achievementsSection
                        quickLinksSection
                    } else {
                        resultsList
                    }
                }
                .padding(.horizontal, 16)
                // Clear the pinned header, then a small gap before the first section.
                .padding(.top, headerHeight + 6)
                // Generous tail space so the last section can scroll fully into view above the
                // bottom edge (plus the home-indicator inset).
                .padding(.bottom, 160 + bottomSafeArea)
                // Report scroll-top as a backup hand-off signal for the interaction controller.
                .background(
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("sheetScroll")).minY) { _, y in
                            model.onScrollAtTop(y >= -1)
                        }
                    }
                )
                // A tap anywhere on the page dismisses the keyboard; tiles still fire their actions.
                .contentShape(Rectangle())
                .onTapGesture {
                    if searchFocused { searchFocused = false }
                }
            }
            .coordinateSpace(name: "sheetScroll")
            .scrollDismissesKeyboard(.immediately)
            // Collapsed, the page is translated off-screen; keep it from intercepting touches.
            .allowsHitTesting(isExpanded)

            pinnedHeader
        }
        .onChange(of: searchFocused) { _, focused in
            // Tapping into the field opens the page fully with the keyboard. A swipe up (which never
            // focuses the field) only peeks it partially, with no keyboard.
            if focused { model.requestFull() }
        }
        // Build the explore derivations once now, then only when the run / poster sets change.
        .onAppear { recomputeDerived(); recomputeResults() }
        // CI diagnostics (ETCH_DIAG=1): focus the search field unattended a few seconds after
        // launch, so a simulator run can reproduce the tap-to-search flow and log its geometry.
        .task {
            guard ProcessInfo.processInfo.environment["ETCH_DIAG"] == "1" else { return }
            try? await Task.sleep(for: .seconds(4))
            searchFocused = true
        }
        .onChange(of: runs.count) { recomputeDerived(); recomputeResults() }
        .onChange(of: savedPosters.count) { recomputeDerived() }
        // Debounce typing: restart a short timer on each keystroke, then commit and refilter once.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed != debouncedQuery else { return }
            if !trimmed.isEmpty {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            debouncedQuery = trimmed
            recomputeResults()
        }
    }

    // MARK: Header

    /// The grabber + search row, pinned at the top of the sheet. One stable hierarchy for every
    /// detent — the elements never swap containers as the sheet moves; only the search field's
    /// padding/background changes between the collapsed pill and the expanded pinned bar.
    private var pinnedHeader: some View {
        VStack(spacing: 0) {
            grabber
            searchField
        }
        // Measure the header so the scroll content can be offset to start just below it.
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { headerHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in headerHeight = h }
            }
        )
    }

    private var grabber: some View {
        // A finer bar, centred in the gap between the pill's top edge and the search bar — the
        // collapsed pill is 64pt with a ~38pt search row, so 13pt sits above the row and the 4pt
        // bar splits it (4.5 / 4 / 4.5), which also leaves the row itself vertically centred.
        Capsule()
            .fill(.secondary.opacity(0.4))
            .frame(width: 34, height: 4)
            .padding(.top, 4.5)
            .padding(.bottom, 4.5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // Tap the grabber to peek the explore page (no keyboard); tap again to collapse. The
            // *drag* is owned by the UIKit pan on the sheet container, so no gesture lives here.
            .onTapGesture {
                searchFocused = false
                model.toggleFromGrabber()
            }
    }

    /// Apple Maps-style search row. Collapsed, it's a single unified bar sitting directly on the
    /// pill; expanded, the query field takes its own blurred capsule so it stays legible over the
    /// scrolling page, with the avatar beside it.
    private var searchField: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.secondary)
                TextField("Search and explore", text: $query)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if query.isEmpty {
                    // Apple's search bar carries a mic at the trailing edge; tapping it focuses the
                    // field to start a search (no dictation backend yet).
                    Button { searchFocused = true } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search")
                } else {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, isExpanded ? 12 : 14)
            .padding(.vertical, isExpanded ? 10 : 8)
            .background {
                if isExpanded {
                    // Expanded, the field pins above the scrolling page, so it carries its own solid,
                    // well-blurred glass so the query text stays crisp over whatever scrolls beneath.
                    Capsule().fill(.thickMaterial)
                        .overlay(Capsule().strokeBorder(.separator.opacity(0.35), lineWidth: 0.5))
                } else {
                    // Collapsed, a subtle recessed shade so the field reads as a distinct bar on the
                    // pill's own glass — no second blur layer needed at rest.
                    Capsule().fill(.primary.opacity(0.08))
                }
            }

            Button { appModel.presentedSurface = .profile } label: {
                ProfileAvatar(size: 34) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        // A constant side inset, wide enough to clear the collapsed pill's own edge inset (the sheet
        // is masked to a floating pill at rest, so anything narrower gets clipped) and to give the
        // field a margin inside the pill — matching Apple Maps. Constant, so the header never
        // relayouts as the sheet moves.
        .padding(.horizontal, 30)
        // Gap before the scroll content when expanded; collapsed, the bottom inset mirrors the
        // grabber block above (13pt) so the search row sits dead-centre in the pill.
        .padding(.bottom, isExpanded ? 10 : 13)
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
    /// Recent like Apple Maps' quick actions — flat Etch-blue circles with white glyphs.
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
                            .background(Theme.accent, in: .circle)
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

    /// A section title with a right chevron that opens the full surface (Apple's "see all"). Only the
    /// title + chevron are tappable — the empty space to their right isn't, so tapping the page
    /// background never navigates. The thumbnails below open their own specific activity.
    private func sectionHeader(_ title: String, _ surface: AppModel.Surface) -> some View {
        HStack(spacing: 0) {
            Button {
                searchFocused = false
                appModel.presentedSurface = surface
            } label: {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
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
        let posters = Array(cachedKeptPosters.prefix(8))
        if !posters.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Studio", .studio)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(posters) { poster in
                            if let run = run(for: poster) {
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
        let milestones = Array(cachedMilestoneRuns.prefix(8))
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
            Text(cachedStats.milestoneLabels(for: run).first ?? run.name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
    }

    /// Full-width utility rows below the content sections — Apple Maps' "Share My Location /
    /// Report an Issue" pattern: a leading icon and a centred accent label on a tinted card.
    private var quickLinksSection: some View {
        VStack(spacing: 12) {
            quickLink("Import Activity", icon: "square.and.arrow.down") {
                appModel.presentedSurface = .addHistory
            }
            quickLink("Settings", icon: "gearshape") {
                appModel.presentedSurface = .settings
            }
        }
    }

    private func quickLink(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            searchFocused = false
            action()
        } label: {
            ZStack {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.leading, 22)
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resultsList: some View {
        if cachedResults.isEmpty {
            ContentUnavailableView.search(text: debouncedQuery).padding(.top, 30)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(cachedResults.count) result\(cachedResults.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                // Cap the rendered rows so a very broad match stays a tidy, quick list. Row
                // thumbnails are cached static snapshots, not live maps.
                runList(Array(cachedResults.prefix(50)))
            }
        }
    }

    private func runList(_ list: [Run]) -> some View {
        // LazyVStack so each row (and its snapshot request) is only realized as it scrolls into view.
        LazyVStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, run in
                if index > 0 { Divider().padding(.leading, 16) }
                runRow(run)
            }
        }
        // A cheap fill rather than a second `regularMaterial`, so the list doesn't stack another
        // live blur on the sheet's one pane of glass.
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 18))
    }

    /// A single activity tile: the tappable run row plus a trailing "⋯" overflow menu offering
    /// Share / Open in Maps / Create in Studio.
    private func runRow(_ run: Run) -> some View {
        HStack(spacing: 0) {
            Button { open(run) } label: {
                RunRow(run: run).padding(.leading, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    // The full activity share — the text summary, a PNG of the map (rendered on
                    // demand; cached by PosterMap for repeats), and an Apple Maps link — matching
                    // the detail page's Share Activity.
                    Task {
                        var items: [Any] = [run.shareSummary]
                        if run.hasMapLocation || run.coordinates.count > 1,
                           let image = await PosterMap.sharePanel(for: run, size: CGSize(width: 1000, height: 1000)) {
                            items.append(image)
                        }
                        if let url = run.appleMapsURL { items.append(url) }
                        AppShare.present(items)
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                if run.hasMapLocation {
                    Button { run.openInAppleMaps() } label: {
                        Label("Open in Maps", systemImage: "map")
                    }
                }
                Button {
                    searchFocused = false
                    appModel.studioRun = run.id
                } label: {
                    Label("Create in Studio", systemImage: "photo.artframe")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .padding(.trailing, 6)
        }
    }

    private func open(_ run: Run) {
        searchFocused = false
        model.requestCollapse()
        appModel.select(run)
    }
}
