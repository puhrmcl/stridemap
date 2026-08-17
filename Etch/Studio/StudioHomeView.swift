import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Etch Studio's home inside the app — the "Make Lasting" surface. A calm, editorial hub for
/// turning a run, race, or favourite into art, plus the entry point for prints. Not a
/// configurator or a shop: the artwork leads, commerce stays quiet.
struct StudioHomeView: View {
    /// True when Studio is the app's home (Studio-first mode): shows a profile button and a mini-map
    /// to reach the map, instead of the "Done" button that dismisses the sheet.
    var isHome: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var showMap = false
    @State private var showProfile = false
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
    /// Importing a single run file with custom title / race / totals choices.
    @State private var showImportPicker = false
    @State private var importDraft: ImportedRunDraft?
    @State private var isParsingImport = false
    @State private var importError: String?

    /// Single-run file types the Studio importer accepts (GPX / TCX / FIT, plus generic XML).
    private static let importTypes: [UTType] = {
        var types = ["gpx", "tcx", "fit"].compactMap { UTType(filenameExtension: $0) }
        types.append(.xml)
        return types
    }()

    /// Runs limited to the app-wide activity scope (All / Runs / Hikes / Walks).
    /// Concrete activity types present and enabled — used to decide whether to offer a filter.
    private var presentActivityScopes: [ActivityScope] {
        [.runs, .hikes, .rides, .walks].filter { ActivitySettings.isVisible($0) && !runs.scoped(to: $0).isEmpty }
    }
    private var isSingleActivity: Bool { presentActivityScopes.count <= 1 }
    private var soleScope: ActivityScope { presentActivityScopes.first ?? .runs }

    /// The scope Studio shows: the sole present type when there's only one, `.all` if the stored
    /// scope was hidden in Settings, otherwise the user's selection.
    private var scope: ActivityScope {
        if isSingleActivity { return soleScope }
        if !ActivitySettings.isVisible(appModel.activityScope) { return .all }
        return appModel.activityScope
    }

    private var scopedRuns: [Run] { runs.scoped(to: scope) }
    private var stats: RunStatistics { RunStatistics(scopedRuns) }
    /// Only runs with a route make good art.
    private var mapped: [Run] { scopedRuns.filter(\.hasRoute) }

    var body: some View {
        NavigationStack {
            Group {
                if mapped.isEmpty {
                    VStack(spacing: 22) {
                        ContentUnavailableView(
                            "Nothing to etch yet",
                            systemImage: "photo.artframe",
                            description: Text("Runs with a map become art here. Sync or import your history to begin — or add a race you ran but never tracked.")
                        )
                        HStack(spacing: 12) {
                            if showsAddRace {
                                actionCapsule("Add a race", "trophy") { showAddRace = true }
                            }
                            actionCapsule("Import an activity", "square.and.arrow.down") { showImportPicker = true }
                        }
                    }
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
                if isHome {
                    // Studio-first: profile on the left, the map as a mini-thumbnail on the right.
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showProfile = true } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        // Studio is the app's home here, so lead with the Etch brand mark.
                        Image("BrandLogo").resizable().scaledToFit().frame(height: 22)
                            .accessibilityLabel("Etch")
                    }
                    ToolbarItem(placement: .topBarTrailing) { mapThumbnailButton }
                } else {
                    // Sheet mode: the wordmark leads at the very top of the page, Done on the right.
                    ToolbarItem(placement: .topBarLeading) {
                        Image("StudioLogo").resizable().scaledToFit().frame(height: 26)
                            .accessibilityLabel("Etch Studio")
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                }
            }
            .fullScreenCover(isPresented: $showMap) { HomeView(isMapPopup: true) }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .sheet(item: $studioRun) { StudioView(run: $0) }
            .sheet(item: $openedPoster) { poster in
                if let run = run(for: poster) {
                    StudioView(run: run, poster: poster)
                }
            }
            .sheet(item: $mapPrintKind) { MapPrintView(runs: scopedRuns, kind: $0) }
            .sheet(isPresented: $showAddRace) { NavigationStack { AddRaceView() } }
            .sheet(item: $importDraft) { draft in
                NavigationStack { ImportRunView(activity: draft.activity) }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: Self.importTypes,
                allowsMultipleSelection: false,
                onCompletion: handleImportPick
            )
            .alert("Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .overlay {
                if isParsingImport {
                    ProgressView("Reading file…")
                        .padding(24)
                        .background(.regularMaterial, in: .rect(cornerRadius: 16))
                }
            }
        }
    }

    /// A plain map glyph in the corner that opens the full map (Studio-first mode).
    private var mapThumbnailButton: some View {
        Button { showMap = true } label: {
            Image(systemName: "map.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open map")
    }

    /// Parses the picked run file, then hands the best activity to the import form. Prefers an
    /// activity that carries a route (some files bundle several); falls back to the first.
    private func handleImportPick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isParsingImport = true
        Task {
            let service = FileImportService(context: modelContext)
            let outcome = await service.parse(urls: [url])
            isParsingImport = false
            if outcome.activities.isEmpty {
                importError = "Couldn't read a run from that file. Etch supports GPX, TCX, and FIT."
            } else {
                let best = outcome.activities.max { $0.coordinates.count < $1.coordinates.count }
                importDraft = ImportedRunDraft(activity: best ?? outcome.activities[0])
            }
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Leave your mark.")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Turn a run, a race, or a favorite into gallery-grade art.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Filter Studio by activity — only when there's more than one type — sits above the
            // entry points so the choice frames what "Add"/"Import" act on.
            if !isSingleActivity { scopeFilter }

            HStack(spacing: 10) {
                // "Add a race" is a running concept — only for Runs or All Activities.
                if showsAddRace {
                    actionCapsule("Add a race", "trophy") { showAddRace = true }
                }
                actionCapsule("Import an activity", "square.and.arrow.down") { showImportPicker = true }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    /// "Add a race" is a running concept, so it's offered only for Runs or All Activities.
    private var showsAddRace: Bool { scope == .runs || scope == .all }

    /// A chip that names and switches the activity filter, mirroring Achievements / Profile.
    private var scopeFilter: some View {
        Menu {
            Picker("Activity", selection: scopeBinding) {
                ForEach(ActivitySettings.visibleScopes) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: scope.icon).font(.system(size: 13, weight: .semibold))
                Text(scope == .all ? "All Activities" : scope.label)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background(Theme.accent.opacity(0.10), in: .capsule)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var scopeBinding: Binding<ActivityScope> {
        Binding(
            get: { scope },
            set: { newValue in withAnimation(Theme.gentle) { appModel.activityScope = newValue } }
        )
    }

    /// A small bordered pill action, used for the Studio entry points.
    private func actionCapsule(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.accent.opacity(0.10), in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        if scope.usesPace, let r = stats.fastestRun, r.hasRoute { out.append((r, "Fastest")) }
        if let r = stats.highestClimb, r.hasRoute { out.append((r, "Highest")) }

        // Best effort at each marquee race distance — a personal record worth a poster (runs only).
        if scope.usesPace {
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
