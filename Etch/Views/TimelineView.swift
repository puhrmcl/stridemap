import SwiftUI
import SwiftData

/// Running history browsed like Apple Photos: a Years / Months / All segmented control, with
/// route thumbnails standing in for photos. Tap any run to zoom the map to it.
struct TimelineView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    enum Scope: String, CaseIterable, Identifiable {
        case years = "Years", months = "Months", all = "All"
        var id: String { rawValue }
    }
    @State private var scope: Scope = .years

    private var stats: RunStatistics { RunStatistics(runs) }
    private var monthGroups: [RunStatistics.MonthGroup] { stats.monthGroups }
    private var years: [Int] { stats.years }

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView(
                        "No Runs Yet",
                        systemImage: "calendar",
                        description: Text("Sync your runs to build your timeline.")
                    )
                } else {
                    ScrollView {
                        switch scope {
                        case .years: yearsContent
                        case .months: monthsContent
                        case .all: allContent
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !runs.isEmpty { scopePicker }
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
                    withAnimation(.easeInOut(duration: 0.25)) { scope = .months }
                } label: {
                    YearCard(
                        year: year,
                        hero: hero(in: yearRuns),
                        runCount: yearRuns.count,
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
        LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
            ForEach(monthGroups) { group in
                Section {
                    monthGrid(group.runs)
                } header: {
                    sectionHeader(title: Format.monthYear(group.date),
                                  detail: "\(group.runs.count) · \(Format.distance(group.totalDistance, decimals: 0))")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    /// A month's runs: a wide hero for the first, then a 3-up grid of the rest.
    @ViewBuilder
    private func monthGrid(_ monthRuns: [Run]) -> some View {
        if let hero = monthRuns.first {
            tile(hero, corner: 14)
                .frame(height: 150)
                .padding(.bottom, 6)
        }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(monthRuns.dropFirst()) { run in
                tile(run, corner: 10)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }

    // MARK: All

    private var allContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(runs) { run in
                tile(run, corner: 6)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    // MARK: Pieces

    private func tile(_ run: Run, corner: CGFloat) -> some View {
        Button { open(run) } label: {
            RouteThumbnail(run: run)
                .clipShape(.rect(cornerRadius: corner))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            Text(detail)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Data helpers

    private func runs(in year: Int) -> [Run] {
        let cal = Calendar.current
        return runs.filter { cal.component(.year, from: $0.startDate) == year }
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
    let runCount: Int
    let distanceMeters: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let hero {
                    RouteThumbnail(run: hero, lineWidth: 3)
                } else {
                    Color(white: 0.1)
                }
            }
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            VStack(alignment: .leading) {
                Text(String(year))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(runCount) runs · \(Format.distance(distanceMeters, decimals: 0))")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 20))
    }
}
