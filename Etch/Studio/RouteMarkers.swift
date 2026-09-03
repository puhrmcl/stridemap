import SwiftUI
import CoreLocation

/// Where a route begins and where it ends, marked on the artwork.
///
/// Every serious print in this category marks both ends, and for good reason: an unmarked line is a
/// shape, while a line with a start and a finish is a journey with a direction. The start is an
/// open ring, the finish a solid point, and a race's finish carries one fine accent halo — the
/// medallion. Quiet cartography, in the line's own colours.
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

            // The marker language is quiet cartography, not novelty: an open ring says "this is
            // where it began", a solid point says "this is where it ended", and a race's finish
            // earns one fine concentric halo — a medallion, not a chequerboard. The chequer read
            // as clip-art at poster size; two weights of the same circle read as typography.
            if !isLoop {
                ring(context, at: first, radius: routeWidth * 1.05)
            }
            point(context, at: last, radius: routeWidth * 1.1)
            if isRace {
                halo(context, at: last, radius: routeWidth * 1.9)
            }
        }
        .allowsHitTesting(false)
    }

    /// The start: an open ring in the route's own colour over a ground-filled centre, so the line
    /// visibly *leaves* a hollow point. Ground casing separates it from whatever it sits on.
    private func ring(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        let stroke = max(1.5, routeWidth * 0.5)
        context.fill(Path(ellipseIn: square(point, radius + stroke)), with: .color(ground))
        context.stroke(Path(ellipseIn: square(point, radius)),
                       with: .color(finish), lineWidth: stroke)
    }

    /// The finish: a solid point in the route's colour inside a ground casing.
    private func point(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        context.fill(Path(ellipseIn: square(point, radius + routeWidth * 0.45)),
                     with: .color(ground))
        context.fill(Path(ellipseIn: square(point, radius)), with: .color(finish))
    }

    /// The race finish's halo: one fine ring in the accent, spaced off the point — the medallion.
    private func halo(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        context.stroke(Path(ellipseIn: square(point, radius)),
                       with: .color(start), lineWidth: max(1.2, routeWidth * 0.3))
    }

    private func square(_ centre: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}
