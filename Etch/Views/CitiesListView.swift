import SwiftUI

/// Every city you've run in: a header, an overview map of the cities, and a ranked list
/// (most-visited first) — mirroring the States page layout.
struct CitiesListView: View {
    /// One entry per city, already sorted by run count descending (`RunStatistics.travelPlaces`).
    let places: [RunStatistics.TravelPlace]

    private var totalRuns: Int { places.reduce(0) { $0 + $1.runs.count } }
    private var totalDistance: Double { places.reduce(0) { $0 + $1.totalDistance } }
    private var maxRuns: Int { places.map(\.runs.count).max() ?? 1 }

    var body: some View {
        ScrollView {
            if places.isEmpty {
                ContentUnavailableView(
                    "No cities yet",
                    systemImage: "building.2",
                    description: Text("Cities appear once your runs have GPS locations.")
                )
                .padding(.top, 60)
            } else {
                VStack(spacing: 20) {
                    header

                    CitiesMapView(
                        cities: places,
                        selectedRunID: .constant(nil),
                        stackedRunIDs: .constant(nil),
                        mapStyle: .standard
                    )
                    .frame(height: 340)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))

                    list
                }
                .padding(20)
            }
        }
        .navigationTitle("Cities")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(places.count)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text(places.count == 1 ? "city" : "cities")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(totalRuns) runs · \(Format.distance(totalDistance, decimals: 0))")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cardRadius))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where you've run")
                .font(.system(.title3, design: .rounded).weight(.bold))

            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                CityRow(
                    rank: index + 1,
                    place: place,
                    fraction: Double(place.runs.count) / Double(maxRuns)
                )
            }
        }
    }
}

private struct CityRow: View {
    let rank: Int
    let place: RunStatistics.TravelPlace
    let fraction: Double

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(place.label)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(Theme.accent)
                            .frame(width: max(6, geo.size.width * max(0.03, fraction)))
                    }
                }
                .frame(height: 6)
                Text(Format.distance(place.totalDistance, decimals: 0))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text("\(place.runs.count)")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text("runs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
