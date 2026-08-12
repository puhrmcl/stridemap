import SwiftUI

/// Every city you've run in, ranked by how many runs started there (most-visited first).
struct CitiesListView: View {
    /// One entry per city, already sorted by run count descending (`RunStatistics.travelPlaces`).
    let places: [RunStatistics.TravelPlace]

    var body: some View {
        List(Array(places.enumerated()), id: \.element.id) { index, place in
            HStack(spacing: 14) {
                Text("\(index + 1)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(place.label)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text(Format.distance(place.totalDistance, decimals: 0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(place.runs.count)×")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .navigationTitle("Cities")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if places.isEmpty {
                ContentUnavailableView(
                    "No cities yet",
                    systemImage: "building.2",
                    description: Text("Cities appear once your runs have GPS locations.")
                )
            }
        }
    }
}
