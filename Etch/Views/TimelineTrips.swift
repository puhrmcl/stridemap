import SwiftUI
import CoreLocation

/// TRIPS — the Timeline's chapters.
///
/// Years, Months and All are three ways of asking *when*. This asks *where*, which is the axis
/// Etch owns and a photo library cannot touch: it knows the route, not merely a geotag. A trip is
/// the unit that answers both at once — a bounded span, a named place, and almost always the part
/// of the history with the photographs in it.
///
/// The chapter leads with the trip's own routes drawn together on an ink ground. Not a map tile:
/// the lines someone actually covered in a place are more particular than a picture of the place,
/// and they are the app's own language.
struct TimelineTripChapter: View {
    let trip: TimelineJourneys.Trip
    let significance: [UUID: TimelineJourneys.Significance]
    let onOpen: (Run) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(TimelineJourneys.rows(for: trip.runs, significance: significance)) { row in
                switch row {
                case .hero(let run, let grade):
                    TimelineHeroTile(run: run, significance: grade) { onOpen(run) }
                case .strip(let runs):
                    HStack(spacing: 3) {
                        ForEach(runs) { run in
                            Button { onOpen(run) } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { RunTileImage(run: run, mapFallback: true) }
                                    .clipShape(.rect(cornerRadius: 10))
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                        // Keeps a short final strip aligned with the full ones above it rather
                        // than stretching two tiles across the width.
                        if runs.count < 3 {
                            ForEach(0..<(3 - runs.count), id: \.self) { _ in
                                Color.clear.aspectRatio(1, contentMode: .fit)
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.Brand.inkWell
            TripRoutesShape(routes: trip.routes)
                .stroke(Theme.Brand.blueLift.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .padding(18)
            LinearGradient(colors: [.clear, Theme.Brand.inkWell.opacity(0.85)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 5) {
                Text(trip.dateLine.uppercased())
                    .font(.etch(.caption2, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Theme.Brand.blueLift)
                Text(trip.title)
                    .font(.etch(.title2, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(trip.subtitle)
                    .font(.etch(.caption))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trip.title), \(trip.subtitle)")
    }
}

/// Every route of a trip in one shared projection.
///
/// Projecting each line to its own box would scale a two-mile shakeout to the same width as a
/// mountain day and throw away the only thing the group says together: how far apart these were.
/// One bounding box for all of them keeps the geography true.
struct TripRoutesShape: Shape {
    let routes: [[CLLocationCoordinate2D]]

    func path(in rect: CGRect) -> Path {
        let all = routes.flatMap { $0 }
        guard all.count > 1 else { return Path() }
        let lats = all.map(\.latitude), lons = all.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return Path() }

        // Longitude degrees shrink toward the poles; without the correction a Scottish trip comes
        // out stretched sideways.
        let midLat = (minLat + maxLat) / 2 * .pi / 180
        let lonScale = max(cos(midLat), 0.01)
        let spanX = max((maxLon - minLon) * lonScale, 0.000001)
        let spanY = max(maxLat - minLat, 0.000001)
        let scale = min(rect.width / spanX, rect.height / spanY)
        let drawnWidth = spanX * scale, drawnHeight = spanY * scale
        let originX = rect.midX - drawnWidth / 2, originY = rect.midY - drawnHeight / 2

        func point(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(x: originX + (c.longitude - minLon) * lonScale * scale,
                    // Latitude increases northward, y increases downward.
                    y: originY + (maxLat - c.latitude) * scale)
        }

        var path = Path()
        for route in routes where route.count > 1 {
            for (index, coordinate) in route.enumerated() {
                if index == 0 { path.move(to: point(coordinate)) }
                else { path.addLine(to: point(coordinate)) }
            }
        }
        return path
    }
}

/// A featured activity: full width, with the reason it was featured named on it.
///
/// The old grid captioned nothing, so you could not tell a first marathon from a Tuesday jog
/// without tapping. One line of type removes most of those taps.
struct TimelineHeroTile: View {
    let run: Run
    let significance: TimelineJourneys.Significance
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .frame(height: 190)
                .overlay { RunTileImage(run: run, mapFallback: true) }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.62)],
                                   startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) { caption }
                .clipShape(.rect(cornerRadius: 14))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(run.name), \(captionLine)")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label = significance.label {
                Text(label.uppercased())
                    .font(.etch(.caption2, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Theme.Brand.blueLift)
            }
            Text(run.name)
                .font(.etch(.subheadline, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(captionLine)
                .font(.etch(.caption2))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Place, distance, date — the three things the silent grid made you tap to learn.
    private var captionLine: String {
        var parts: [String] = []
        let place = [run.city, PlaceNames.canonicalState(run.state)]
            .compactMap { $0 }.filter { !$0.isEmpty }
        if let first = place.first { parts.append(first) }
        if let distance = StatMetric.distance.value(for: run) { parts.append(distance) }
        parts.append(run.startDate.formatted(.dateTime.day().month(.abbreviated)))
        return parts.joined(separator: "  ·  ")
    }
}
