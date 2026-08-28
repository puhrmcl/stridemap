import SwiftUI
import SwiftData

/// Running history browsed like Apple Photos: a Years / Months / All segmented control, with
/// route thumbnails standing in for photos. Tap any run to zoom the map to it.
struct TimelineView: View {
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    enum Scope: String, CaseIterable, Identifiable {
        case years = "Years", months = "Months", all = "All"
        var id: String { rawValue }
    }
    @State private var scope: Scope = .years
    /// Month section to scroll to after switching to Months (set when a year tile is tapped).
    @State private var scrollTarget: String?

    /// Runs limited to the app-wide activity scope (All / Runs / Hikes / Walks).
    private var scopedRuns: [Run] { runs.scoped(to: appModel.activityScope) }
    private var stats: RunStatistics { RunStatistics(scopedRuns) }
    private var monthGroups: [RunStatistics.MonthGroup] { stats.monthGroups }
    private var years: [Int] { stats.years }

    var body: some View {
        NavRoot(embedded) {
            Group {
                if scopedRuns.isEmpty {
                    ContentUnavailableView(
                        "No Runs Yet",
                        systemImage: "calendar",
                        description: Text("Sync your runs to build your timeline.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            switch scope {
                            case .years: yearsContent
                            case .months: monthsContent
                            case .all: allContent
                            }
                        }
                        // After a year tile switches us to Months, scroll to that year's start.
                        .task(id: scrollTarget) {
                            guard let target = scrollTarget else { return }
                            try? await Task.sleep(nanoseconds: 80_000_000)
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                            scrollTarget = nil
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            // Years / Months / All sits at the bottom as a sheet, and at the top inside the tab.
            //
            // Apple Photos docks exactly this control in a floating capsule at the foot of the
            // screen, which is the model this view was built on — but Photos has no tab bar, and
            // Etch now does. Two floating capsules stacked at the bottom is the app's own
            // navigation arguing with the page's, so inside the tab the control moves up under
            // the header, where it is plainly this page's and not the app's.
            .safeAreaInset(edge: .top) {
                if embedded && !scopedRuns.isEmpty { scopePicker }
            }
            .safeAreaInset(edge: .bottom) {
                if !embedded && !scopedRuns.isEmpty { scopePicker }
            }
        }
    }

    // MARK: Scope control

    private var scopePicker: some View {
        Picker("View", selection: $scope.animation(.easeInOut(duration: 0.25))) {
            ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 44)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Years

    private var yearsContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(years, id: \.self) { year in
                let yearRuns = runs(in: year)
                Button {
                    scrollTarget = firstMonthID(ofYear: year)
                    withAnimation(.easeInOut(duration: 0.25)) { scope = .months }
                } label: {
                    YearCard(
                        year: year,
                        hero: hero(in: yearRuns),
                        count: yearRuns.count,
                        countNoun: appModel.activityScope.countNoun,
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
            ForEach(monthGroups) { group in
                Section {
                    monthGrid(group.runs)
                } header: {
                    sectionHeader(title: Format.monthYear(group.date),
                                  detail: "\(group.runs.count) · \(Format.distance(group.totalDistance, decimals: 0))")
                }
                .id(group.id)
            }
        }
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
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

    private var allContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(scopedRuns) { run in
                photoTile(run, corner: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: Pieces

    /// A tappable run tile. `height` gives a fixed-height band (the month hero); otherwise the
    /// tile is a square sized to its column. A clear sizing container defines the frame and the
    /// image sits in an overlay that's clipped to it — so `scaledToFill` can never overflow the
    /// layout (which is what made tiles overlap).
    private func photoTile(_ run: Run, corner: CGFloat, height: CGFloat? = nil) -> some View {
        Button { open(run) } label: {
            Group {
                if let height {
                    Color.clear.frame(height: height)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
            .overlay { RunTileImage(run: run) }
            .clipShape(.rect(cornerRadius: corner))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { delete(run) } label: {
                Label("Delete Run", systemImage: "trash")
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
                .font(.system(.title, design: .rounded).weight(.bold))
            Text(detail)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    // MARK: Data helpers

    private func runs(in year: Int) -> [Run] {
        let cal = Calendar.current
        return scopedRuns.filter { cal.component(.year, from: $0.startDate) == year }
    }

    /// The id of the earliest month group in a year — the beginning of that year.
    private func firstMonthID(ofYear year: Int) -> String? {
        let cal = Calendar.current
        return monthGroups
            .filter { cal.component(.year, from: $0.date) == year }
            .min(by: { $0.date < $1.date })?.id
    }

    /// The most representative run for a year's hero image: the longest one that has a route.
    private func hero(in yearRuns: [Run]) -> Run? {
        yearRuns.filter(\.hasRoute).max { $0.distance < $1.distance } ?? yearRuns.first
    }

    private func open(_ run: Run) {
        // Swap this sheet for the run's detail (no dismiss(), which would clear the selection
        // before the detail could present).
        appModel.select(run)
        appModel.presentedSurface = nil
    }
}

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
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
            Spacer()
            Text("\(count) \(countNoun) · \(Format.distance(distanceMeters, decimals: 0))")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
                    Color(white: 0.1)
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
