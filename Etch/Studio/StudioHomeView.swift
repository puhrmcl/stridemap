import SwiftUI
import SwiftData

/// Etch Studio's home inside the app — the "Make Lasting" surface. A calm, editorial hub for
/// turning a run, race, or favourite into art, plus the entry point for prints. Not a
/// configurator or a shop: the artwork leads, commerce stays quiet.
struct StudioHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    /// Posters the user kept, newest edit first.
    @Query(sort: \SavedPoster.updatedAt, order: .reverse) private var savedPosters: [SavedPoster]

    /// The run whose Studio composition sheet is presented.
    @State private var studioRun: Run?
    /// A kept poster being reopened (restores its saved recipe).
    @State private var openedPoster: SavedPoster?
    @State private var showPrints = false
    /// The aggregate map-print kind whose sheet is presented.
    @State private var mapPrintKind: MapPrintKind?
    /// Presenting the "add a race from the library" flow.
    @State private var showAddRace = false

    /// Runs limited to the app-wide activity scope (All / Runs / Hikes / Walks).
    private var scopedRuns: [Run] { runs.scoped(to: appModel.activityScope) }
    private var stats: RunStatistics { RunStatistics(scopedRuns) }
    /// Only runs with a route make good art.
    private var mapped: [Run] { scopedRuns.filter(\.hasRoute) }

    var body: some View {
        NavigationStack {
            Group {
                if mapped.isEmpty {
                    ContentUnavailableView(
                        "Nothing to etch yet",
                        systemImage: "photo.artframe",
                        description: Text("Runs with a map become art here. Sync or import your history to begin.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            intro
                            if !keptPosters.isEmpty { keptSection }
                            if !milestones.isEmpty { subjectRow("Milestones", milestones) }
                            let races = mapped.filter(\.isRace)
                            if !races.isEmpty { subjectRow("Races", races.map { ($0, nil) }) }
                            let favorites = mapped.filter(\.isFavorite)
                            if !favorites.isEmpty { subjectRow("Favorites", favorites.map { ($0, nil) }) }
                            subjectRow("Recent", Array(mapped.prefix(12)).map { ($0, nil) })
                            mapPrintsSection
                            printsBand
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            // The logo wordmark leads the page, so keep the bar title inline and blank.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $studioRun) { StudioView(run: $0) }
            .sheet(item: $openedPoster) { poster in
                if let run = run(for: poster) {
                    StudioView(run: run, poster: poster)
                }
            }
            .sheet(item: $mapPrintKind) { MapPrintView(runs: scopedRuns, kind: $0) }
            .sheet(isPresented: $showAddRace) { NavigationStack { AddRaceView() } }
        }
    }

    // MARK: Kept posters (the pieces the user saved)

    /// Only posters whose run is still around — a deleted run can't be recomposed.
    private var keptPosters: [SavedPoster] {
        savedPosters.filter { poster in runs.contains { $0.id == poster.runID } }
    }

    private func run(for poster: SavedPoster) -> Run? {
        runs.first { $0.id == poster.runID }
    }

    private var keptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Etches")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(keptPosters) { poster in
                        if let run = run(for: poster) {
                            Button { openedPoster = poster } label: {
                                SavedPosterCard(run: run, poster: poster)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { openedPoster = poster } label: { Label("Open", systemImage: "square.and.pencil") }
                                Button(role: .destructive) { delete(poster) } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func delete(_ poster: SavedPoster) {
        modelContext.delete(poster)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image("StudioLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .accessibilityLabel("Etch Studio")
            VStack(alignment: .leading, spacing: 6) {
                Text("Leave your mark.")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Turn a run, a race, or a favorite into gallery-grade art.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Button { showAddRace = true } label: {
                Label("Add a race from the library", systemImage: "trophy")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Subject rows

    /// The standout runs, each with a small label — the most Studio-worthy subjects. Ordered so
    /// the marquee superlatives lead, then benchmark-distance bests, then the firsts/edges. Any
    /// run that qualifies twice keeps its first (highest-priority) label.
    private var milestones: [(Run, String?)] {
        var out: [(Run, String?)] = []
        if let r = stats.longestRun, r.hasRoute { out.append((r, "Furthest")) }
        if let r = stats.longestDurationRun, r.hasRoute { out.append((r, "Longest")) }
        // Pace-based superlatives only make sense for runs (a hike's "fastest" is meaningless).
        if appModel.activityScope.usesPace, let r = stats.fastestRun, r.hasRoute { out.append((r, "Fastest")) }
        if let r = stats.highestClimb, r.hasRoute { out.append((r, "Highest")) }

        // Best effort at each marquee race distance — a personal record worth a poster (runs only).
        if appModel.activityScope.usesPace {
            let prByLabel = Dictionary(uniqueKeysWithValues: stats.personalRecords.map { ($0.label, $0.run) })
            for label in ["Marathon", "Half Marathon", "10K", "5K"] {
                if let r = prByLabel[label], r.hasRoute { out.append((r, label)) }
            }
        }

        if let r = mapped.min(by: { $0.startDate < $1.startDate }) { out.append((r, "First")) }
        if let r = stats.northernmostRun, r.hasRoute { out.append((r, "Northernmost")) }
        if let r = stats.southernmostRun, r.hasRoute { out.append((r, "Southernmost")) }

        var seen = Set<UUID>()
        return out.filter { seen.insert($0.0.id).inserted }
    }

    private func subjectRow(_ title: String, _ items: [(Run, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.0.id) { run, caption in
                        Button { studioRun = run } label: { card(run, caption: caption) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func card(_ run: Run, caption: String?) -> some View {
        RunMonthTile(run: run, corner: 16)
            .frame(width: 168, height: 210)
            .overlay(alignment: .topLeading) {
                if let caption {
                    Text(caption.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: .capsule)
                        .padding(10)
                }
            }
    }

    // MARK: Full-map prints (the whole history as one poster)

    private var mapPrintsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Full-Map Prints")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MapPrintKind.allCases) { kind in
                        Button { mapPrintKind = kind } label: { mapPrintCard(kind) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func mapPrintCard(_ kind: MapPrintKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text(kind.name)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Text(kind.descriptor)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 200, height: 180, alignment: .leading)
        .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.15), lineWidth: 1))
    }

    // MARK: Prints (entry point — fulfillment lands with the Prodigi backend)

    private var printsBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prints")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Button { showPrints = true } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gallery prints, framed art & canvas", systemImage: "photo.artframe")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("Museum-grade paper, hardwood frames, and canvas — shipped to your door.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: nil) }
        }
        .padding(.horizontal, 20)
    }
}

/// A kept poster on the Studio home shelf — its actual composition re-rendered at preview
/// resolution, with the run's name beneath. Tapping the enclosing button reopens it in Studio
/// with the saved recipe restored.
private struct SavedPosterCard: View {
    let run: Run
    let poster: SavedPoster

    @State private var thumbnail: UIImage?

    private var edition: StudioEdition { StudioEdition.edition(poster.editionID) }
    private var orientation: StudioOrientation { StudioOrientation(rawValue: poster.orientationRaw) ?? .portrait }
    private var dataPlacement: StudioDataPlacement { StudioDataPlacement(rawValue: poster.dataPlacementRaw) ?? .side }
    private var aspect: CGFloat {
        let s = StudioComposition.nominalSize(orientation, dataPlacement)
        return s.width / s.height
    }
    private var title: String { poster.customTitle.isEmpty ? run.name : poster.customTitle }
    private var cardWidth: CGFloat { orientation == .landscape ? 210 : 150 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color(hex: poster.groundColorHex) ?? edition.ground)
                        .aspectRatio(aspect, contentMode: .fit)
                        .overlay { ProgressView().tint(edition.accent) }
                }
            }
            .frame(width: cardWidth)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(edition.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .task(id: poster.updatedAt) { await renderThumbnail() }
    }

    private func renderThumbnail() async {
        let slots = poster.statSlotsRaw.compactMap { StatMetric(rawValue: $0) }
        let request = StudioRenderer.Request(
            run: run, edition: edition,
            layout: StudioLayout(rawValue: poster.layoutRaw) ?? .classic,
            orientation: orientation, dataPlacement: dataPlacement,
            photoLayout: StudioPhotoLayout(rawValue: poster.photoLayoutRaw) ?? .single,
            titleOverride: poster.customTitle.isEmpty ? nil : poster.customTitle,
            dateOverride: poster.customDate.isEmpty ? nil : poster.customDate,
            showEditorialPhoto: poster.showEditorialPhoto,
            showMemoryRoute: poster.showMemoryRoute,
            heroMetric: StatMetric(rawValue: poster.heroMetricRaw) ?? .distance,
            statSlots: slots.isEmpty ? [.time, .pace, .elevationGain] : slots,
            showElevationProfile: poster.showElevationProfile,
            includeWeather: poster.includeWeather,
            routeColor: Color(hex: poster.routeColorHex),
            textColor: Color(hex: poster.textColorHex),
            groundColor: Color(hex: poster.groundColorHex)
        )
        thumbnail = await StudioRenderer.image(for: request, scale: 1)
    }
}
