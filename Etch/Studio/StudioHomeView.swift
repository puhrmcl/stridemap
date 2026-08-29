import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Etch Studio's home inside the app — the "Make Lasting" surface. A calm, editorial hub for
/// turning any activity — a ride, a run, a hike, a race — into art, plus the entry point for
/// prints. The artwork leads; commerce stays quiet.
struct StudioHomeView: View {
    /// True when Studio is the app's own tab: it draws the shared page header and hides the
    /// navigation bar. False when Studio is presented as a sheet from somewhere else, which keeps
    /// the bar and shows the wordmark instead (see `intro`).
    var isHome: Bool = false
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false

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
    /// Presenting the photo-wall poster (cover photos of every run that has one).
    @State private var showPhotoWall = false
    @State private var showLithograph = false
    /// The activity whose medal frame is being configured.
    @State private var medalSubject: Run?
    /// The aggregate map-print kind whose sheet is presented.
    @State private var mapPrintKind: MapPrintKind?
    /// Presenting the "add a race from the library" flow.
    @State private var showAddRace = false
    /// Importing a single run file with custom title / race / totals choices.
    @State private var showImportPicker = false
    @State private var importDraft: ImportedRunDraft?
    @State private var isParsingImport = false
    @State private var importError: String?

    /// Single-run file types the Studio importer accepts (GPX / TCX / FIT). iOS registers no UTI
    /// for these extensions and types such files as a dynamic type conforming to `public.data`, so
    /// the reliable way to keep them selectable (not greyed) is to allow `.data` itself. The
    /// specific types are kept for intent; the parser validates the actual contents on import.
    private static let importTypes: [UTType] = {
        var types = [
            UTType(filenameExtension: "gpx", conformingTo: .xml),
            UTType(filenameExtension: "tcx", conformingTo: .xml),
            UTType(filenameExtension: "fit", conformingTo: .data)
        ].compactMap { $0 }
        types.append(.data)
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
    /// Only runs with a route make good art.
    private var mapped: [Run] { scopedRuns.filter(\.hasRoute) }

    var body: some View {
        NavRoot(embedded) {
            Group {
                if mapped.isEmpty {
                    VStack(spacing: 22) {
                        ContentUnavailableView(
                            "Nothing to etch yet",
                            systemImage: "photo.artframe",
                            description: Text("Any activity with a map becomes art here. Sync or import your history to begin — or add a race you did but never tracked.")
                        )
                        HStack(spacing: 12) {
                            actionCapsule("Add from the library", "trophy") { showAddRace = true }
                            actionCapsule("Import an activity", "square.and.arrow.down") { showImportPicker = true }
                        }
                    }
                } else {
                    // A storefront, in the order a shop is read: one editorial hero, then the
                    // products, then the curated line, then your own work — and the utilities
                    // last, quiet. What used to be four shelves of run thumbnails now lives
                    // inside choosing a product, which is where picking a subject belongs.
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 38) {
                                if isHome { header }
                                intro.id("intro")
                                momentHero.id("hero")
                                productGrid.id("products")
                                recentImportsSection.id("imports")
                                collectionsSection.id("collections")
                                if !keptPosters.isEmpty { keptSection.id("kept") }
                                utilityFooter.id("utilities")
                            }
                            .padding(.vertical, 14)
                        }
                        // CI preview only: jump to a named section so a long page can be
                        // photographed a screenful at a time. Inert without the variable.
                        .onAppear {
                            guard let anchor = ProcessInfo.processInfo
                                .environment["ETCH_PREVIEW_SCROLL"], !anchor.isEmpty else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                proxy.scrollTo(anchor, anchor: .top)
                            }
                        }
                    }
                }
            }
            // The page header lives in the content, so the bar carries no title of its own.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // As a tab, Studio builds its own header in the content (see `header`), so the bar
            // is hidden entirely rather than left empty. Sheet mode keeps its bar (and has no
            // close button — swipe it down).
            .toolbar(isHome ? .hidden : .automatic, for: .navigationBar)
            // A different scope is a different library, so its hero starts at the top rather
            // than wherever "Show another" had wandered to in the previous one.
            .onChange(of: scope) { heroOffset = 0 }
            // Weather backfill sweep: each visit fills the next batch of runs from WeatherKit's
            // historical weather (idempotent; source-recorded values always win).
            //
            // Keyed on the run count, which climbs on every insert during a first import — so the
            // leading settle turns `task(id:)`'s cancel-and-restart into a trailing debounce and
            // the sweep runs once the store stops moving, instead of being restarted (and its
            // WeatherKit calls abandoned) hundreds of times on the first launch.
            .task(id: runs.count) {
                guard await settled(for: .seconds(2)) else { return }
                await WeatherBackfill.run(context: modelContext)
            }
            .sheet(item: $studioRun) { StudioView(run: $0) }
            .sheet(item: $openedPoster) { poster in
                if let run = run(for: poster) {
                    StudioView(run: run, poster: poster)
                }
            }
            .sheet(item: $mapPrintKind) { MapPrintView(runs: scopedRuns, kind: $0) }
            .sheet(isPresented: $showLithograph) {
                MapPrintView(runs: scopedRuns, kind: .cities, cityIndex: true)
            }
            .sheet(isPresented: $showPhotoWall) { PhotoWallView(runs: scopedRuns) }
            .sheet(item: $medalSubject) { MedalFrameView(run: $0) }
            .sheet(isPresented: $showAddRace) { NavigationStack { AddRaceView() } }
            .sheet(item: $importDraft) { draft in
                NavigationStack {
                    ImportRunView(activity: draft.activity) { run in
                        // Straight into the editor on the run that was just imported. Importing a
                        // file is never the goal — making something out of it is — and returning
                        // to the storefront made you go and find the run you had just added.
                        // A beat, because the import sheet is still dismissing.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            studioPreset = StudioSubjectPick(run: run, family: .map)
                        }
                    }
                }
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

    // MARK: Recent imports

    /// Runs brought in from a file, newest import first.
    ///
    /// Keyed on `importedAt` rather than the run's own date, which is the point: a file dropped in
    /// today is usually a race from three years ago, so it lands in the middle of the library
    /// where nothing surfaces it. What the person wants is the thing they just added, and the
    /// storefront's other shelves are all ordered by when the run *happened*.
    ///
    /// Everything that entered through Studio: a dropped file, and a race added from the
    /// library, which lands as `.manual`. Both were a deliberate act by someone standing on this
    /// page. HealthKit and Strava are excluded because they arrive by the hundred on a sync and
    /// would bury the handful that were chosen.
    ///
    /// A GPX has no parser-side method of its own, so it falls through `ImportRunView` to
    /// `.manual` as well — which is why that case has to be in the set even though it reads like
    /// it only means the library.
    private var recentImports: [Run] {
        let fromFiles: Set<ImportMethod> = [.gpxFile, .tcxFile, .fitFile, .zipArchive, .manual]
        return scopedRuns
            .filter { run in run.importMethod.map(fromFiles.contains) ?? false }
            .sorted { $0.importedAt > $1.importedAt }
            .prefix(10)
            .map { $0 }
    }

    @ViewBuilder private var recentImportsSection: some View {
        if !recentImports.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // The supporting line sits under the whole row rather than inside the heading,
                // because the Add button shares that row and would otherwise squeeze the line
                // into a narrow column beside it.
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        sectionTitle("Recent imports")
                        Spacer(minLength: 8)
                        Button { showImportPicker = true } label: {
                            Label("Add", systemImage: "plus")
                                .font(.etch(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Brought in through Studio. Pick one up where you left it.")
                        .font(.etch(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(recentImports, id: \.id) { run in
                            Button {
                                studioPreset = StudioSubjectPick(run: run, family: .map)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    RunMonthTile(run: run, corner: 14)
                                        .frame(width: 150, height: 190)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(run.name)
                                            .font(.etch(.subheadline, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        // When it was imported, not when it was run — the run's own
                                        // date is already on the tile, and this shelf exists to
                                        // answer "what did I just bring in".
                                        Text(importedLabel(run))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 150, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    /// "Imported today" / "Imported 3 days ago" — relative, because the exact minute is noise.
    private func importedLabel(_ run: Run) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let calendar = Calendar.current
        if calendar.isDateInToday(run.importedAt) { return "Imported today" }
        if calendar.isDateInYesterday(run.importedAt) { return "Imported yesterday" }
        return "Imported " + formatter.localizedString(for: run.importedAt, relativeTo: .now)
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
            sectionTitle("Your Etches", "Pieces you've kept. Open one to change it or order a print.")
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

    // MARK: Header

    /// Avatar, wordmark, map — on one line, in the content rather than the navigation bar.
    ///
    /// The bar cannot hold this. A navigation bar is 44pt tall and the wordmark's frame is about
    /// 83pt, because two thirds of the BrandLogo asset is transparent margin and only a third is
    /// ink. Handing the bar a mark that size gets it scaled down to something that reads as an
    /// afterthought — which is why it was moved into the page in the first place. Building the
    /// header out of ordinary views instead means the mark keeps the size it has now *and* sits
    /// beside the two buttons, which is what was actually being asked for.
    ///
    /// The trade is that the header scrolls away with the page rather than pinning. For a
    /// storefront that reads top to bottom, that is the normal behaviour and arguably the better
    /// one: the buttons are reachable at the top, where a reader starts.
    /// The shared masthead: "Studio" on the left, the avatar on the right.
    ///
    /// The wordmark is gone from here. It had been the page's title, which meant Studio was the
    /// one tab whose heading was a logo rather than a name — and once every other surface gained
    /// the same header, a mark in that slot read as a different kind of page rather than a
    /// branded one. The brand still opens the app; the shop is now just labelled like a shop.
    private var header: some View {
        EtchPageHeader("Studio")
    }

    // MARK: Intro

    /// How much of the BrandLogo artwork is actually ink: **a third**. The rest is transparent
    /// margin baked into the asset, so a frame height is roughly three times the letterforms it
    /// produces. Sizing the mark as though the frame were the type is what made every earlier
    /// value — 26, 28, 40, 46 — come out looking the same and looking small.
    private static let brandInkFraction: CGFloat = 0.333

    /// A frame tall enough that the wordmark's letterforms clear the headline beneath it.
    /// "Leave your mark." is `.title` bold, whose ink runs cap-height to descender at about 0.93
    /// of its point size; the mark is scaled to beat that rather than merely approach it.
    private static var mastheadMarkHeight: CGFloat {
        let headlineInk = UIFont.preferredFont(forTextStyle: .title1).pointSize * 0.93
        return (headlineInk / brandInkFraction) * 1.06
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Sheet mode: the wordmark IS the masthead — modest, with one quiet supporting line.
            // Stacking it over a second bold headline read as two competing headers, so the
            // tagline treatment belongs only to the home variant (whose toolbar mark is small).
            if !isHome {
                VStack(alignment: .leading, spacing: 8) {
                    Image("BrandLogo")
                        .resizable().scaledToFit().frame(height: Self.mastheadMarkHeight * 0.85)
                        .accessibilityLabel("Etch")
                    Text("Turn any ride, run, hike or race into gallery-grade art.")
                        .font(.etch(.subheadline))
                        .foregroundStyle(.secondary)
                }
            } else {
                // The wordmark now leads the page from `header`, so the intro is the headline and
                // its line — repeating the mark here would give the page two of them.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Leave your mark.")
                        .font(.etch(.title, weight: .bold))
                    Text("Turn any ride, run, hike or race into gallery-grade art.")
                        .font(.etch(.body))
                        .foregroundStyle(.secondary)
                }
            }

            // Filter Studio by activity — only when there's more than one type. Bringing
            // activities in now lives at the foot of the page: a storefront opens with what it
            // sells, not with its filing cabinet.
            if !isSingleActivity { scopeFilter }
        }
        .padding(.horizontal, 20)
    }

    /// The library now covers running, cycling and iconic hikes, so the entry point belongs to
    /// every scope rather than only the running ones.
    private var showsAddRace: Bool { true }

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
                    .font(.etch(.subheadline, weight: .semibold))
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
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.accent.opacity(0.10), in: .capsule)
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: The storefront — what you can make

    /// Whether any scoped run carries a cover photo — gates the Photo Wall utility row.
    private var hasPhotos: Bool { scopedRuns.contains { !$0.photoReferences.isEmpty } }
    @State private var showYearBook = false
    /// Browsing the whole history in date order to pick a subject.
    @State private var showTimeline = false

    /// Which product's activity picker is open.
    @State private var pickingFor: StudioProduct?
    /// Live previews of each product, rendered from this user's own history.
    @State private var productPreviews: [StudioProduct: UIImage] = [:]

    /// The four objects Etch makes, as a shop presents them: a large image of the thing itself,
    /// its name, one line, and a price. Two columns, generous air — the grid does the selling,
    /// so nothing below it has to shout.
    private var productGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("What would you like to make?",
                         "Every one is composed from your own maps and photographs, then printed and shipped to you.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 20) {
                ForEach(StudioProduct.offered) { product in
                    Button { open(product) } label: { productCard(product) }
                        .buttonStyle(.plain)
                        // Each tile is its own scroll anchor, so CI can photograph a product
                        // that sits below the fold — "studio@lithograph" opens on that row.
                        // The section anchors above can only reveal what follows them, and the
                        // grid is now four rows deep.
                        .id(product.rawValue)
                }
            }
            finishes
        }
        .padding(.horizontal, 20)
        // Same settle as the weather sweep, and for a sharper reason: each restart threw away six
        // half-finished poster renders — map snapshots included — and started them again, so on a
        // first launch the storefront flickered through partial tiles for as long as the import
        // ran. One render, after the history stops arriving.
        .task(id: mapped.count) {
            guard await settled(for: .milliseconds(600)) else { return }
            await renderProductPreviews()
        }
        .sheet(item: $pickingFor) { product in
            ActivityPickerSheet(runs: runs, scope: scope) { run in
                // The picker dismisses itself; give it a beat before the editor rises.
                // The medal frame is not composed in the poster editor: its aperture is
                // 2397 × 3000 rather than 2:3, and it takes two colours instead of one. It gets
                // its own screen once a subject is chosen.
                let isMedal = product == .medalFrame
                let family = product.family
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if isMedal { medalSubject = run }
                    else { studioPreset = StudioSubjectPick(run: run, family: family) }
                }
            }
        }
        .sheet(item: $studioPreset) { pick in
            StudioView(run: pick.run, preset: preset(pick.family, for: pick.run))
        }
    }

    /// A chosen subject waiting to open in the editor on a particular product.
    struct StudioSubjectPick: Identifiable {
        let run: Run
        let family: PosterFamily
        var id: UUID { run.id }
    }
    @State private var studioPreset: StudioSubjectPick?

    private func preset(_ family: PosterFamily, for run: Run) -> PosterConfig {
        var config = PosterConfig.makeDefault(for: run)
        config.family = family
        return config
    }

    private func open(_ product: StudioProduct) {
        switch product {
        case .mapPoster, .galleryPoster, .medalFrame: pickingFor = product
        case .photoWall:                              showPhotoWall = true
        case .yearBook:                               showYearBook = true
        case .wallArt:                                mapPrintKind = .artMap
        case .lithograph:                             showLithograph = true
        }
    }

    private func productCard(_ product: StudioProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.Palette.bone)
                if let image = productPreviews[product] {
                    // Fitted, not filled: the object keeps its own proportions and sits on the
                    // mat with its own shadow, the way a shop photographs a mixed range. Filling
                    // cropped a landscape book to a square and lost its shape entirely.
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                        .padding(14)
                        .transition(.opacity)
                } else {
                    Image(systemName: product.placeholderSymbol)
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.22))
                }
            }
            .aspectRatio(StudioProduct.tileAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.etch(.headline))
                    .foregroundStyle(.primary)
                // Two lines are reserved whether or not the copy needs them, so every caption
                // in a row starts and ends on the same line and the price sits at one height.
                // Without it a one-line product and a two-line one push their neighbours around.
                Text(product.line)
                    .font(.etch(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.priceLine)
                    .font(.etch(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
        // Cards hang from the top of their row rather than centring in it.
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// What the grid above can be *made of*.
    ///
    /// The grid answers "what would you like to make" and every tile is a composition — a map
    /// poster, a gallery poster, a year book. None of them says that a finished piece can arrive
    /// as a bare sheet, on a wood hanger, or framed behind glass, because that choice lives in the
    /// print sheet you only reach *after* designing something. So a first-time visitor reads this
    /// page as "an app that makes posters" and never learns there is a $139 framed object in it.
    ///
    /// This strip is the shortest honest fix: the formats, their entry prices, and the fact that
    /// any piece can be any of them. Built from `PrintProduct.offered`, so a format that is
    /// withheld — as the hanger was until its size could be rendered — never advertises itself.
    private var finishes: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Every piece, three ways")
                    .font(.etch(.subheadline, weight: .semibold))
                Text("Pick the finish when you order — anything above can arrive as any of these.")
                    .font(.etch(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                ForEach(PrintProduct.offered) { format in
                    VStack(spacing: 5) {
                        Image(systemName: format.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(height: 22)
                        Text(format.shortName)
                            .font(.etch(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(format.entryPrice)
                            .font(.etch(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.Palette.bone.opacity(0.7), in: .rect(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                }
            }
            Button { showPrints = true } label: {
                HStack(spacing: 4) {
                    Text("See papers, frames and sizes")
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .font(.etch(.footnote, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    /// Each tile shows the buyer's own history in that product — a stock sample would be a
    /// different shop's promise. Sequential and cached, so the page settles once.
    private func renderProductPreviews() async {
        guard let subject = heroPiece?.run ?? mapped.first else { return }
        for product in StudioProduct.offered where productPreviews[product] == nil {
            if Task.isCancelled { return }
            let image: UIImage?
            switch product {
            case .mapPoster, .galleryPoster:
                var recipe = PosterConfig.makeDefault(for: subject)
                recipe.family = product.family
                image = await StudioRenderer.image(for: recipe.request(for: subject), scale: 0.34)
            case .medalFrame:
                // The frame, not a poster: this product ships a moulding with a window cut for
                // the medal, and a tile showing a bare print is a tile for a different object.
                var recipe = PosterConfig.makeDefault(for: subject)
                recipe.family = .map
                let panel = await StudioRenderer.image(for: recipe.request(for: subject), scale: 0.2)
                image = MedalFrameMockup.image(panel: panel)
            case .yearBook:
                let year = Calendar.current.component(.year, from: subject.startDate)
                let plan = BookPlan.make(year: year, runs: runs)
                image = await BookRenderer.pageImage(plan: plan, page: 0, scale: 0.34)
            case .photoWall:
                // The tile shows the wall inside its frame, because that is the object that
                // ships — the bare grid is the artwork, not the product.
                image = await photoWallMockup()
            case .wallArt:
                var request = MapPrintRequest.make(kind: .artMap, runs: mapped)
                request.artStyle = .grid
                image = await MapPrintRenderer.image(for: request, scale: 0.2)
            case .lithograph:
                // The tile shows the tour-poster form — the dot map crowning the list — because
                // that is the piece at its most recognisable from across a shelf of tiles.
                var request = MapPrintRequest.make(kind: .cities, runs: scopedRuns)
                request.cityIndex = true
                request.cityIndexHero = .map
                image = await MapPrintRenderer.image(for: request, scale: 0.2)
            }
            if Task.isCancelled { return }
            if let image {
                withAnimation(.easeIn(duration: 0.2)) { productPreviews[product] = image }
            }
        }
    }

    /// The Photo Wall tile: this user's own cover photos, behind the mount of the frame the
    /// default count is cut for. Loads only as many photographs as the frame has windows, at
    /// thumbnail size — the tile is 180pt wide, and a storefront that stalls on a photo library
    /// is worse than one that shows a glyph for a moment.
    private func photoWallMockup() async -> UIImage? {
        let size = MultiPhotoFrameCatalog.size(
            forPhotos: MultiPhotoFrameCatalog.defaultPhotos
        )
        let candidates = scopedRuns
            .filter { !$0.photoReferences.isEmpty }
            .sorted { $0.startDate > $1.startDate }
            .prefix(size.capacity)
        guard !candidates.isEmpty else { return nil }

        var photos: [UIImage] = []
        for run in candidates {
            if Task.isCancelled { return nil }
            guard let reference = run.photoReferences.first else { continue }
            if let image = await PhotoLibrary.image(
                for: reference, targetSize: CGSize(width: 180, height: 180)
            ) { photos.append(image) }
        }
        guard !photos.isEmpty else { return nil }
        return PhotoWallRenderer.image(photos: photos, size: size, longEdge: 900)
    }

    /// Waits out a burst of changes. Returns false if another change arrived first — `task(id:)`
    /// cancels the running task when its id changes, so a cancelled sleep *is* the signal that
    /// this work is already stale.
    private func settled(for duration: Duration) async -> Bool {
        do { try await Task.sleep(for: duration) } catch { return false }
        return !Task.isCancelled
    }

    /// A section heading in the two-part form a shop uses: the bold statement, then a lighter
    /// line beneath saying what the shelf actually holds.
    ///
    /// The supporting line is optional on purpose. A shelf whose name already explains itself
    /// gains nothing from a second line that restates it — the pattern earns its keep only where
    /// the heading names a thing and the line answers the question the heading raises.
    private func sectionTitle(_ text: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text)
                .font(.etch(.title3, weight: .bold))
            if let detail {
                Text(detail)
                    .font(.etch(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The utilities, kept quiet at the foot of the page

    /// Everything that isn't a product: bringing activities in, the photo wall, and browsing the
    /// print catalogue on its own. Present, findable, and deliberately not competing with the
    /// storefront above.
    private var utilityFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.bottom, 4)
            restoreHeroRow
            utilityRow("Add from the library", "trophy") { showAddRace = true }
            utilityRow("Create from your timeline", "calendar") { showTimeline = true }
            utilityRow("Import an activity", "square.and.arrow.down") { showImportPicker = true }
            if hasPhotos {
                utilityRow("Photo Wall", "photo.on.rectangle.angled") { showPhotoWall = true }
            }
            utilityRow("Browse prints & frames", "bag") { showPrints = true }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: nil) }
        .sheet(isPresented: $showYearBook) { YearBookView() }
        // The product grid's picker leads with standouts and stops at thirty recent runs, which
        // is the right shape for "make something good" and the wrong one for "make the one from
        // that Tuesday in March". This is the same picker in date order, month by month, with
        // nothing left out.
        .sheet(isPresented: $showTimeline) {
            ActivityPickerSheet(runs: runs, scope: scope, mode: .timeline) { run in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    studioPreset = StudioSubjectPick(run: run, family: .map)
                }
            }
        }
    }

    private func utilityRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.etch(.subheadline))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: The moment hero — Studio knows the user; lead with *their* moment

    @State private var heroPick: CollectionPiece?
    /// Which of the candidates is showing. Cycled by "Show another".
    @State private var heroOffset = 0
    /// Hidden by the reader, remembered across launches.
    @AppStorage("studioHeroHidden") private var heroHidden = false

    /// The pieces worth leading with, best first.
    ///
    /// **Scoped.** This read the unfiltered library, so filtering Studio to Rides still put a run
    /// at the top of the page — the one place a filter has to be obeyed, since the hero is the
    /// largest thing on the screen and reads as a claim about what you have.
    ///
    /// Races newest first, then summits by height, then the longest remaining routes. The tail
    /// matters: without it, a library with no races and no climbs — which is most people starting
    /// out — got no hero at all, and "Show another" had nothing to move to.
    private var heroCandidates: [CollectionPiece] {
        let scoped = scopedRuns
        var pieces = StudioCollections.courses(in: scoped) + StudioCollections.summits(in: scoped)
        var seen = Set(pieces.map { $0.run.id })
        let longest = scoped
            .filter { $0.hasRoute && !seen.contains($0.id) }
            .sorted { $0.distance > $1.distance }
            .prefix(8)
        for run in longest {
            seen.insert(run.id)
            pieces.append(CollectionPiece(run: run,
                                          preset: StudioCollections.coursePreset(for: run),
                                          subtitle: Format.distance(run.distance)))
        }
        return pieces
    }

    /// The one on screen. The offset wraps, so "Show another" is an endless carousel rather than
    /// a button that quietly stops working at the end of the list.
    private var heroPiece: CollectionPiece? {
        let candidates = heroCandidates
        guard !candidates.isEmpty else { return nil }
        return candidates[((heroOffset % candidates.count) + candidates.count) % candidates.count]
    }

    @ViewBuilder private var momentHero: some View {
        if !heroHidden, let piece = heroPiece {
            let isRace = piece.run.isRace
            VStack(alignment: .leading, spacing: 0) {
            Button { heroPick = piece } label: {
                ZStack(alignment: .bottomLeading) {
                    RouteMapTile(run: piece.run)
                        .frame(height: 340)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    // An ink scrim so the type sits on the image the way a gallery caption does.
                    //
                    // Shaped with explicit stops rather than an even ramp: the caption block —
                    // eyebrow, title, subtitle, call to action — occupies the bottom half of the
                    // tile, and an even three-colour ramp only reached real darkness below the
                    // title, which left the letterspaced eyebrow sitting on bare map. The scrim
                    // now arrives at working strength just above the eyebrow and every line of
                    // type stands on ink.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.28),
                            .init(color: Theme.Palette.ink.opacity(0.55), location: 0.52),
                            .init(color: Theme.Palette.ink.opacity(0.92), location: 1.0)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 7) {
                        Text("MAKE IT PERMANENT")
                            .font(.etch(size: 11, weight: .semibold))
                            .tracking(2.4)
                            .foregroundStyle(isRace ? Theme.Palette.blueBright : Theme.Palette.brass)
                        // The editorial serif enters here — the artwork's voice, not the app's.
                        Text("Your \(heroTitle(for: piece))")
                            .font(.etchSerif(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.Palette.bone)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(heroSubtitle(for: piece))
                            .font(.etch(.subheadline))
                            .foregroundStyle(Theme.Palette.bone.opacity(0.7))
                        HStack(spacing: 6) {
                            Text("Create your piece")
                                .font(.etch(.subheadline, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(Theme.Palette.bone)
                        .padding(.top, 6)
                    }
                    .padding(22)
                }
                .clipShape(.rect(cornerRadius: 22))
                .contentShape(.rect(cornerRadius: 22))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your \(heroTitle(for: piece)). Create your piece in Etch Studio.")

            // A featured piece is a suggestion, and a suggestion you cannot refuse is an
            // instruction. Both ways out sit under it, quietly.
            HStack(spacing: 18) {
                if heroCandidates.count > 1 {
                    Button { withAnimation(.easeInOut(duration: 0.25)) { heroOffset += 1 } } label: {
                        Label("Show another", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button { withAnimation { heroHidden = true } } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
                .buttonStyle(.plain)
            }
            .font(.etch(.footnote, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            }
            .padding(.horizontal, 20)
            .sheet(item: $heroPick) { pick in
                StudioView(run: pick.run, preset: pick.preset)
            }
        }
    }

    /// Bringing the hero back, offered only to someone who hid it.
    @ViewBuilder private var restoreHeroRow: some View {
        if heroHidden && !heroCandidates.isEmpty {
            utilityRow("Show a featured piece", "sparkles") {
                withAnimation { heroHidden = false }
            }
        }
    }

    /// "BOSTON 26.2" reads as "Your Boston 26.2"; a summit reads as its trail or climb.
    private func heroTitle(for piece: CollectionPiece) -> String {
        if piece.run.isRace {
            return StudioCollections.artworkTitle(for: piece.run).capitalized
        }
        if let iconic = StudioCollections.iconicSummit(for: piece.run) { return iconic.name }
        return piece.run.displayName
    }

    private func heroSubtitle(for piece: CollectionPiece) -> String {
        var parts: [String] = [Format.distance(piece.run.distance)]
        if let city = piece.run.city, !city.isEmpty {
            parts.append(piece.run.state.map { "\(city), \($0)" } ?? city)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Collections — the curated line

    @State private var collectionBrowser: StudioCollection?

    /// The three curated collections, offered only when the user's history can fill them — an
    /// empty collection is a broken promise, so it simply doesn't appear.
    @ViewBuilder private var collectionsSection: some View {
        let counts: [(StudioCollection, Int)] = [
            (.course, StudioCollections.courses(in: runs).count),
            (.summit, StudioCollections.summits(in: runs).count),
            (.archive, StudioCollections.archiveStyles(for: runs).count)
        ].filter { $0.1 > 0 }

        if !counts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Collections", "Curated sets, drawn from what you've already done.")
                VStack(spacing: 12) {
                    ForEach(counts, id: \.0) { collection, count in
                        Button { collectionBrowser = collection } label: {
                            collectionCard(collection, count: count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .sheet(item: $collectionBrowser) { collection in
                CollectionBrowserView(collection: collection, runs: runs)
            }
        }
    }

    /// One collection as an editorial card: ink ground, the collection's accent as an eyebrow,
    /// the count as quiet proof. Deliberately darker than the utility cards around it — this is
    /// the shop window, not another tool row.
    private func collectionCard(_ collection: StudioCollection, count: Int) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(collection.title.uppercased())
                    .font(.etch(size: 11, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(collection.accent)
                Text(collection.descriptor)
                    .font(.etch(.subheadline))
                    .foregroundStyle(Theme.Palette.bone.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Text(count == 1 ? "1 piece" : "\(count) pieces")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.bone.opacity(0.45))
            }
            Spacer(minLength: 0)
            Image(systemName: collection.symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(collection.accent.opacity(0.9))
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.Palette.bone.opacity(0.35))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.ink, in: .rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(collection.accent.opacity(0.25), lineWidth: 0.75)
        )
    }

}

/// A kept poster on the Studio home shelf — its actual composition re-rendered at preview
/// resolution, with the run's name beneath. Tapping the enclosing button reopens it in Studio
/// with the saved recipe restored.
struct SavedPosterCard: View {
    let run: Run
    let poster: SavedPoster

    @State private var thumbnail: UIImage?

    private var edition: StudioEdition { StudioEdition.edition(poster.editionID) }
    private var orientation: StudioOrientation { StudioOrientation(rawValue: poster.orientationRaw) ?? .portrait }
    private var dataPlacement: StudioDataPlacement { StudioDataPlacement.from(raw: poster.dataPlacementRaw) }
    private var aspect: CGFloat {
        let s = StudioComposition.nominalSize(orientation, dataPlacement)
        return s.width / s.height
    }
    private var title: String { poster.customTitle.isEmpty ? run.name : poster.customTitle }
    /// Every kept-poster thumbnail is shown at the same tile size, whatever the poster's
    /// orientation — the artwork is fitted (never cropped) onto its own ground, so a shelf of
    /// mixed portrait/landscape etches reads as a tidy, uniform gallery.
    private let tileWidth: CGFloat = 150
    private let tileHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                (Color(hex: poster.groundColorHex) ?? edition.ground)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(edition.accent)
                }
            }
            .frame(width: tileWidth, height: tileHeight)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(edition.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: tileWidth, alignment: .leading)
        }
        .task(id: poster.updatedAt) { await renderThumbnail() }
    }

    private func renderThumbnail() async {
        // Build through PosterConfig so a thumbnail honours the remodel (Map/Gallery, mono, font,
        // title/location visibility) and old posters migrate to their closest new setup.
        let request = PosterConfig(poster: poster).request(for: run)
        thumbnail = await StudioRenderer.image(for: request, scale: 1)
    }
}
