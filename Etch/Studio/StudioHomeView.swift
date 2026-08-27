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
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    @State private var showMap = false
    @State private var showProfile = false
    /// The user's chosen profile photo (shared with the profile page and map search bar), so the
    /// Studio-first toolbar avatar shows it too.
    @AppStorage("profileImageData") private var profileImageData: Data?
    /// Posters the user kept, newest edit first.
    @Query(sort: \SavedPoster.updatedAt, order: .reverse) private var savedPosters: [SavedPoster]

    /// The run whose Studio composition sheet is presented.
    @State private var studioRun: Run?
    /// A kept poster being reopened (restores its saved recipe).
    @State private var openedPoster: SavedPoster?
    @State private var showPrints = false
    /// Presenting the photo-wall poster (cover photos of every run that has one).
    @State private var showPhotoWall = false
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
                            description: Text("Runs with a map become art here. Sync or import your history to begin — or add a race you ran but never tracked.")
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
                                intro.id("intro")
                                momentHero.id("hero")
                                productGrid.id("products")
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
            // The logo wordmark leads the page, so keep the bar title inline and blank.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isHome {
                    // Studio-first: profile on the left, the map as a mini-thumbnail on the right.
                    profileToolbarItem
                    ToolbarItem(placement: .principal) {
                        // One mark across the app, and the masthead of this page — so it is
                        // sized to carry the bar rather than to match the old lockup's ink. The
                        // artwork holds 27% of its height as padding, so a 40pt frame puts about
                        // 29pt of letterform in a 44pt bar.
                        Image("BrandLogo").resizable().scaledToFit().frame(height: 40)
                            .accessibilityLabel("Etch")
                    }
                    ToolbarItem(placement: .topBarTrailing) { mapThumbnailButton }
                }
                // Sheet mode has no close button — swipe the sheet down to dismiss.
            }
            .fullScreenCover(isPresented: $showMap) { HomeView(isMapPopup: true) }
            // Weather backfill sweep: each visit fills the next batch of runs from WeatherKit's
            // historical weather (idempotent; source-recorded values always win).
            .task(id: runs.count) { await WeatherBackfill.run(context: modelContext) }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .sheet(item: $studioRun) { StudioView(run: $0) }
            .sheet(item: $openedPoster) { poster in
                if let run = run(for: poster) {
                    StudioView(run: run, poster: poster)
                }
            }
            .sheet(item: $mapPrintKind) { MapPrintView(runs: scopedRuns, kind: $0) }
            .sheet(isPresented: $showPhotoWall) { PhotoWallView(runs: scopedRuns) }
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
    /// The profile photo, as the whole button.
    ///
    /// From iOS 26 the toolbar draws its own glass circle behind an item, which left the avatar
    /// sitting inside as a smaller disc ringed in white. That background belongs to the toolbar
    /// item rather than the button, so `.buttonStyle(.plain)` doesn't touch it — hiding the
    /// item's shared background does. Earlier systems never drew the circle, so the unmodified
    /// item is already correct there.
    @ToolbarContentBuilder
    private var profileToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { profileButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { profileButton }
        }
    }

    private var profileButton: some View {
        Button { showProfile = true } label: {
            // Shows the user's chosen photo (like the map search bar); the plain person glyph is
            // the placeholder before one is set.
            ProfileAvatar(size: 36) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.accent)
            }
        }
        .buttonStyle(.plain)
        // Long-press to remove the photo without opening the profile page.
        .contextMenu {
            if profileImageData != nil {
                Button(role: .destructive) { profileImageData = nil } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
            }
        }
    }

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
            // Sheet mode: the wordmark IS the masthead — modest, with one quiet supporting line.
            // Stacking it over a second bold headline read as two competing headers, so the
            // tagline treatment belongs only to the home variant (whose toolbar mark is small).
            if !isHome {
                VStack(alignment: .leading, spacing: 8) {
                    Image("BrandLogo")
                        .resizable().scaledToFit().frame(height: 44)
                        .accessibilityLabel("Etch")
                    Text("Turn a run, a race, or a favorite into gallery-grade art.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Leave your mark.")
                        .font(.system(.title, design: .rounded).weight(.bold))
                    Text("Turn a run, a race, or a favorite into gallery-grade art.")
                        .font(.system(.body, design: .rounded))
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

    // MARK: The storefront — what you can make

    /// Whether any scoped run carries a cover photo — gates the Photo Wall utility row.
    private var hasPhotos: Bool { scopedRuns.contains { !$0.photoReferences.isEmpty } }
    @State private var showYearBook = false

    /// Which product's activity picker is open.
    @State private var pickingFor: StudioProduct?
    /// Live previews of each product, rendered from this user's own history.
    @State private var productPreviews: [StudioProduct: UIImage] = [:]

    /// The four objects Etch makes, as a shop presents them: a large image of the thing itself,
    /// its name, one line, and a price. Two columns, generous air — the grid does the selling,
    /// so nothing below it has to shout.
    private var productGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("What would you like to make?")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 20) {
                ForEach(StudioProduct.allCases) { product in
                    Button { open(product) } label: { productCard(product) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .task(id: mapped.count) { await renderProductPreviews() }
        .sheet(item: $pickingFor) { product in
            ActivityPickerSheet(runs: runs, scope: scope) { run in
                // The picker dismisses itself; give it a beat before the editor rises.
                let family = product.family
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    studioPreset = StudioSubjectPick(run: run, family: family)
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
        case .mapPoster, .galleryPoster: pickingFor = product
        case .yearBook:                  showYearBook = true
        case .wallArt:                   mapPrintKind = .artMap
        }
    }

    private func productCard(_ product: StudioProduct) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Theme.Palette.bone)
                if let image = productPreviews[product] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    Image(systemName: product == .yearBook ? "book.pages" : "photo.artframe")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.22))
                }
            }
            .aspectRatio(product.tileAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                Text(product.line)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.priceLine)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
        }
    }

    /// Each tile shows the buyer's own history in that product — a stock sample would be a
    /// different shop's promise. Sequential and cached, so the page settles once.
    private func renderProductPreviews() async {
        guard let subject = heroPiece?.run ?? mapped.first else { return }
        for product in StudioProduct.allCases where productPreviews[product] == nil {
            if Task.isCancelled { return }
            let image: UIImage?
            switch product {
            case .mapPoster, .galleryPoster:
                var recipe = PosterConfig.makeDefault(for: subject)
                recipe.family = product.family
                image = await StudioRenderer.image(for: recipe.request(for: subject), scale: 0.34)
            case .yearBook:
                let year = Calendar.current.component(.year, from: subject.startDate)
                let plan = BookPlan.make(year: year, runs: runs)
                image = await BookRenderer.pageImage(plan: plan, page: 0, scale: 0.34)
            case .wallArt:
                var request = MapPrintRequest.make(kind: .artMap, runs: mapped)
                request.artStyle = .grid
                // Shown landscape so it shares a row with the book, which only lies that way.
                request.orientation = .landscape
                image = await MapPrintRenderer.image(for: request, scale: 0.2)
            }
            if Task.isCancelled { return }
            if let image {
                withAnimation(.easeIn(duration: 0.2)) { productPreviews[product] = image }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .rounded).weight(.bold))
    }

    // MARK: The utilities, kept quiet at the foot of the page

    /// Everything that isn't a product: bringing activities in, the photo wall, and browsing the
    /// print catalogue on its own. Present, findable, and deliberately not competing with the
    /// storefront above.
    private var utilityFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.bottom, 4)
            utilityRow("Add from the library", "trophy") { showAddRace = true }
            utilityRow("Import an activity", "square.and.arrow.down") { showImportPicker = true }
            if hasPhotos {
                utilityRow("Photo Wall", "photo.on.rectangle.angled") { showPhotoWall = true }
            }
            utilityRow("Browse prints & frames", "bag") { showPrints = true }
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: nil) }
        .sheet(isPresented: $showYearBook) { YearBookView() }
    }

    private func utilityRow(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
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

    /// The single most commemorable piece in the library: the latest race, else the biggest
    /// summit. Shown as a full-bleed editorial hero — the user's own place as the shop window,
    /// per the art-house standard (the artwork leads; chrome recedes).
    private var heroPiece: CollectionPiece? {
        StudioCollections.courses(in: runs).first ?? StudioCollections.summits(in: runs).first
    }

    @ViewBuilder private var momentHero: some View {
        if let piece = heroPiece {
            let isRace = piece.run.isRace
            Button { heroPick = piece } label: {
                ZStack(alignment: .bottomLeading) {
                    RouteMapTile(run: piece.run)
                        .frame(height: 340)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    // An ink scrim so the type sits on the image the way a gallery caption does.
                    LinearGradient(
                        colors: [.clear, Theme.Palette.ink.opacity(0.25), Theme.Palette.ink.opacity(0.88)],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 7) {
                        Text("MAKE IT PERMANENT")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(isRace ? Theme.Palette.blueBright : Theme.Palette.brass)
                        // The editorial serif enters here — the artwork's voice, not the app's.
                        Text("Your \(heroTitle(for: piece))")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.Palette.bone)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(heroSubtitle(for: piece))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.Palette.bone.opacity(0.7))
                        HStack(spacing: 6) {
                            Text("Create your piece")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
            .padding(.horizontal, 20)
            .accessibilityLabel("Your \(heroTitle(for: piece)). Create your piece in Etch Studio.")
            .sheet(item: $heroPick) { pick in
                StudioView(run: pick.run, preset: pick.preset)
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
                Text("Collections")
                    .font(.system(.title3, design: .rounded).weight(.bold))
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
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(collection.accent)
                Text(collection.descriptor)
                    .font(.system(.subheadline, design: .rounded))
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
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
