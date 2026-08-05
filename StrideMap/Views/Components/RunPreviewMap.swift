import SwiftUI
import MapKit

/// A small, non-interactive map preview of a single run's route. Used in Run Details.
struct RunPreviewMap: View {
    let run: Run
    var interactive: Bool = false

    private var coordinates: [CLLocationCoordinate2D] { run.coordinates }

    var body: some View {
        Map(initialPosition: .region(region), interactionModes: interactive ? .all : []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(
                        Theme.accent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
            if let start = run.startCoordinate {
                Annotation("", coordinate: start) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(interactive)
    }

    private var region: MKCoordinateRegion {
        guard run.maxLatitude != run.minLatitude || run.maxLongitude != run.minLongitude else {
            let center = run.startCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
        let center = CLLocationCoordinate2D(
            latitude: (run.minLatitude + run.maxLatitude) / 2,
            longitude: (run.minLongitude + run.maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (run.maxLatitude - run.minLatitude) * 1.4 + 0.002,
            longitudeDelta: (run.maxLongitude - run.minLongitude) * 1.4 + 0.002
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
