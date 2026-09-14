import SwiftUI
import SwiftData

/// A fun, rewarding highlights screen. Two faces of the same tab, chosen by the app-wide activity
/// scope: **All Activities** tells the bigger story — your combined reach and a per-discipline
/// breakdown you can tap to dive in — while a **specific activity** (Runs / Hikes / Walks) shows
/// that discipline's own records, personal bests, and recaps.
struct HighlightsView: View {
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false
    @Environment(AppModel.self) private var appModel
    /// The activity pushed onto this tab's own stack — see `focus(_:)`.
    @State private var pushedRun: Run?
    @State private var showMemories = false
    @State private var nearbyMemories = false
    @State private var selectedInsight: MeaningEngine.Insight?
    @State private var recordsExpanded = false
    @State private var yearsExpanded = false
    @State private var selectedStory: DailyStoryEngine.Story?
    @State private var memoryDate = Date()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Query private var runs: [Run]

    /// GPS-attributed reach, computed off-main so the counts match exactly what the States and
    /// Countries maps shade (point-in-polygon), rather than the looser geocoded label sets — which
    /// over-count DC/territories, foreign regions, spelling variants, and GPS-less imported runs.
    private struct ReachGeo { var states = 0; var countries = 0; var ready = false }
    @State private var reachGeo = ReachGeo()
    /// Monotonic stamp so only the newest reach computation may publish its result.
    @State private var reachGeneration = 0

    /// Whether the switcher is offered — kept whenever an explicit selection differs from the one
    /// populated type, so an intentionally empty scope still has a way out.
    private var isSingleActivity: Bool {
        !ActivitySettings.offersActivityChoice(appModel.activityScope, in: runs)
    }

    /// The scope actually shown — the one rule every surface shares.
    private var scope: ActivityScope {
        ActivitySettings.resolvedScope(appModel.activityScope, in: runs)
    }

    // MARK: Derived data, computed once per change
    //
    // This was the most expensive page in the app to render, and none of it was cached. Reading
    // `stats.totalElevationMeters / Double(stats.totalRuns)` scoped the library, ran
    // `countingTotals` and built a `RunStatistics` twice for one division. `reachStats
    // .travelPlaces` — a group and a sort over every located activity — was called twice in
    // adjacent lines. `records` derives every superlative and personal best. The breakdown built
    // a fresh `RunStatistics` per activity type, and the recap list one per year, inside
    // `ForEach`. On a thousand activities one evaluation of `body` was doing tens of full passes,
    // most of them duplicates — and the tab stays mounted, so it re-ran on changes made elsewhere.

    private struct Derived {
        var ready = false
        var scopedRuns: [Run] = []
        var travelPlaces: [RunStatistics.TravelPlace] = []
        var stateCount = 0
        var countryCount = 0
        var mostVisitedArea: (label: String, count: Int)?
        var totalRuns = 0
        var totalDistance = 0.0
        var totalElevation = 0.0
        var totalMovingTime = 0
        var topSpeed: Double?
        var records: [RunStatistics.Record] = []
        var years: [Int] = []
        var yearTotals: [Int: (runs: Int, distance: Double)] = [:]
        var breakdown: [(scope: ActivityScope, stats: RunStatistics)] = []
        var locatedCount = 0
        var meaningInsights: [MeaningEngine.Insight] = []
        var memories: [PhotoMemory] = []
        var dailyStories: [DailyStoryEngine.Story] = []
        /// Identifies the exact located set the reach tiles describe — see `reachKey`.
        var reachSignature = 0
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
        return DerivedKey(count: runs.count, newestEdit: newest, scope: scope,
                          filter: appModel.filter, typeMask: ActivitySettings.mask)
    }

    /// Rebuilds the page.
    ///
    /// Temporary browse filters scope the factual sections below so the page agrees with the map.
    /// Meaning is different: “Etch noticed” is a statement about the selected activity history,
    /// not about whatever date/place/race slice happens to be active right now. It therefore uses
    /// `typed`, while reach/records/recaps continue using the filtered `scoped` set.
    private func rebuildDerived() {
        let typed = runs.scoped(to: scope)
        let scoped: [Run]
        if appModel.filter.isActive {
            let prs = appModel.filter.mode == .prs ? RunStatistics(typed).milestoneRunIDs : []
            scoped = typed.filter { appModel.filter.matches($0, isPR: prs.contains($0.id)) }
        } else {
            scoped = typed
        }

        let reach = RunStatistics(scoped)
        let counting = RunStatistics(scoped.countingTotals)

        var next = Derived()
        next.ready = true
        next.scopedRuns = scoped
        next.travelPlaces = reach.travelPlaces
        next.stateCount = reach.states.count
        next.countryCount = reach.countries.count
        next.mostVisitedArea = reach.mostVisitedArea
        next.totalRuns = counting.totalRuns
        next.totalDistance = counting.totalDistanceMeters
        next.totalElevation = counting.totalElevationMeters
        next.totalMovingTime = counting.totalMovingTime
        next.topSpeed = counting.topSpeed
        next.records = counting.records(usesPace: scope.usesPace)
        next.years = counting.years
        for year in next.years {
            let yearStats = counting.statistics(forYear: year)
            next.yearTotals[year] = (yearStats.totalRuns, yearStats.totalDistanceMeters)
        }
        next.locatedCount = scoped.reduce(0) { $0 + ($1.startLatitude != nil ? 1 : 0) }
        // Membership and coordinates, not merely how many there are. Two different filtered sets
        // of equal size are a different geography, and keying on the count alone let the previous
        // set's state and country totals survive the change. Built here, once per rebuild, rather
        // than in `reachKey` — which SwiftUI evaluates on every body pass.
        var reachHasher = Hasher()
        reachHasher.combine(scope.rawValue)
        for run in scoped {
            reachHasher.combine(run.id)
            reachHasher.combine(run.startLatitude)
            reachHasher.combine(run.startLongitude)
        }
        next.reachSignature = reachHasher.finalize()
        next.meaningInsights = MeaningEngine(runs: typed).insights(limit: 3, excludingKinds: [.personalBest, .record])
        next.dailyStories = DailyStoryEngine.stories(in: runs, scope: scope, now: memoryDate)
        next.memories = PhotoMemories.discover(in: runs, scope: scope, now: memoryDate, limit: 3).memories
        if scope == .all {
            next.breakdown = breakdownScopes.compactMap { s in
                let subset = RunStatistics(runs.scoped(to: s))
                return subset.totalRuns > 0 ? (s, subset) : nil
            }
        }

        derived = next
    }

    private var scopedRuns: [Run] { derived.scopedRuns }

    var body: some View {
        NavRoot(embedded) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if !isSingleActivity { scopeSwitcher }
                        featuredStory
                        dailySection
                        memoriesSection
                        meaningSection
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Achievements").font(.etch(.title2, weight: .bold))
                            if scopedRuns.isEmpty {
                                Text("No activities in this selection. Adjust your filters or activity type to explore your achievements.")
                                    .font(.etch(.subheadline)).foregroundStyle(.secondary)
                            } else if scope == .all {
                                breakdownSection
                            } else {
                                DisclosureGroup("Records & personal bests", isExpanded: $recordsExpanded) {
                                    VStack(spacing: 20) {
                                        superlativesSection
                                        personalBestsSection
                                    }.padding(.top, 16)
                                }
                                .font(.etch(.headline))
                                .tint(Theme.accent)
                            }
                        }
                        DisclosureGroup("Your years", isExpanded: $yearsExpanded) {
                            recapsSection.padding(.top, 12)
                        }
                        .font(.etch(.headline))
                        .tint(Theme.accent)
                    }
                    .padding(20)
                    // The whole content is the anchor, scrolled to its own top edge. Nothing on
                    // this page carries an id of its own and the first section changes with the
                    // scope, so naming a section would name a different one depending on where
                    // you were.
                    .id("top")
                }
                // Tap Milestones while you are already there and the page returns to the top.
                .onChange(of: appModel.reselectCount) { _, _ in
                    guard appModel.reselectedTab == .achievements else { return }
                    pushedRun = nil
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                }
                // The one place this page's data is built. Everything else reads values.
                .onChange(of: derivedKey, initial: true) { _, _ in rebuildDerived() }
                .sheet(isPresented: $showMemories) { PhotoMemoriesView(nearby: nearbyMemories) }
                .sheet(item: $selectedStory) { story in dailyStoryDetails(story) }
                .sheet(item: $selectedInsight) { insight in insightDetails(insight) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { memoryDate = Date(); rebuildDerived() }
                }
                .task {
                    while !Task.isCancelled {
                        let current = Date()
                        let midnight = Calendar.current.date(byAdding: .day, value: 1,
                            to: Calendar.current.startOfDay(for: current)) ?? current.addingTimeInterval(86400)
                        do { try await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSince(current)))) }
                        catch { return }
                        memoryDate = Date()
                        rebuildDerived()
                    }
                }
                .navigationTitle("Milestones")
                .navigationDestination(item: $pushedRun) { run in
                    RunDetailView(run: run)
                }
                // As a tab it wears the shared masthead like its neighbours; as a sheet it keeps the
                // navigation bar it is presented in.
                .navigationBarTitleDisplayMode(embedded ? .inline : .large)
                .toolbar(embedded ? .hidden : .automatic, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        if embedded {
                            EtchPageHeader("Milestones", subtitle: "What mattered.")
                        }
                        EtchFilterChip(filter: appModel.filter) {
                            appModel.setFilter(RunFilter())
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, embedded ? 8 : 0)
                    .background(embedded ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
                }
                .onAppear {
                    // Heal a stored scope that's since been hidden in Settings so it doesn't linger.
                    if !ActivitySettings.isVisible(appModel.activityScope) { setScope(.all) }
                }
                // Recompute the GPS-attributed reach whenever the scope or the located-run set changes.
                .task(id: reachKey) { await computeReachGeo() }
            }
        }
    }

    /// Keys the reach computation to *which* activities are in scope and where they start, so a
    /// filter change that happens to preserve the located count still recomputes.
    private var reachKey: Int { derived.reachSignature }

    /// Attributes each located run to a US state and a country by point-in-polygon — off the main
    /// actor — so the reach tiles read exactly what the maps shade. Coordinates are snapshotted on
    /// the main actor first (Run isn't Sendable); the polygon tests run detached.
    private func computeReachGeo() async {
        // `.task(id:)` cancels the previous task, but the polygon work runs in a *detached* task,
        // which does not inherit that cancellation. A slow earlier pass can therefore finish after
        // a newer one and publish the older geography. The generation stamp makes the last request
        // the only one allowed to write.
        reachGeneration &+= 1
        let generation = reachGeneration
        let coordinates = scopedRuns.compactMap(\.startCoordinate)
        let result = await Task.detached(priority: .userInitiated) { () -> (states: Int, countries: Int) in
            let stateBoundaries = USStateBoundaries.shared
            let countryBoundaries = WorldCountryBoundaries.shared
            var states = Set<String>()
            var countries = Set<String>()
            for coordinate in coordinates {
                if let name = stateBoundaries.region(containing: coordinate), stateBoundaries.isState(name) {
                    states.insert(name)
                }
                if let name = countryBoundaries.region(containing: coordinate) {
                    countries.insert(name)
                }
            }
            return (states.count, countries.count)
        }.value
        guard generation == reachGeneration else { return }   // a newer request already answered
        reachGeo = ReachGeo(states: result.states, countries: result.countries, ready: true)
    }

    // MARK: Scope switcher / indicator

    /// The header chip that both names the current scope and switches it — mirroring the home
    /// pill's activity selector, so the achievements tab is filterable in place.
    private var scopeSwitcher: some View {
        Menu {
            Picker("Activity", selection: scopeBinding) {
                ForEach(ActivitySettings.visibleScopes) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: scope.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(scope == .all ? "All Activities" : scope.label)
                    .font(.etch(.subheadline, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.accentOnGlass)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.regularMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopeBinding: Binding<ActivityScope> {
        Binding(get: { scope }, set: { setScope($0) })
    }

    private func setScope(_ newValue: ActivityScope) {
        withAnimation(Theme.gentle) { appModel.activityScope = newValue }
    }

    // MARK: Stories and memories

    private var featuredStory: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your story").font(.etch(.title2, weight: .bold))
                Spacer()
                Text("\(derived.years.count) \(derived.years.count == 1 ? "year" : "years")")
                    .font(.etch(.caption)).foregroundStyle(.secondary)
            }
            reachSection
            if appModel.filter.isActive {
                Text("Totals reflect your filters. Stories and memories draw from your full \(scope == .all ? "activity" : scope.countNoun) history.")
                    .font(.etch(.caption)).foregroundStyle(.secondary)
            }
        }
    }

    private var dailyStory: DailyStoryEngine.Story? {
        guard !derived.dailyStories.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: memoryDate) ?? 0
        return derived.dailyStories[day % derived.dailyStories.count]
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("A little perspective").font(.etch(.title2, weight: .bold))
                Spacer()
                Text(memoryDate.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.etch(.caption)).foregroundStyle(.secondary)
            }
            if let story = dailyStory {
                Button { selectedStory = story } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        StoryArtwork(run: story.run).id(story.run.id)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(story.eyebrow).font(.etch(.caption, weight: .semibold)).tracking(1.4)
                                .foregroundStyle(Theme.accent)
                            Text(story.title).font(.etch(.title, weight: .bold))
                            Text(story.message).font(.etch(.subheadline)).foregroundStyle(.secondary)
                            if !story.marks.isEmpty { StoryMarks(marks: story.marks) }
                            HStack {
                                Text("See the story").font(.etch(.subheadline, weight: .semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }.foregroundStyle(Theme.accent).padding(.top, 4)
                        }.padding(20)
                    }
                    .foregroundStyle(.primary)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
                    .clipShape(.rect(cornerRadius: 24))
                    .contentShape(.rect)
                }.buttonStyle(.plain)
            } else if let memory = derived.memories.first {
                Button { pushedRun = memory.run } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        StoryArtwork(run: memory.run).id(memory.run.id)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(memory.title).font(.etch(.title2, weight: .bold))
                            Text("\(memory.run.name) · \(Format.date(memory.run.startDate))")
                                .font(.etch(.subheadline)).foregroundStyle(.secondary)
                            Text("What would you want to remember about this day?")
                                .font(.etch(.body))
                            Label("Revisit this activity", systemImage: "arrow.up.right")
                                .font(.etch(.subheadline, weight: .semibold)).foregroundStyle(Theme.accent)
                        }.padding(20)
                    }.foregroundStyle(.primary)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
                        .clipShape(.rect(cornerRadius: 24))
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sparkles").font(.title).foregroundStyle(Theme.accent)
                    Text("Every story starts somewhere.").font(.etch(.title2, weight: .bold))
                    Text("Your activities will bring photos, familiar places and patterns here. Start with a day you want to remember.")
                        .font(.etch(.subheadline)).foregroundStyle(.secondary)
                    Button("Explore Timeline") { appModel.selectedTab = .timeline }
                        .frame(minHeight: 44)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
            }
        }
    }

    private var memoryPreviews: [PhotoMemory] {
        let featuredID = dailyStory?.run.id ?? derived.memories.first?.id
        return derived.memories.filter { $0.id != featuredID }
    }

    private var memoriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Memories").font(.etch(.title2, weight: .bold))
                Spacer()
                Button("Explore all") { nearbyMemories = false; showMemories = true }
                    .font(.etch(.subheadline, weight: .semibold))
                    .frame(minHeight: 44)
            }
            Text("A date. A place. A feeling worth keeping.")
                .font(.etch(.subheadline)).foregroundStyle(.secondary)
            if memoryPreviews.isEmpty {
                Button { nearbyMemories = false; showMemories = true } label: {
                    Label("Explore your history", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                }.buttonStyle(.plain)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(memoryPreviews) { memory in
                            Button { pushedRun = memory.run } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    MemoryCover(identifiers: memory.photoReferences, run: memory.run)
                                        .accessibilityHidden(true)
                                    Text(memory.title).font(.etch(.headline))
                                    Text(memory.run.name).font(.etch(.subheadline))
                                    Text(Format.date(memory.run.startDate))
                                        .font(.etch(.caption)).foregroundStyle(.secondary)
                                }
                                .frame(width: 270, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this activity")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Button { nearbyMemories = true; showMemories = true } label: {
                Label("Find memories near you", systemImage: "location")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Opens nearby discovery; location is requested only when you choose to find memories")
        }
    }

    // MARK: Meaning

    private var meaningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !derived.meaningInsights.isEmpty || derived.dailyStories.count > 1 {
                Text("Worth noticing").font(.etch(.title2, weight: .bold))
                ForEach(derived.dailyStories.filter { $0.id != dailyStory?.id }) { story in
                    Button { selectedStory = story } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: story.symbol).font(.title3).foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(story.title).font(.etch(.headline))
                                Text(story.message).font(.etch(.subheadline)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(18).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }
                ForEach(Array(derived.meaningInsights.prefix(derived.dailyStories.count > 1 ? 1 : 2)), id: \.id) { insight in
                    Button { selectedInsight = insight } label: {
                        MeaningCard(insight: insight, featured: false)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func dailyStoryDetails(_ story: DailyStoryEngine.Story) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    StoryArtwork(run: story.run).clipShape(.rect(cornerRadius: 22))
                    Text(story.title).font(.etch(.largeTitle, weight: .bold))
                    Text(story.message).font(.etch(.body))
                    if !story.marks.isEmpty { StoryMarks(marks: story.marks) }
                    Text("Make it yours").font(.etch(.title3, weight: .semibold))
                    Text(story.prompt).font(.etch(.body)).foregroundStyle(.secondary)
                    NavigationLink { RunDetailView(run: story.run) } label: {
                        Label("Revisit \(story.run.name)", systemImage: "arrow.up.right")
                            .frame(minHeight: 44)
                    }
                    Text("Behind the story").font(.etch(.headline))
                    ForEach(Array(story.evidence.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.etch(.subheadline)).foregroundStyle(.secondary)
                    }
                    Text("Based on your selected activity history in Etch. Hidden activities and activities excluded from totals or Memories are left out.")
                        .font(.etch(.caption)).foregroundStyle(.secondary)
                    ShareLink(item: story.shareText) {
                        Label("Share this insight", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }.padding(20)
            }
            .navigationTitle("Your story").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { selectedStory = nil } } }
        }
    }

    private func insightDetails(_ insight: MeaningEngine.Insight) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let run = insight.run, !run.isHiddenFromMemories {
                        StoryArtwork(run: run).clipShape(.rect(cornerRadius: 22))
                    }
                    Text(insight.title).font(.etch(.largeTitle, weight: .bold))
                    Text(insight.story).font(.etch(.body))
                    ShareLink(item: "\(insight.title)\n\n\(insight.story)\n\nFrom my activity history in Etch.") {
                        Label("Share this insight", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                    }
                    Text("Behind this insight").font(.etch(.headline))
                    ForEach(Array(insight.evidence.enumerated()), id: \.offset) { _, evidence in
                        Label(evidence, systemImage: "checkmark.circle")
                            .font(.etch(.subheadline))
                    }
                    if insight.claimWorld == .open {
                        Text("Based on the activity history currently in Etch.")
                            .font(.etch(.caption)).foregroundStyle(.secondary)
                    }
                    if let run = insight.run {
                        NavigationLink { RunDetailView(run: run) } label: {
                            Label("View activity", systemImage: "arrow.up.right")
                                .frame(minHeight: 44)
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("Etch noticed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { selectedInsight = nil }
                }
            }
        }
    }

    private struct MeaningCard: View {
        let insight: MeaningEngine.Insight
        let featured: Bool

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: insight.symbol)
                    .font(.system(size: featured ? 20 : 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    Text(insight.title)
                        .font(.etch(featured ? .title3 : .headline, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(insight.story)
                        .font(.etch(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if insight.confidence.band != .high && insight.claimWorld == .open {
                        Text("Based on the history currently in Etch")
                            .font(.etch(.caption))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 4)
                Group {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 5)
                }
            }
            .padding(featured ? 18 : 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: featured ? 22 : 18))
            .overlay {
                RoundedRectangle(cornerRadius: featured ? 22 : 18)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
        }
    }

    // MARK: Reach (shared, scopes with the selection)

    private var reachSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                summaryValue(derived.totalRuns.formatted(), label: "Activities")
                summaryValue(Format.distanceValue(derived.totalDistance).formatted(.number.precision(.fractionLength(0))),
                             label: "Total \(UnitSystem.current.distanceSuffix)")
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
                NavigationLink { CitiesListView(places: derived.travelPlaces) } label: {
                    placeValue(derived.travelPlaces.count.formatted(), label: "Cities")
                }.buttonStyle(.plain)
                NavigationLink { StatesView() } label: {
                    placeValue(reachStateValue, label: "States")
                }.buttonStyle(.plain)
                placeValue(reachCountryValue, label: "Countries")
            }
            if scopeClimbs {
                DisclosureGroup("Climb & movement") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StoryStat(value: climbValue(derived.totalElevation), label: "Total climb", systemName: "mountain.2")
                        StoryStat(value: climbValue(averageClimb), label: "Avg climb", systemName: "arrow.up.forward")
                        if scope == .rides {
                            StoryStat(value: averageSpeedValue, label: "Avg speed", systemName: "speedometer")
                            if let top = topSpeedValue { StoryStat(value: top, label: "Top speed", systemName: "gauge.high") }
                        }
                    }.padding(.top, 12)
                }.font(.etch(.subheadline)).tint(Theme.accent)
            }
        }.padding(20)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
    }

    private func summaryValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.etch(.caption)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private func placeValue(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(label).font(.etch(.caption)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44).accessibilityElement(children: .combine)
    }

    /// The States / Countries tile values: the GPS-attributed count once computed, falling back to
    /// the geocoded estimate for the brief moment before the polygon pass finishes.
    private var reachStateValue: String {
        (reachGeo.ready ? reachGeo.states : derived.stateCount).formatted()
    }
    private var reachCountryValue: String {
        (reachGeo.ready ? reachGeo.countries : derived.countryCount).formatted()
    }

    /// Whether the current scope is a climbing-forward discipline that should lead with elevation.
    private var scopeClimbs: Bool { scope == .hikes || scope == .rides }

    /// Mean ascent per activity, for the "Avg climb" tile.
    private var averageClimb: Double {
        derived.totalRuns > 0 ? derived.totalElevation / Double(derived.totalRuns) : 0
    }

    /// Distance-weighted average speed in the user's unit (mph / km/h) — the ride headline metric.
    private var averageSpeedValue: String {
        guard derived.totalMovingTime > 0 else { return "—" }
        return speedString(derived.totalDistance / Double(derived.totalMovingTime))
    }

    /// The fastest recorded top speed, when a source provided one for any ride in scope.
    private var topSpeedValue: String? {
        guard let metersPerSecond = derived.topSpeed, metersPerSecond > 0 else { return nil }
        return speedString(metersPerSecond)
    }

    /// Formats a speed in metres/second to the user's unit, e.g. "14.2 mph" / "22.8 km/h".
    private func speedString(_ metersPerSecond: Double) -> String {
        let unit = UnitSystem.current
        let value = unit == .miles ? metersPerSecond * 2.2369363 : metersPerSecond * 3.6
        let suffix = unit == .miles ? "mph" : "km/h"
        return String(format: "%.1f %@", value, suffix)
    }

    /// Elevation in the user's unit with grouping, e.g. "12,480 ft" — a tile-friendly headline
    /// number (unlike `Format.elevation`, which isn't grouped).
    private func climbValue(_ meters: Double) -> String {
        let unit = UnitSystem.current
        let value = unit == .miles ? meters * 3.28084 : meters
        let suffix = unit == .miles ? "ft" : "m"
        return "\(Int(value).formatted()) \(suffix)"
    }

    // MARK: All-Activities — the per-discipline hub ("bigger story")

    /// The scopes with their own detail page, in order — All excluded, hidden types dropped.
    private var breakdownScopes: [ActivityScope] {
        ActivitySettings.visibleScopes.filter { $0 != .all }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Your movement")
                    .font(.etch(.title3, weight: .bold))
                Spacer()
                Text("Tap to explore")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(derived.breakdown, id: \.scope) { entry in
                Button { setScope(entry.scope) } label: { breakdownRow(entry.scope, entry.stats) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func breakdownRow(_ s: ActivityScope, _ subset: RunStatistics) -> some View {
        HStack(spacing: 14) {
            Image(systemName: s.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accentOnGlass)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(s.label)
                    .font(.etch(.headline, weight: .bold))
                Text(breakdownDetail(s, subset))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(subset.totalRuns.formatted())
                    .font(.etch(.title3, weight: .bold))
                Text(s.countNoun)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    /// The secondary line under each discipline — distance always, plus climb for hikes and
    /// moving time for walks, so each type leads with the metric that suits it.
    private func breakdownDetail(_ s: ActivityScope, _ subset: RunStatistics) -> String {
        let distance = Format.distance(subset.totalDistanceMeters, decimals: 0)
        switch s {
        case .hikes: return "\(distance) · \(Format.elevation(subset.totalElevationMeters)) climbed"
        case .walks: return "\(distance) · \(Format.duration(subset.totalMovingTime))"
        default:     return "\(distance) · \(Format.duration(subset.totalMovingTime))"
        }
    }

    // MARK: Specific activity — records & bests

    private var superlativesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standout moments")
                .font(.etch(.title3, weight: .bold))

            // Rendered from `stats.records(usesPace:)` rather than composed here, so the records
            // this page shows and the records search finds are the same list. Pace records are
            // gated inside it, on the same rule as before: pace is a running concept.
            ForEach(records.filter { $0.group == .superlative }) { record in
                SuperlativeRow(icon: record.symbol, title: record.title,
                               value: record.value, subtitle: record.detail) { focus(record.run) }
            }
            // Most Visited stays here rather than joining the list: it is a record about a place
            // rather than about an activity, it opens a different screen, and forcing it into a
            // shape built around "the run that holds it" would have meant inventing one.
            if let visited = derived.mostVisitedArea {
                NavigationLink {
                    CitiesListView(places: derived.travelPlaces)
                } label: {
                    SuperlativeRow(icon: "repeat", title: "Most Visited", value: "\(visited.count)×", subtitle: visited.label, showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Every record this history holds, from the one definition both this page and search read.
    private var records: [RunStatistics.Record] { derived.records }

    @ViewBuilder
    private var personalBestsSection: some View {
        let bests = records.filter { $0.group == .personalBest }
        if !bests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Personal bests")
                    .font(.etch(.title3, weight: .bold))

                ForEach(bests) { pr in
                    SuperlativeRow(icon: pr.symbol, title: pr.title,
                                   value: pr.value, subtitle: pr.detail) { focus(pr.run) }
                }
            }
        }
    }

    // MARK: Recaps (shared, scopes with the selection)

    private var recapsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(derived.years, id: \.self) { year in
                NavigationLink {
                    YearInReviewView(year: year)
                } label: {
                    let yearStats = derived.yearTotals[year] ?? (runs: 0, distance: 0)
                    HStack {
                        Text(String(year))
                            .font(.etch(.title3, weight: .bold))
                        Spacer()
                        Text("\(yearStats.runs) \(scope.countNoun) · \(Format.distance(yearStats.distance, decimals: 0))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 18)
                    .background(.regularMaterial, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func focus(_ run: Run) {
        // As a tab, push. As a sheet, hand off to the map.
        //
        // The second branch is the original behaviour and is still right when Highlights is a
        // sheet HomeView presented: clearing the surface dismisses it and HomeView's router
        // brings up the detail behind. It is wrong for a tab — there is nothing to dismiss and
        // HomeView is elsewhere — which is exactly how the Timeline's thumbnails went dead.
        // Fixed here at the same time rather than waiting for the same report twice.
        // Pushing sets no `selectedRunID`: HomeView's sheet router reads that as "present this
        // run", and HomeView stays mounted on the map tab, so setting it here opened the activity
        // twice — a sheet from the bottom over the pushed page. The map still gets its camera
        // command. Same fix as the Timeline's, made here at the same time rather than waiting for
        // the same report twice.
        if embedded {
            appModel.focus(on: run)
            pushedRun = run
        } else {
            appModel.select(run)
            appModel.presentedSurface = nil
        }
    }
}

/// A photograph and its own map share one composition. Map snapshots are cached by the existing
/// route tile renderer; no live map participates in scrolling or commerce rendering.
private struct StoryArtwork: View {
    let run: Run
    @State private var photograph: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(height: 220)
            .overlay {
                if let photograph {
                    Image(uiImage: photograph).resizable().scaledToFill()
                } else if run.hasRoute {
                    RouteMapTile(run: run)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "figure.walk").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text(run.placeLabel.isEmpty ? Format.date(run.startDate) : run.placeLabel)
                            .font(.etch(.headline))
                        Text("\(Format.distance(run.distance)) · \(Format.date(run.startDate))")
                            .font(.etch(.caption)).foregroundStyle(.secondary)
                    }.padding(20)
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if photograph != nil && run.hasRoute {
                    RouteMapTile(run: run)
                        .frame(width: 104, height: 104)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.8), lineWidth: 2) }
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .padding(12)
                }
            }
            .accessibilityHidden(true)
            .task(id: run.memoryPhotoReferences) {
                photograph = nil
                for identifier in run.memoryPhotoReferences {
                    let loaded = await PhotoLibrary.image(for: identifier, targetSize: CGSize(width: 1000, height: 660))
                    guard !Task.isCancelled else { return }
                    if let loaded { photograph = loaded; break }
                }
            }
    }
}

private struct StoryStat: View {
    let value: String
    let label: String
    let systemName: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: systemName)
                .font(.etch(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(accent ? Theme.accent : Color.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

/// A compact count chart with its complete values available to VoiceOver.
private struct StoryMarks: View {
    let marks: [DailyStoryEngine.Mark]
    private var maximum: Int { max(1, marks.map(\.value).max() ?? 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(marks.count == 8 ? "Active days · last 8 complete weeks" : "Active days · by weekday")
                .font(.etch(.caption)).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                    VStack(spacing: 5) {
                        Text("\(mark.value)").font(.caption2).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(mark.value == 0 ? Color.secondary.opacity(0.15) : Theme.accent.opacity(0.85))
                            .frame(height: max(4, 44 * Double(mark.value) / Double(maximum)))
                        Text(marks.count == 8 ? "\(index + 1)" : String(mark.label.prefix(2)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marks.map { "\($0.label): \($0.value) active days" }.joined(separator: "; "))
    }
}
