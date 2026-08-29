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

    /// Runs limited to the app-wide activity scope (All / Runs / Hikes / Walks).
    private var scopedRuns: [Run] { runs.scoped(to: scope) }
    /// Reach and the per-discipline breakdown describe everywhere you've been, so they include
    /// every activity. Records, personal bests, and year sums use only the counting activities.
    private var reachStats: RunStatistics { RunStatistics(scopedRuns) }
    private var stats: RunStatistics { RunStatistics(scopedRuns.countingTotals) }

    var body: some View {
        NavRoot(embedded) {
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
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                // Heal a stored scope that's since been hidden in Settings so it doesn't linger.
                if !ActivitySettings.isVisible(appModel.activityScope) { setScope(.all) }
            }
            // Recompute the GPS-attributed reach whenever the scope or the located-run set changes.
            .task(id: reachKey) { await computeReachGeo() }
        }
    }

    /// Keys the reach computation to the scope and the number of located runs, so it re-runs when
    /// the user switches activity or new routes give older runs coordinates.
    private var reachKey: String {
        "\(scope.rawValue)-\(scopedRuns.reduce(0) { $0 + ($1.startLatitude != nil ? 1 : 0) })"
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
                    CitiesListView(places: reachStats.travelPlaces)
                } label: {
                    // Match the Cities map / list, which cluster by place (travelPlaces), not the
                    // raw distinct-city-name set.
                    StatTile(value: reachStats.travelPlaces.count.formatted(), label: "Cities", systemName: "building.2", accent: true)
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
                    value: Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0))),
                    label: "Total \(UnitSystem.current.distanceSuffix)",
                    systemName: scope.icon,
                    accent: true
                )
                // For climbing disciplines (hikes, rides) elevation is a headline metric, not an
                // afterthought — surface total ascent and the average per outing.
                if scopeClimbs {
                    StatTile(value: climbValue(stats.totalElevationMeters), label: "Total climb",
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
        (reachGeo.ready ? reachGeo.states : reachStats.states.count).formatted()
    }
    private var reachCountryValue: String {
        (reachGeo.ready ? reachGeo.countries : reachStats.countries.count).formatted()
    }

    /// Whether the current scope is a climbing-forward discipline that should lead with elevation.
    private var scopeClimbs: Bool { scope == .hikes || scope == .rides }

    /// Mean ascent per activity, for the "Avg climb" tile.
    private var averageClimb: Double {
        stats.totalRuns > 0 ? stats.totalElevationMeters / Double(stats.totalRuns) : 0
    }

    /// Distance-weighted average speed in the user's unit (mph / km/h) — the ride headline metric.
    private var averageSpeedValue: String {
        guard stats.totalMovingTime > 0 else { return "—" }
        return speedString(stats.totalDistanceMeters / Double(stats.totalMovingTime))
    }

    /// The fastest recorded top speed, when a source provided one for any ride in scope.
    private var topSpeedValue: String? {
        guard let metersPerSecond = stats.topSpeed, metersPerSecond > 0 else { return nil }
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

            ForEach(breakdownScopes) { s in
                let subset = RunStatistics(runs.scoped(to: s))
                if subset.totalRuns > 0 {
                    Button { setScope(s) } label: { breakdownRow(s, subset) }
                        .buttonStyle(.plain)
                }
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

            if let furthest = stats.longestRun {
                SuperlativeRow(icon: "arrow.left.and.right", title: "Furthest", value: Format.distance(furthest.distance), subtitle: furthest.name) { focus(furthest) }
            }
            if let longest = stats.longestDurationRun {
                SuperlativeRow(icon: "clock", title: "Longest", value: Format.duration(longest.movingTime), subtitle: longest.name) { focus(longest) }
            }
            if let climb = stats.highestClimb {
                SuperlativeRow(icon: "mountain.2", title: "Highest Climb", value: Format.elevation(climb.elevationGain), subtitle: climb.name) { focus(climb) }
            }
            // Pace is a running concept — hidden for hikes/walks.
            if scope.usesPace, let fastest = stats.fastestRun {
                SuperlativeRow(icon: "bolt.fill", title: "Fastest Pace", value: Format.pace(secondsPerKm: fastest.paceSecondsPerKm), subtitle: fastest.name) { focus(fastest) }
            }
            if let north = stats.northernmostRun {
                SuperlativeRow(icon: "arrow.up", title: "Northernmost", value: north.placeLabel.isEmpty ? "—" : north.placeLabel, subtitle: north.name) { focus(north) }
            }
            if let south = stats.southernmostRun {
                SuperlativeRow(icon: "arrow.down", title: "Southernmost", value: south.placeLabel.isEmpty ? "—" : south.placeLabel, subtitle: south.name) { focus(south) }
            }
            if let visited = stats.mostVisitedArea {
                NavigationLink {
                    CitiesListView(places: stats.travelPlaces)
                } label: {
                    SuperlativeRow(icon: "repeat", title: "Most Visited", value: "\(visited.count)×", subtitle: visited.label, showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var personalBestsSection: some View {
        let prs = stats.personalRecords
        // Distance-time PRs are a running concept; only shown when pace applies.
        if scope.usesPace, !prs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Personal Bests")
                    .font(.etch(.title3, weight: .bold))

                ForEach(prs) { pr in
                    SuperlativeRow(
                        icon: "stopwatch",
                        title: pr.label,
                        value: Format.duration(pr.time),
                        subtitle: "\(Format.pace(secondsPerKm: pr.run.paceSecondsPerKm)) pace"
                    ) { focus(pr.run) }
                }
            }
        }
    }

    // MARK: Recaps (shared, scopes with the selection)

    private var recapsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Year in Review")
                .font(.etch(.title3, weight: .bold))

            ForEach(stats.years, id: \.self) { year in
                NavigationLink {
                    YearInReviewView(year: year)
                } label: {
                    let yearStats = stats.statistics(forYear: year)
                    HStack {
                        Text(String(year))
                            .font(.etch(.title3, weight: .bold))
                        Spacer()
                        Text("\(yearStats.totalRuns) \(scope.countNoun) · \(Format.distance(yearStats.totalDistanceMeters, decimals: 0))")
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
        // Swap the Highlights sheet for the run's detail and zoom the map to it. We do NOT call
        // dismiss() here: dismissing sets the shared sheet binding to nil, which clears the
        // selection before the run detail can present. Changing the state does the swap.
        appModel.select(run)             // selectedRunID (opens detail) + focus command (zoom)
        appModel.presentedSurface = nil  // closes Highlights; detail takes its place
    }
}
