import SwiftUI
import CoreLocation

/// The indoor/treadmill glyph, resolved once to the first available SF Symbol so a missing name
/// on any OS version can't render a blank box. Shared by every routeless-run surface.
enum IndoorGlyph {
    static let symbol: String = {
        for name in ["figure.run.treadmill", "figure.indoor.run", "figure.run"] where UIImage(systemName: name) != nil {
            return name
        }
        return "figure.run"
    }()
}

/// A lightweight, static thumbnail of a run's route — the shape drawn as a blue line on a
/// dark tile. Cheap enough to render hundreds in a grid (unlike a live `Map`), and gives the
/// timeline an "etched" look. Runs without a route show a quiet placeholder — an indoor
/// treatment for treadmill runs, or a plain runner for routes still syncing.
struct RouteThumbnail: View {
    let run: Run
    var lineWidth: CGFloat = 2.5

    /// The mark for a routeless activity: the treadmill for an indoor run, otherwise whatever
    /// the activity actually was. `ActivityType.detailIcon` already carries the whole set —
    /// run, walk, hike, ride, ski, swim, row — so a ride stops being drawn as a runner.
    private var glyph: String {
        run.isIndoor ? IndoorGlyph.symbol : run.activityType.detailIcon
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.07)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            let coordinates = run.coordinates
            if coordinates.count > 1 {
                RouteShape(coordinates: coordinates)
                    .stroke(
                        Theme.Route.recent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .padding(10)
            } else {
                // No route: the activity's own glyph, in the route's own blue.
                //
                // This used to be a grey `figure.run` on every routeless activity, which was
                // wrong twice over. Grey read as an error state — a tile apologising for missing
                // something — when a treadmill run or an untracked race is a perfectly good
                // activity that simply has no line to draw. And a runner glyph on a ride was
                // just incorrect, which the library's cycling and hiking made visible.
                //
                // Drawn in Theme.Route.recent, the same blue the route lines use, inside a ring:
                // in a grid of blue lines on dark tiles, a blue mark on a dark tile belongs to
                // the set. Grey did not.
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    ZStack {
                        Circle()
                            .strokeBorder(Theme.Route.recent.opacity(0.28),
                                          lineWidth: max(1, side * 0.02))
                            .frame(width: side * 0.52, height: side * 0.52)
                        Image(systemName: glyph)
                            .font(.system(size: side * 0.24, weight: .semibold))
                            .foregroundStyle(Theme.Route.recent)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
    }
}

/// The image for a run's Timeline tile: the run's top photo when it has one, otherwise the
/// route drawing. Falls back to the route if the photo can't load (e.g. deleted from library).
///
/// `mapFallback` upgrades the no-photo state from the flat route line to a brand-tinted MapKit
/// snapshot of the route — used by the year hero, where the larger tile earns a real map. It's
/// left off for dense grids (the "All" 4-up), where dozens of live snapshots would be wasteful.
struct RunTileImage: View {
    let run: Run
    var mapFallback: Bool = false
    @State private var photo: UIImage?
    @State private var triedPhoto = false

    private var photoID: String? { run.photoReferences.first }

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else if photoID != nil && !triedPhoto {
                Color(white: 0.12)   // brief loading state before the photo resolves
            } else if mapFallback {
                RouteMapTile(run: run)
            } else {
                RouteThumbnail(run: run)
            }
        }
        .task(id: photoID) {
            guard let id = photoID else { triedPhoto = true; return }
            triedPhoto = false
            photo = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 500, height: 500))
            triedPhoto = true
        }
    }
}

/// A brand-tinted MapKit snapshot of the run's route, sized to fill its tile. Shows the flat
/// route drawing while the snapshot renders — and permanently for runs with no route to map
/// (e.g. indoor), where the drawing supplies the indoor glyph. Snapshots are cached per
/// run + size by `PosterMap.tileImage`, so re-rendering the tile is cheap.
struct RouteMapTile: View {
    let run: Run
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    RouteThumbnail(run: run)
                }
            }
            .task(id: sizeKey(geo.size)) {
                guard geo.size.width > 1, geo.size.height > 1 else { return }
                image = await PosterMap.tileImage(for: run, size: geo.size)
            }
        }
    }

    private func sizeKey(_ size: CGSize) -> String { "\(Int(size.width))x\(Int(size.height))" }
}

/// Normalises a run's coordinates into the given rect, preserving aspect (longitude scaled by
/// cos(latitude) so the shape isn't stretched), with north up.
struct RouteShape: Shape {
    let coordinates: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count > 1 else { return Path() }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!

        let midLatRad = ((minLat + maxLat) / 2) * .pi / 180
        let lonScale = max(cos(midLatRad), 0.01)
        let dataWidth = max((maxLon - minLon) * lonScale, 1e-6)
        let dataHeight = max(maxLat - minLat, 1e-6)

        let scale = min(rect.width / dataWidth, rect.height / dataHeight)
        let drawWidth = dataWidth * scale
        let drawHeight = dataHeight * scale
        let offsetX = (rect.width - drawWidth) / 2
        let offsetY = (rect.height - drawHeight) / 2

        var path = Path()
        for (index, coordinate) in coordinates.enumerated() {
            let x = offsetX + (coordinate.longitude - minLon) * lonScale * scale
            let y = offsetY + (maxLat - coordinate.latitude) * scale   // flip so north is up
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
