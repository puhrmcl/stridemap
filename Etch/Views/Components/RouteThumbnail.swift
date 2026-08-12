import SwiftUI
import CoreLocation

/// A lightweight, static thumbnail of a run's route — the shape drawn as a blue line on a
/// dark tile. Cheap enough to render hundreds in a grid (unlike a live `Map`), and gives the
/// timeline an "etched" look. Runs without a route show a quiet placeholder.
struct RouteThumbnail: View {
    let run: Run
    var lineWidth: CGFloat = 2.5

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
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
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
