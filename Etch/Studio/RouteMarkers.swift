import SwiftUI
import CoreLocation

/// Where a route begins and where it ends, marked on the artwork.
///
/// Every serious print in this category marks both ends, and for good reason: an unmarked line is a
/// shape, while a line with a start and a finish is a journey with a direction. It is also the
/// detail that reads instantly as a *race* print when the finish carries a chequer.
///
/// Etch drew these on map panels and nowhere else, so the same run rendered as Minimal — the
/// route alone on paper, our most restrained and most printable piece — had no ends at all. These
/// markers project through `RouteShape.projectedPoints`, the exact projection that drew the line,
/// so they sit on it rather than beside it.
struct RouteEndpointMarkers: View {
    let coordinates: [CLLocationCoordinate2D]
    /// The start pip — the edition's accent, so it reads as a signal rather than as more route.
    let start: Color
    /// The finish, in the route's own colour.
    let finish: Color
    /// The sheet beneath, used for the ring that separates a marker from whatever it sits on.
    let ground: Color
    /// A race finishes under a chequered flag. A training run just stops.
    let isRace: Bool
    /// The route's stroke width, which the markers are sized from — they have to belong to the
    /// line, not to the page.
    let routeWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let points = RouteShape.projectedPoints(
                coordinates, in: CGRect(origin: .zero, size: size)
            )
            guard let first = points.first, let last = points.last else { return }

            // A loop returns to where it started, and stacking two markers on one spot just makes
            // a smudge. Within a stroke-width of each other, only the finish is drawn.
            let isLoop = hypot(last.x - first.x, last.y - first.y) < routeWidth * 1.6

            if !isLoop {
                dot(context, at: first, radius: routeWidth * 1.15, fill: start)
            }
            if isRace {
                chequer(context, at: last, radius: routeWidth * 1.45)
            } else {
                dot(context, at: last, radius: routeWidth * 1.15, fill: finish)
            }
        }
        .allowsHitTesting(false)
    }

    /// A filled pip inside a ring of the ground colour, so it separates from the route and from
    /// whatever the route is drawn over.
    private func dot(_ context: GraphicsContext, at point: CGPoint,
                     radius: CGFloat, fill: Color) {
        let ring = radius + routeWidth * 0.45
        context.fill(Path(ellipseIn: square(point, ring)), with: .color(ground))
        context.fill(Path(ellipseIn: square(point, radius)), with: .color(fill))
    }

    /// The chequered finish: a ring of alternating squares around a solid centre. Drawn as
    /// geometry rather than as a flag glyph, because at print resolution a symbol font's flag
    /// turns to mush and this stays crisp at 300 DPI.
    private func chequer(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        let ring = radius + routeWidth * 0.4
        context.fill(Path(ellipseIn: square(point, ring)), with: .color(ground))
        context.fill(Path(ellipseIn: square(point, radius)), with: .color(finish))

        // The chequerboard, clipped to the disc.
        var inner = context
        inner.clip(to: Path(ellipseIn: square(point, radius)))
        let cells = 4
        let cell = radius * 2 / CGFloat(cells)
        let origin = CGPoint(x: point.x - radius, y: point.y - radius)
        for row in 0..<cells {
            for column in 0..<cells where (row + column).isMultiple(of: 2) {
                let rect = CGRect(x: origin.x + CGFloat(column) * cell,
                                  y: origin.y + CGFloat(row) * cell,
                                  width: cell, height: cell)
                inner.fill(Path(rect), with: .color(ground))
            }
        }
        // A hairline of route colour around the disc, so the pale squares never bleed into a pale
        // ground and leave the marker looking half-eaten.
        context.stroke(Path(ellipseIn: square(point, radius)),
                       with: .color(finish), lineWidth: max(1, routeWidth * 0.22))
    }

    private func square(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}
