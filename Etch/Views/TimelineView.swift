import SwiftUI
import SwiftData

/// History browsed like Apple Photos: a Years / Months / All / Gallery segmented control, with
/// route thumbnails standing in for photos in the first three and the real photographs in the
/// fourth. Tap any tile to open what it belongs to.
struct TimelineView: View {
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false
    /// Written with the date span of whatever is on screen, for the page header to show.
    ///
    /// Apple Photos puts this under "Library" and updates it as you scroll — "Aug 23–27, 2021" —
    /// and it is the detail that makes a wall of thumbnails legible: it tells you *when* you are
    /// without you having to recognise a photograph. Timeline has the same problem and the same
    /// answer. Nil while nothing is measured, so the header can fall back to its summary.
    var visibleSpan: Binding<String?> = .constant(nil)
    @Environment(AppModel.self) private var appModel
    /// The activity pushed onto this tab's own stack — see `open(_:)`.
    @State private var pushedRun: Run?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    /// Named so CI can photograph a scope other than the one the page opens on — the preview
    /// harness cannot tap a segmented control, so without this Gallery and All are unverifiable.
    init(embedded: Bool = false,
         visibleSpan: Binding<String?> = .constant(nil),
         scope: Scope = .years) {
        self.embedded = embedded
        self.visibleSpan = visibleSpan
        _scope = State(initialValue: scope)
    }

    /// Gallery is a fourth arrangement of the same history, not a separate place.
    ///
    /// It was a corner button in the page header opening a full-screen cover, which made the
    /// photographs feel like a side door off the Timeline rather than one of its views. Years,
    /// Months, All and Gallery are four ways of looking at the same activities — by year, by month,
    /// by activity, by photograph — so they belong in one control.
    enum Scope: String, CaseIterable, Identifiable {
        case years = "Years", months = "Months", all = "All", gallery = "Gallery"
        var id: String { rawValue }
    }
    @State private var scope: Scope = .years
    /// Month section to scroll to after switching to Months (set when a year tile is tapped).
    @State private var scrollTarget: String?
    /// The photograph the full-screen viewer is opened on, in the Gallery scope.
    @State private var openedPhoto: OpenedGalleryPhoto?

    // MARK: Derived data, computed once per change
    //
    // Every list on this page used to be a computed property chained onto another computed
    // property, recomputed from scratch on each access: `scopedRuns` filtered the whole library,
    // `monthGroups` regrouped it through `Calendar` (the expensive part), `photoMonths` walked
    // every photo reference and sorted them, and `timelineRuns` allocated a full reversed copy.
    // Nothing was cached, so one evaluation of `body` ran ten or more passes over the library —
    // and `body` runs a great deal more often than the data changes.
    //
    // Three things made that expensive rather than merely wasteful. The page reports its visible
    // date span through a binding, so *scrolling* rewrote the parent's state and re-ran all of
    // it. All four tabs stay alive in a `TabView`, so any change to `AppModel` re-ran all of it
    // on tabs nobody was looking at. And a year card's `runs(in:)` filtered the library again per
    // card. On a thousand-activity library that is the whole "slow and delayed" feeling.
    //
    // So the work happens once, when its inputs actually change, and `body` reads arrays.

    private struct Derived {
        var ready = false
        var scopedRuns: [Run] = []
        /// Oldest-first, each month's activities oldest-first inside it — so the newest activity
        /// in the whole history is the last tile on the page.
        ///
        /// Apple Photos' order, and the one thing about it people navigate by without thinking.
        /// `RunStatistics` hands everything back newest-first because that is what every other
        /// surface wants; only this view reads bottom-up, so the reversal lives here.
        var months: [RunStatistics.MonthGroup] = []
        /// Newest-first, as the rest of the app orders them — used for the opening-month lookup.
        var monthGroups: [RunStatistics.MonthGroup] = []
        var years: [Int] = []
        var runsByYear: [Int: [Run]] = [:]
        var reversedRuns: [Run] = []
        var photoMonths: [GalleryMonth] = []
        var photos: [GalleryPhoto] = []
        var hasPhotos = false
        /// Start dates by activity id, so the visible-span readout is a handful of dictionary
        /// lookups rather than a filter over the library on every scroll update.
        var datesByID: [UUID: Date] = [:]
    }

    @State private var derived = Derived()

    /// Everything that changes what this page shows, as one comparable value.
    ///
    /// `newestEdit` is what catches an in-place edit — a favourite toggled, a route hydrated, a
    /// photo attached — which changes no count. It is an O(n) pass over one `Date` per activity,
    /// which is the cheapest thing in this file and the reason it can stand in for all the work
    /// it guards.
    private struct DerivedKey: Equatable {
        var count = 0
        var newestEdit = 0.0
        var scope: ActivityScope = .all
        var filter = RunFilter()
        var typeMask = 0
    }

    private var derivedKey: DerivedKey {
        var newest = 0.0
        for run in runs { newest = max(newest, run.updatedAt.timeIntervalSinceReferenceDate) }
        return DerivedKey(count: runs.count, newestEdit: newest,
                          scope: appModel.activityScope, filter: appModel.filter,
                          typeMask: ActivitySettings.mask)
    }

    /// Rebuilds the page's data.
    ///
    /// The shared filter reaches here — `appModel.filter` has been app-wide session state all
    /// along, but only the map ever read it, so setting a filter changed the map and left the
    /// Timeline showing everything. PR status is a property of the collection rather than of a
    /// run, so it is computed from the typed set before narrowing — the same order the map uses,
    /// and the reason "PRs" means the same activities on both.
    private func rebuildDerived() {
        let typed = runs.scoped(to: appModel.activityScope)
        let scoped: [Run]
        if appModel.filter.isActive {
            let prs = appModel.filter.mode == .prs ? RunStatistics(typed).milestoneRunIDs : []
            scoped = typed.filter { appModel.filter.matches($0, isPR: prs.contains($0.id)) }
        } else {
            scoped = typed
        }

        let stats = RunStatistics(scoped)
        let groups = stats.monthGroups
        let calendar = Calendar.current

        var next = Derived()
        next.ready = true
        next.scopedRuns = scoped
        next.monthGroups = groups
        next.months = groups.reversed().map { group in
            var ordered = group
            ordered.runs = group.runs.reversed()
            return ordered
        }
        next.years = stats.years.reversed()
        next.reversedRuns = scoped.reversed()
        next.photoMonths = GalleryIndex.months(in: scoped)
        next.photos = next.photoMonths.flatMap(\.photos)
        next.hasPhotos = typed.contains { !$0.photoReferences.isEmpty }

        var byYear: [Int: [Run]] = [:]
        var dates: [UUID: Date] = [:]
        dates.reserveCapacity(scoped.count)
        for run in scoped {
            byYear[calendar.component(.year, from: run.startDate), default: []].append(run)
            dates[run.id] = run.startDate
        }
        next.runsByYear = byYear
        next.datesByID = dates

        derived = next
    }

    private var scopedRuns: [Run] { derived.scopedRuns }
    private var timelineMonths: [RunStatistics.MonthGroup] { derived.months }
    private var timelineYears: [Int] { derived.years }
    private var timelineRuns: [Run] { derived.reversedRuns }

    // MARK: Gallery

    /// Every photograph in the scoped history, in the same months-oldest-first order as the rest
    /// of the page. Scoped rather than global on purpose: a filter that narrows the Timeline to
    /// races should narrow the pictures to races too, or the control means two things.
    private var photoMonths: [GalleryMonth] { derived.photoMonths }
    private var photos: [GalleryPhoto] { derived.photos }
    /// Whether the Gallery scope has anything behind it. A door to an empty room is worse than
    /// no door, so the segment is simply absent until there is a photograph in the library.
    private var hasPhotos: Bool { derived.hasPhotos }
    private var availableScopes: [Scope] {
        hasPhotos ? Scope.allCases : Scope.allCases.filter { $0 != .gallery }
    }

    /// The scope this view has already placed itself in. Landing is a thing that happens when you
    /// arrive or change scope — not every time the tab is re-entered, which would throw away the
    /// place you had scrolled to for the sake of repeating an opening move.
    @State private var landedScope: Scope?

    /// Puts the newest activity on screen, at the foot, when the page opens or the scope changes.
    ///
    /// The scroll view only exists once there is something to show — the empty case is a different
    /// branch entirely — so this runs with content already in hand rather than racing the query.
    /// The sleep is for layout, not for data: the target has to be a row the scroll view can find.
    ///
    /// It stands down when `scrollTarget` is set, because that means a year card was tapped and
    /// the user asked to land somewhere specific. Two scrolls arguing would be worse than either.
    ///
    /// `force` is the re-tap on the Timeline tab: an explicit "take me back to the newest" that
    /// deliberately ignores both the once-per-scope rule and wherever you had scrolled to.
    @MainActor
    private func landOnNewest(_ proxy: ScrollViewProxy, force: Bool = false) async {
        if force {
            // An explicit request outranks a pending year-card jump.
            scrollTarget = nil
        } else {
            guard scrollTarget == nil, landedScope != scope else { return }
        }

        // Wait for there to be something to land on.
        //
        // The old version slept 60ms once and then scrolled to whatever `last` was — which on a
        // scope entered before the query had delivered anything is nil, a silent no-op, and a
        // `landedScope` set to the scope it never actually landed in. The guard above then
        // blocked every retry, so the page simply stayed at the top. Gallery caught it: it opens
        // on hundreds of tiles that take a beat longer to arrive than a handful of year cards.
        for _ in 0..<20 {
            if newestID != nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
        }
        guard let target = newestID, scrollTarget == nil else { return }
        landedScope = scope

        // Twice, deliberately. A lazy grid materialises rows *toward* a named target, so the
        // first scroll resolves against a content height that is still partly an estimate; the
        // second corrects it once the real rows exist. On a few hundred tiles that is a
        // screenful of difference, and on a thousand it is several.
        //
        // Arriving is silent; being taken back is animated. A page that simply *is* at the foot
        // when it opens needs no motion, but a jump you asked for from wherever you had scrolled
        // to should show you it happened.
        if force {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled, scrollTarget == nil else { return }
        proxy.scrollTo(target, anchor: .bottom)
    }

    /// The last row on the page — the newest thing in whichever arrangement is showing, and so
    /// the one the scope opens on. Nil while the scope has nothing in it.
    private var newestID: AnyHashable? {
        switch scope {
        case .years:   return timelineYears.last.map { AnyHashable($0) }
        case .months:  return timelineMonths.last.map { AnyHashable($0.id) }
        case .all:     return timelineRuns.last.map { AnyHashable($0.id) }
        case .gallery: return photos.last.map { AnyHashable($0.id) }
        }
    }

    var body: some View {
        NavRoot(embedded) {
            Group {
                if !derived.ready {
                    // The one frame between the first layout and the first rebuild. Blank rather
                    // than the empty state, which would flash "Nothing here yet" over a full
                    // library every time the page appeared.
                    Color.clear
                } else if scopedRuns.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "calendar",
                        description: Text("Sync your activities to build your timeline.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            switch scope {
                            case .years: yearsContent
                            case .months: monthsContent
                            case .all: allContent
                            case .gallery: galleryContent
                            }
                        }
                        // Opens on the newest activity, which now sits at the foot of the page.
                        //
                        // Deliberately *not* `.defaultScrollAnchor(.bottom, …)`, which is what
                        // this was and what broke it: that anchor resolves against the content
                        // height the scroll view knows at first layout, and inside a LazyVStack
                        // that height is an estimate from the handful of rows built so far. On a
                        // thousand-activity history the estimate was long, so the view opened
                        // scrolled clean past the end — the last card's bottom edge at the top of
                        // the screen and an empty page under it.
                        //
                        // Naming the last item instead is exact: `scrollTo(_:anchor:.bottom)`
                        // puts that item's bottom edge on the viewport's bottom edge, and lazy
                        // content materialises toward a named target rather than being guessed at.
                        .task(id: scope) { await landOnNewest(proxy) }
                        // Tap the Timeline tab you are already on and you come back to the
                        // newest activity — the top of the list, which here is the foot of the
                        // page. Applies in whichever scope is showing: the newest year, the
                        // newest month, the newest activity, the newest photograph.
                        .task(id: appModel.reselectCount) {
                            guard appModel.reselectCount > 0,
                                  appModel.reselectedTab == .timeline else { return }
                            // Back out of an open activity first. Re-tapping a tab means "back to
                            // the start of this tab", and the start is not a detail page.
                            pushedRun = nil
                            await landOnNewest(proxy, force: true)
                        }
                        // Which tiles are actually on screen, rather than a guess from the scroll
                        // offset — a lazy grid's offset says nothing reliable about which row you
                        // are looking at. Only the dated scopes report: Years already prints its
                        // own year on every card, so a span under the title would say it twice.
                        //
                        // Written only when it actually changes. This binding is the parent's
                        // state, so every write re-renders the whole page — and the callback runs
                        // continuously while a finger is down, which meant a scroll was rebuilding
                        // the Timeline dozens of times a second to arrive at the same seven words
                        // it already had. The span only moves when you cross a day.
                        .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
                            let next = scope == .years ? nil : span(forVisible: Set(ids))
                            if next != visibleSpan.wrappedValue { visibleSpan.wrappedValue = next }
                        }
                        // Gallery reports no span of its own — its tiles are photographs, not
                        // activities — so the header would otherwise keep printing the dates of
                        // whatever the previous scope last saw.
                        .onChange(of: scope) { _, new in
                            if new == .gallery { visibleSpan.wrappedValue = nil }
                        }
                        // After a year tile switches us to Months, scroll to that year's start.
                        .task(id: scrollTarget) {
                            guard let target = scrollTarget else { return }
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                            // This counts as having landed. Without it, leaving the tab and
                            // coming back would run the open-on-newest move and throw away the
                            // month the year card was tapped to reach.
                            landedScope = scope
                            scrollTarget = nil
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            // The one place the page's data is built. Everything else on this view reads arrays.
            .onChange(of: derivedKey, initial: true) { _, _ in rebuildDerived() }
            .navigationDestination(item: $pushedRun) { run in
                RunDetailView(run: run)
            }
            // The viewer walks the whole gallery rather than one activity's photos: this is a
            // gallery, and stopping the swipe at an activity boundary would be the filing cabinet
            // again. The cover action still resolves per photo, to whichever activity owns the
            // one on screen.
            .fullScreenCover(item: $openedPhoto) { selection in
                RunPhotoViewer(
                    identifiers: photos.map(\.photoID),
                    selection: selection.id,
                    isCoverPhoto: { id in owner(of: id)?.photoReferences.first == id },
                    onDelete: deletePhoto,
                    onSetCover: setCover
                )
            }
            // Years / Months / All sits at the bottom as a sheet, and at the top inside the tab.
            //
            // Apple Photos docks exactly this control in a floating capsule at the foot of the
            // screen, which is the model this view was built on — but Photos has no tab bar, and
            // Etch now does. Two floating capsules stacked at the bottom is the app's own
            // navigation arguing with the page's, so inside the tab the control moves up under
            // the header, where it is plainly this page's and not the app's.
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    // The chip goes above the scope picker rather than beside it: one says what
                    // the whole page is narrowed to, the other is a control for this page. Mixing
                    // them on a line would read as four buttons.
                    EtchFilterChip(filter: appModel.filter) {
                        appModel.setFilter(RunFilter())
                    }
                    .padding(.horizontal, 20)
                    if embedded && !scopedRuns.isEmpty { scopePicker }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !embedded && !scopedRuns.isEmpty { scopePicker }
            }
        }
    }

    // MARK: The visible span

    /// "Aug 23–27, 2021" for whatever is on screen, in Photos' own phrasing.
    ///
    /// Collapses as far as the dates allow: one day prints once, a span inside a month shares the
    /// month, a span inside a year shares the year, and only a span crossing years spells both
    /// ends out. A header that said "Aug 23, 2021 – Aug 27, 2021" would be accurate and unreadable.
    private func span(forVisible ids: Set<UUID>) -> String? {
        // A dictionary lookup per visible tile, not a filter over the library per scroll update.
        var first: Date?, last: Date?
        for id in ids {
            guard let date = derived.datesByID[id] else { continue }
            if first == nil || date < first! { first = date }
            if last == nil || date > last! { last = date }
        }
        guard let first, let last else { return nil }

        let calendar = Calendar.current
        if calendar.isDate(first, inSameDayAs: last) {
            return first.formatted(.dateTime.month(.abbreviated).day().year())
        }
        let sameYear = calendar.component(.year, from: first) == calendar.component(.year, from: last)
        let sameMonth = sameYear
            && calendar.component(.month, from: first) == calendar.component(.month, from: last)

        if sameMonth {
            let month = first.formatted(.dateTime.month(.abbreviated))
            let d1 = calendar.component(.day, from: first)
            let d2 = calendar.component(.day, from: last)
            let year = calendar.component(.year, from: first)
            return "\(month) \(d1)–\(d2), \(year)"
        }
        if sameYear {
            let a = first.formatted(.dateTime.month(.abbreviated).day())
            let b = last.formatted(.dateTime.month(.abbreviated).day())
            return "\(a) – \(b), \(calendar.component(.year, from: first))"
        }
        let a = first.formatted(.dateTime.month(.abbreviated).year())
        let b = last.formatted(.dateTime.month(.abbreviated).year())
        return "\(a) – \(b)"
    }

    // MARK: Scope control

    /// Four equal segments need the width three did not. The inset was 44pt a side, which on a
    /// 375pt screen leaves 71pt per segment — enough for "Months" and not for "Gallery", and a
    /// segmented control that runs out of room truncates to an ellipsis rather than shrinking.
    private var scopePicker: some View {
        Picker("View", selection: $scope.animation(.easeInOut(duration: 0.25))) {
            ForEach(availableScopes) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, availableScopes.count > 3 ? 20 : 44)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        // The last photograph in the library can be deleted from inside the viewer, which takes
        // the segment away while it is the selected one. Land somewhere real rather than on a
        // scope the control no longer offers.
        .onChange(of: hasPhotos) { _, has in
            if !has, scope == .gallery { scope = .all }
        }
    }

    // MARK: Years

    private var yearsContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(timelineYears, id: \.self) { year in
                let yearRuns = runs(in: year)
                Button {
                    scrollTarget = openingMonthID(ofYear: year)
                    withAnimation(.easeInOut(duration: 0.25)) { scope = .months }
                } label: {
                    YearCard(
                        year: year,
                        hero: hero(in: yearRuns),
                        count: yearRuns.count,
                        // The year's own activities name themselves. The selector's word is
                        // right for the page and wrong for a card: on All Activities a year
                        // of nothing but hikes was captioned "activities" when it could say
                        // "hikes", and that is the whole complaint about this vocabulary.
                        countNoun: ActivityScope.noun(for: yearRuns, count: yearRuns.count),
                        distanceMeters: yearRuns.reduce(0) { $0 + $1.distance }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    // MARK: Months

    private var monthsContent: some View {
        // Headers scroll with the content (not pinned) for an Apple Photos-style feel.
        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(timelineMonths) { group in
                Section {
                    monthGrid(group.runs)
                } header: {
                    sectionHeader(title: Format.monthYear(group.date),
                                  detail: "\(group.runs.count) · \(Format.distance(group.totalDistance, decimals: 0))")
                }
                .id(group.id)
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    /// A month's runs: a wide hero for the first, then a 3-up grid of the rest. Tiles show the
    /// run's photo (or a brand-tinted map of the route) with the title + distance captioned.
    @ViewBuilder
    private func monthGrid(_ monthRuns: [Run]) -> some View {
        if let hero = monthRuns.first {
            Button { open(hero) } label: {
                RunMonthTile(run: hero, corner: 14)
                    .frame(height: 170)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
        }
        // Months keeps three columns — it is the browsing scope, where a tile has to be big
        // enough to recognise a route from — but the gutters tighten to match All.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
            ForEach(monthRuns.dropFirst()) { run in
                Button { open(run) } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay { RunMonthTile(run: run, corner: 10) }
                        .clipShape(.rect(cornerRadius: 10))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: All

    /// All, at Apple Photos' density: five columns, hairline gutters, edge to edge.
    ///
    /// Four columns inside an 8pt margin left the grid reading as a panel of thumbnails on a
    /// page. Photos runs its tiles to the screen edges with 2pt between them, and the effect is
    /// not that the pictures are smaller — it is that the page stops being a container and starts
    /// being the pictures. On a history of several hundred activities that is the difference
    /// between browsing and scrolling.
    ///
    /// Corner radius drops with the tile: a 6pt round on a 90pt tile is a detail, and on a 72pt
    /// tile it is a shape.
    private var allContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), spacing: 2) {
            ForEach(timelineRuns) { run in
                // A run with no photograph shows where it happened rather than a bare line.
                //
                // The flat route drawing is a shape with no place attached: two loops of similar
                // size are indistinguishable, which in a grid of hundreds is most of them. On a
                // map you recognise the neighbourhood before you have read anything. Runs with a
                // photograph still lead with it, and routeless ones keep their activity glyph —
                // RunTileImage already cascades photo → map → drawing.
                photoTile(run, corner: 4, mapFallback: true)
            }
        }
        .scrollTargetLayout()
        .padding(.top, 2)
    }

    // MARK: Gallery

    /// Every photograph, at the same density as All — five across, hairline gutters, edge to edge
    /// — under pinned month headers. Pinned rather than scrolling because a wall of photographs
    /// has no other way of telling you where you are: a route tile carries its own title, a
    /// picture of a mountain carries nothing.
    @ViewBuilder
    private var galleryContent: some View {
        if photos.isEmpty {
            ContentUnavailableView(
                "No photos here",
                systemImage: "photo.on.rectangle.angled",
                description: Text(appModel.filter.isActive
                    ? "No photos on the activities this filter is showing."
                    : "Photos you attach to an activity — or that Etch matches from your library — collect here.")
            )
            .padding(.top, 60)
        } else {
            // One grid, sectioned — not a stack of grids.
            //
            // It was a LazyVStack of per-month LazyVGrids, which reads the same and does not
            // behave the same: a scroll target four hundred tiles down sits inside a lazy
            // container nested in another lazy container, and `scrollTo` cannot resolve a
            // position the outer container has not built the inner one for yet. The page opened
            // at the top every time while All, which is a single grid, landed correctly. A
            // LazyVGrid's own section headers span every column, so the arrangement is identical
            // and the scroll target is reachable.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5),
                      spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(photoMonths) { month in
                    Section {
                        ForEach(month.photos) { photo in
                            Button { openedPhoto = OpenedGalleryPhoto(id: photo.photoID) } label: {
                                GalleryTile(identifier: photo.photoID)
                            }
                            .buttonStyle(.plain)
                            .id(photo.id)
                        }
                    } header: {
                        galleryHeader(month)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func galleryHeader(_ month: GalleryMonth) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.title)
                .font(.etch(.headline, weight: .semibold))
            Spacer(minLength: 0)
            Text("\(month.photos.count)")
                .font(.etch(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        // Asymmetric: the gap belongs *above* a month, separating it from the one before. The
        // grid's own row spacing is 2pt, so without this the headers sat on the tiles.
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// The activity a photograph belongs to. First match wins on the rare shared picture — the
    /// cover it would set is that activity's, which is the one the reader tapped through from.
    private func owner(of photoID: String) -> Run? {
        runs.first { $0.photoReferences.contains(photoID) }
    }

    private func deletePhoto(_ photoID: String) {
        guard let run = owner(of: photoID) else { return }
        run.photoReferences.removeAll { $0 == photoID }
        run.updatedAt = Date()
        try? context.save()
    }

    /// Makes a photograph its activity's cover, from here as much as from the activity itself —
    /// the gallery is where you see a picture big enough to decide.
    private func setCover(_ photoID: String) {
        guard let run = owner(of: photoID),
              let index = run.photoReferences.firstIndex(of: photoID), index != 0 else { return }
        var refs = run.photoReferences
        refs.remove(at: index)
        refs.insert(photoID, at: 0)
        run.photoReferences = refs
        run.updatedAt = Date()
        try? context.save()
    }

    // MARK: Pieces

    /// A tappable run tile. `height` gives a fixed-height band (the month hero); otherwise the
    /// tile is a square sized to its column. A clear sizing container defines the frame and the
    /// image sits in an overlay that's clipped to it — so `scaledToFill` can never overflow the
    /// layout (which is what made tiles overlap).
    private func photoTile(_ run: Run, corner: CGFloat, height: CGFloat? = nil,
                           mapFallback: Bool = false) -> some View {
        Button { open(run) } label: {
            Group {
                if let height {
                    Color.clear.frame(height: height)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
            .overlay { RunTileImage(run: run, mapFallback: mapFallback) }
            .clipShape(.rect(cornerRadius: corner))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { delete(run) } label: {
                Label("Delete Activity", systemImage: "trash")
            }
        }
    }

    private func delete(_ run: Run) {
        context.delete(run)
        try? context.save()
    }

    /// An Apple Photos-style month header: a large bold title with the count · distance on a quiet
    /// second line, left-aligned with no background bar (it scrolls with the grid).
    private func sectionHeader(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.etch(.title, weight: .bold))
            Text(detail)
                .font(.etch(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: Data helpers

    /// Grouped once in the rebuild rather than filtered per card. Six year cards on a
    /// thousand-activity library meant six full passes and six thousand `Calendar` calls, every
    /// time the page re-rendered.
    private func runs(in year: Int) -> [Run] { derived.runsByYear[year] ?? [] }

    /// The month a year card opens on: that year's copy of the month we are in now.
    ///
    /// It used to open on January, which is the beginning of the year and almost never what the
    /// question was. Tapping 2023 in August is nearly always "what was I doing this time in 2023"
    /// — the comparison a training year invites — and landing on January means scrolling past
    /// seven months to ask it.
    ///
    /// A year rarely has every month, so the nearest one it does have stands in. Ties break toward
    /// the later month: between June and October in an August gap, October is the one you can
    /// scroll *back* from without leaving the year.
    private func openingMonthID(ofYear year: Int) -> String? {
        let cal = Calendar.current
        let months = derived.monthGroups.filter { cal.component(.year, from: $0.date) == year }
        let target = cal.component(.month, from: .now)
        return months.min { a, b in
            let da = abs(cal.component(.month, from: a.date) - target)
            let db = abs(cal.component(.month, from: b.date) - target)
            return da == db ? a.date > b.date : da < db
        }?.id
    }

    /// The most representative run for a year's hero image: the longest one that has a route.
    private func hero(in yearRuns: [Run]) -> Run? {
        yearRuns.filter(\.hasRoute).max { $0.distance < $1.distance } ?? yearRuns.first
    }

    private func open(_ run: Run) {
        // As a tab, push. As a sheet, hand off to the map.
        //
        // This used to only do the second thing: select the run and clear `presentedSurface`,
        // leaving HomeView's sheet router to present the detail. That worked while Timeline *was*
        // a sheet HomeView had presented — clearing the surface dismissed it and the detail came
        // up behind. Once Timeline became a tab there was nothing to dismiss and HomeView was on
        // a different tab, so the tap set a selection that nobody presented and the thumbnail
        // simply stopped responding.
        //
        // Pushing is also the better answer for a tab: you are in the Timeline, you open an
        // activity, and Back returns you to the row you were looking at — rather than being
        // thrown to a modal over a map you were not on.
        // Push only — deliberately *not* `appModel.select(run)`.
        //
        // `select` sets `selectedRunID` as well as aiming the map, and HomeView's sheet router
        // reads `selectedRunID` as "present this run". HomeView is still mounted on the map tab
        // while you are here, so one tap opened the activity twice: a sheet rising from the
        // bottom, and the pushed page behind it. The map still gets its camera command, so going
        // back to the map lands on the activity you just read about.
        if embedded {
            appModel.focus(on: run)
            pushedRun = run
        } else {
            appModel.select(run)
            appModel.presentedSurface = nil
        }
    }
}

/// The photo a full-screen viewer is opened on. File-local: `RunDetailView` has its own, and one
/// shared type in the global namespace for two call sites is not an abstraction, it is a name.
private struct OpenedGalleryPhoto: Identifiable { let id: String }

/// A large hero card for a single year: the year's standout route, with the year and totals
/// laid over a darkening gradient.
private struct YearCard: View {
    let year: Int
    let hero: Run?
    let count: Int
    /// The plural noun for the count — "activities" for the All scope, else "runs" / "hikes" /
    /// "rides" / "walks" — so a year of mixed activity never reads "398 runs".
    let countNoun: String
    let distanceMeters: Double

    var body: some View {
        // The text is the primary (fixed-height) content; the photo + gradient are a clipped
        // background sized to match, so the card is always 220 tall and the year/stats overlay
        // always renders on top — regardless of the photo's aspect ratio.
        VStack(alignment: .leading) {
            Text(String(year))
                .font(.etch(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            Spacer()
            Text("\(count) \(countNoun) · \(Format.distance(distanceMeters, decimals: 0))")
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 220)
        .background {
            ZStack {
                if let hero {
                    RunTileImage(run: hero, mapFallback: true)
                } else {
                    Theme.Brand.inkDeep
                }
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .clipShape(.rect(cornerRadius: 20))
        // Make the whole card tappable, not just the text glyphs — the photo and empty areas
        // aren't hit-testable without an explicit content shape.
        .contentShape(.rect)
    }
}
