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
    @Environment(\.dismiss) private var dismiss
    @Query private var runs: [Run]

    /// GPS-attributed reach, computed off-main so the counts match exactly what the States and
    /// Countries maps shade (point-in-polygon), rather than the looser geocoded label sets — which
    /// over-count DC/territories, foreign regions, spelling variants, and GPS-less imported runs.
    private struct ReachGeo { var states = 0; var countries = 0; var ready = false }
    @State private var reachGeo = ReachGeo()

    /// Concrete activity types (not "All") that are both enabled in Settings and actually present.
    /// When only one qualifies, there's nothing to switch between.
    private var presentActivityScopes: [ActivityScope] {
        [.runs, .hikes, .rides, .walks].filter { ActivitySettings.isVisible($0) && !runs.scoped(to: $0).isEmpty }
    }
    private var isSingleActivity: Bool { presentActivityScopes.count <= 1 }
    private var soleScope: ActivityScope { presentActivityScopes.first ?? .runs }

    /// The scope actually shown: the sole type when there's only one (no switcher), `.all` if the
    /// stored scope was hidden in Settings, otherwise the user's selection.
    private var scope: ActivityScope {
        if isSingleActivity { return soleScope }
        if !ActivitySettings.isVisible(appModel.activityScope) { return .all }
        return appModel.activityScope
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
    /// Same reasoning as the Timeline for the filter reaching here: "your cities" means the
    /// cities in what you are currently looking at rather than the cities in everything. A
    /// records page that ignored the filter would quietly contradict the map beside it.
    ///
    /// Reach and the per-discipline breakdown describe everywhere you've been, so they include
    /// every activity. Records, personal bests and year sums use only the counting activities.
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
                    VStack(spacing: 24) {
                        // With more than one activity type, offer the switcher; a single type just
                        // shows its own achievements with no chooser.
                        if !isSingleActivity { scopeSwitcher }
                        if scope == .all {
                            // The bigger story: combined reach, a per-discipline hub, and recaps.
                            reachSection
                            breakdownSection
                            recapsSection
                        } else {
                            // One discipline's deep dive: its records, bests, and recaps.
                            reachSection
                            superlativesSection
                            personalBestsSection
                            recapsSection
                        }
                    }
                    .padding(20)
                    // The whole content is the anchor, scrolled to its own top edge. Nothing on
                    // this page carries an id of its own and the first section changes with the
                    // scope, so naming a section would name a different one depending on where
                    // you were.
                    .id("top")
                }
                // Tap Achievements while you are already there and the page returns to the top.
                .onChange(of: appModel.reselectCount) { _, _ in
                    guard appModel.reselectedTab == .achievements else { return }
                    pushedRun = nil
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                }
                // The one place this page's data is built. Everything else reads values.
                .onChange(of: derivedKey, initial: true) { _, _ in rebuildDerived() }
                .navigationTitle("Achievements")
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
                            EtchPageHeader("Achievements")
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

    /// Keys the reach computation to the scope and the number of located runs, so it re-runs when
    /// the user switches activity or new routes give older runs coordinates.
    private var reachKey: String {
        "\(scope.rawValue)-\(derived.locatedCount)"
    }

    /// Attributes each located run to a US state and a country by point-in-polygon — off the main
    /// actor — so the reach tiles read exactly what the maps shade. Coordinates are snapshotted on
    /// the main actor first (Run isn't Sendable); the polygon tests run detached.
    private func computeReachGeo() async {
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

    // MARK: Reach (shared, scopes with the selection)

    private var reachSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your reach")
                .font(.etch(.title2, weight: .bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    CitiesListView(places: derived.travelPlaces)
                } label: {
                    // Match the Cities map / list, which cluster by place (travelPlaces), not the
                    // raw distinct-city-name set.
                    StatTile(value: derived.travelPlaces.count.formatted(), label: "Cities", systemName: "building.2", accent: true)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    StatesView()
                } label: {
                    StatTile(value: reachStateValue, label: "States", systemName: "map")
                }
                .buttonStyle(.plain)
                StatTile(value: reachCountryValue, label: "Countries", systemName: "globe")
                StatTile(
                    value: Format.distanceValue(derived.totalDistance).formatted(.number.precision(.fractionLength(0))),
                    label: "Total \(UnitSystem.current.distanceSuffix)",
                    systemName: scope.icon,
                    accent: true
                )
                // For climbing disciplines (hikes, rides) elevation is a headline metric, not an
                // afterthought — surface total ascent and the average per outing.
                if scopeClimbs {
                    StatTile(value: climbValue(derived.totalElevation), label: "Total climb",
                             systemName: "mountain.2", accent: true)
                    StatTile(value: climbValue(averageClimb), label: "Avg climb",
                             systemName: "arrow.up.forward")
                }
                // Speed is a headline metric for rides (pace suits runs) — surface average and,
                // when a source recorded it, top speed.
                if scope == .rides {
                    StatTile(value: averageSpeedValue, label: "Avg speed", systemName: "speedometer", accent: true)
                    if let top = topSpeedValue {
                        StatTile(value: top, label: "Top speed", systemName: "gauge.high")
                    }
                }
            }
        }
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
                Text("Your activities")
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
            Text("Records")
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
                Text("Personal Bests")
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
            Text("Year in Review")
                .font(.etch(.title3, weight: .bold))

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
