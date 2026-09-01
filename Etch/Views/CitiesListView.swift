import SwiftUI

/// Every city you've run in: a header, an overview map of the cities, and a ranked list
/// (most-visited first) — mirroring the States page layout.
struct CitiesListView: View {
    /// One entry per city, already sorted by run count descending (`RunStatistics.travelPlaces`).
    let places: [RunStatistics.TravelPlace]
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    /// Narrows the whole app to one city, then steps back so the result is visible.
    ///
    /// This is the fast path the location filter never had. Races and PRs are one tap on the map;
    /// a place took opening the filter sheet, scrolling to Where and picking from a menu — which
    /// is a lot of work to ask of someone already looking at a list of their cities.
    ///
    /// Popping is part of it. Applying a filter and staying on a page that does not show the
    /// filter would be a global change with no visible effect; going back one step lands on
    /// Achievements, where the chip states what is now set and clears it in a tap.
    private func narrow(to place: RunStatistics.TravelPlace) {
        guard let city = place.runs.first?.city, !city.isEmpty else { return }
        var filter = appModel.filter
        // The city alone, not city + state. Two cities of the same name in different states is a
        // real thing, but the pairing here comes from one group of activities that already share
        // both — and setting the state as well would survive a later change of city and quietly
        // narrow something the user never asked to narrow.
        filter.city = city
        filter.state = nil
        filter.country = nil
        appModel.setFilter(filter)
        dismiss()
    }

    private var totalRuns: Int { places.reduce(0) { $0 + $1.runs.count } }
    /// Every activity behind the list, so the count can be named in the right word — "42 hikes"
    /// when that is all this history holds, "activities" the moment it is mixed.
    private var allRuns: [Run] { places.flatMap(\.runs) }
    private var totalDistance: Double { places.reduce(0) { $0 + $1.totalDistance } }
    private var maxRuns: Int { places.map(\.runs.count).max() ?? 1 }

    var body: some View {
        ScrollView {
            if places.isEmpty {
                ContentUnavailableView(
                    "No cities yet",
                    systemImage: "building.2",
                    description: Text("Cities appear once your activities have GPS locations.")
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
                    .font(.etch(size: 44, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                Text(places.count == 1 ? "city" : "cities")
                    .font(.etch(.title3, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text("\(totalRuns) \(ActivityScope.noun(for: allRuns, count: totalRuns)) · \(Format.distance(totalDistance, decimals: 0))")
                .font(.etch(.subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cardRadius))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where you've been")
                .font(.etch(.title3, weight: .bold))

            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                Button {
                    narrow(to: place)
                } label: {
                    CityRow(
                        rank: index + 1,
                        place: place,
                        fraction: Double(place.runs.count) / Double(maxRuns)
                    )
                }
                .buttonStyle(.plain)
                .id(place.id)
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
                .font(.etch(.subheadline, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(place.label)
                    .font(.etch(.subheadline, weight: .semibold))
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
                .font(.etch(.headline))
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text(ActivityScope.noun(for: place.runs))
                .font(.caption)
                .foregroundStyle(.secondary)

            // The same glyph the filter chip wears, so the row says what tapping it does. A row
            // that silently changes app-wide state needs to look like a control, and a chevron
            // would promise a page that does not exist.
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }
}
