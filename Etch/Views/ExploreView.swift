import SwiftUI
import SwiftData

/// A fun, rewarding statistics screen: where you've been and what you've conquered.
struct ExploreView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query private var runs: [Run]

    private var stats: RunStatistics { RunStatistics(runs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    reachSection
                    superlativesSection
                    recapsSection
                }
                .padding(20)
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var reachSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You have run")
                .font(.system(.title2, design: .rounded).weight(.bold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(value: stats.cities.count.formatted(), label: "Cities", systemName: "building.2", accent: true)
                StatTile(value: stats.states.count.formatted(), label: "States", systemName: "map")
                StatTile(value: stats.countries.count.formatted(), label: "Countries", systemName: "globe")
                StatTile(
                    value: Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0))),
                    label: "Total \(UnitSystem.current.distanceSuffix)",
                    systemName: "figure.run",
                    accent: true
                )
            }
        }
    }

    private var superlativesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Records")
                .font(.system(.title3, design: .rounded).weight(.bold))

            if let longest = stats.longestRun {
                SuperlativeRow(icon: "arrow.left.and.right", title: "Longest Run", value: Format.distance(longest.distance), subtitle: longest.name) { focus(longest) }
            }
            if let climb = stats.highestClimb {
                SuperlativeRow(icon: "mountain.2", title: "Highest Climb", value: Format.elevation(climb.elevationGain), subtitle: climb.name) { focus(climb) }
            }
            if let fastest = stats.fastestRun {
                SuperlativeRow(icon: "bolt.fill", title: "Fastest Pace", value: Format.pace(secondsPerKm: fastest.paceSecondsPerKm), subtitle: fastest.name) { focus(fastest) }
            }
            if let north = stats.northernmostRun {
                SuperlativeRow(icon: "arrow.up", title: "Northernmost", value: north.placeLabel.isEmpty ? "—" : north.placeLabel, subtitle: north.name) { focus(north) }
            }
            if let south = stats.southernmostRun {
                SuperlativeRow(icon: "arrow.down", title: "Southernmost", value: south.placeLabel.isEmpty ? "—" : south.placeLabel, subtitle: south.name) { focus(south) }
            }
            if let visited = stats.mostVisitedArea {
                SuperlativeRow(icon: "repeat", title: "Most Visited", value: "\(visited.count)×", subtitle: visited.label, action: nil)
            }
        }
    }

    private var recapsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Year in Review")
                .font(.system(.title3, design: .rounded).weight(.bold))

            ForEach(stats.years, id: \.self) { year in
                NavigationLink {
                    YearInReviewView(year: year)
                } label: {
                    let yearStats = stats.statistics(forYear: year)
                    HStack {
                        Text(String(year))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                        Spacer()
                        Text("\(yearStats.totalRuns) runs · \(Format.distance(yearStats.totalDistanceMeters, decimals: 0))")
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
        appModel.select(run)
        appModel.presentedSurface = nil
        dismiss()
    }
}
