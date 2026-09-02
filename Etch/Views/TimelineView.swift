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

    private struct Derived {
        var ready = false
        var scopedRuns: [Run] = []
        var months: [RunStatistics.MonthGroup] = []
        var monthGroups: [RunStatistics.MonthGroup] = []
        var years: [Int] = []
        var runsByYear: [Int: [Run]] = [:]
        var reversedRuns: [Run] = []
        var photoMonths: [GalleryMonth] = []
        var photos: [GalleryPhoto] = []
        var hasPhotos = false
        var datesByID: [UUID: Date] = [:]
    }

    @State private var derived = Derived()

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
        next.hasPhotos = scoped.contains { !$0.photoReferences.isEmpty }

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
    private var photoMonths: [GalleryMonth] { derived.photoMonths }
    private var photos: [GalleryPhoto] { derived.photos }
    private var hasPhotos: Bool { derived.hasPhotos }
    private var availableScopes: [Scope] {
        hasPhotos ? Scope.allCases : Scope.allCases.filter { $0 != .gallery }
    }

    @State private var landedScope: Scope?

    @MainActor
    private func landOnNewest(_ proxy: ScrollViewProxy, force: Bool = false) async {
        if force {
            scrollTarget = nil
        } else {
            guard scrollTarget == nil, landedScope != scope else { return }
        }
        for _ in 0..<20 {
            if newestID != nil { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
        }
        guard let target = newestID, scrollTarget == nil else { return }
        landedScope = scope
        if force {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled, scrollTarget == nil else { return }
        proxy.scrollTo(target, anchor: .bottom)
    }

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
                        // The page opens at its foot — the most recent activity — in every
                        // scope. The anchor does the initial placement natively (robust against
                        // lazy content that hasn't measured yet, which made a scrollTo land
                        // short on large libraries); `landOnNewest` remains for scope switches
                        // and the tab re-tap.
                        .defaultScrollAnchor(.bottom)
                        .task(id: scope) { await landOnNewest(proxy) }
                        .task(id: appModel.reselectCount) {
                            guard appModel.reselectCount > 0,
                                  appModel.reselectedTab == .timeline else { return }
                            pushedRun = nil
                            await landOnNewest(proxy, force: true)
                        }
                        .onScrollTargetVisibilityChange(idType: UUID.self) { ids in
                            let next = scope == .years ? nil : span(forVisible: Set(ids))
                            if next != visibleSpan.wrappedValue { visibleSpan.wrappedValue = next }
                        }
                        .onChange(of: scope) { _, new in
                            if new == .gallery { visibleSpan.wrappedValue = nil }
                        }
                        .task(id: scrollTarget) {
                            guard let target = scrollTarget else { return }
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                            landedScope = scope
                            scrollTarget = nil
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: derivedKey, initial: true) { _, _ in rebuildDerived() }
            .navigationDestination(item: $pushedRun) { run in
                RunDetailView(run: run)
            }
            .fullScreenCover(item: $openedPhoto) { selection in
                RunPhotoViewer(
                    identifiers: photos.map(\.photoID),
                    selection: selection.id,
                    isCoverPhoto: { id in owner(of: id)?.photoReferences.first == id },
                    onDelete: deletePhoto,
                    onSetCover: setCover
                )
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
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

    private func span(forVisible ids: Set<UUID>) -> String? {
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

    private var scopePicker: some View {
        Picker("View", selection: $scope.animation(.easeInOut(duration: 0.25))) {
            ForEach(availableScopes) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, availableScopes.count > 3 ? 20 : 44)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .onChange(of: hasPhotos) { _, has in
            if !has, scope == .gallery { scope = .all }
        }
    }

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
                        countNoun: ActivityScope.noun(for: yearRuns, count: yearRuns.count),
                        distanceMeters: yearRuns.reduce(0) { $0 + $1.distance }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var monthsContent: some View {
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

    private var allContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), spacing: 2) {
            ForEach(timelineRuns) { run in
                photoTile(run, corner: 4, mapFallback: true)
            }
        }
        .scrollTargetLayout()
        .padding(.top, 2)
    }

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
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func owner(of photoID: String) -> Run? {
        runs.first { $0.photoReferences.contains(photoID) }
    }

    private func deletePhoto(_ photoID: String) {
        guard let run = owner(of: photoID) else { return }
        run.photoReferences.removeAll { $0 == photoID }
        run.updatedAt = Date()
        try? context.save()
    }

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

    private func runs(in year: Int) -> [Run] { derived.runsByYear[year] ?? [] }

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

    private func hero(in yearRuns: [Run]) -> Run? {
        yearRuns.filter(\.hasRoute).max { $0.distance < $1.distance } ?? yearRuns.first
    }

    private func open(_ run: Run) {
        if embedded {
            appModel.focus(on: run)
            pushedRun = run
        } else {
            appModel.select(run)
            appModel.presentedSurface = nil
        }
    }
}

private struct OpenedGalleryPhoto: Identifiable { let id: String }

private struct YearCard: View {
    let year: Int
    let hero: Run?
    let count: Int
    let countNoun: String
    let distanceMeters: Double

    var body: some View {
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
        .contentShape(.rect)
    }
}
