import SwiftUI
import MapKit

/// A choropleth of the United States: states you've run in are filled with the Etch accent
/// (deeper where you've run more), the rest lightly outlined. Read-only; pan/zoom enabled.
struct StatesMapView: UIViewRepresentable {

    /// Boundary name → fill intensity 0…1 (already compressed by the caller). Only visited
    /// regions appear here; the others render as faint outlines so the country still reads.
    var intensities: [String: Double]
    /// Base map style (standard / satellite / hybrid), shared with the route map.
    var mapStyle: MapStyleOption = .standard
    /// Set by the home-map "jump to state" menu; zooms to that state's boundary, then clears.
    var focusStateName: Binding<String?> = .constant(nil)

    func makeCoordinator() -> Coordinator { Coordinator(intensities: intensities) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        map.preferredConfiguration = mapStyle.configuration()
        context.coordinator.appliedStyle = mapStyle

        // Continental US to start; Alaska/Hawaii are a pan away.
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 40)
            ),
            animated: false
        )

        context.coordinator.install(on: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if context.coordinator.appliedStyle != mapStyle {
            context.coordinator.appliedStyle = mapStyle
            map.preferredConfiguration = mapStyle.configuration()
        }
        // Intensities are computed asynchronously after the map appears, so restyle and
        // force a redraw of any already-drawn renderers; not-yet-drawn ones pick up the
        // updated intensities from the coordinator when they're first rendered.
        context.coordinator.intensities = intensities
        for overlay in map.overlays {
            guard let renderer = map.renderer(for: overlay) as? MKPolygonRenderer,
                  let polygon = overlay as? MKPolygon else { continue }
            context.coordinator.style(renderer, for: polygon)
            renderer.setNeedsDisplay()
        }

        // A jump-to-state request: frame that state's boundary, then clear the binding so the
        // same state can be picked again later.
        if let name = focusStateName.wrappedValue,
           let rect = USStateBoundaries.shared.boundingMapRect(for: name) {
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 90, left: 40, bottom: 120, right: 40),
                animated: true
            )
            DispatchQueue.main.async { focusStateName.wrappedValue = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var intensities: [String: Double]
        var appliedStyle: MapStyleOption?
        /// Overlay identity → boundary name (overlays are the shared boundary polygons).
        private var nameByOverlay: [ObjectIdentifier: String] = [:]

        init(intensities: [String: Double]) { self.intensities = intensities }

        func install(on map: MKMapView) {
            for boundary in USStateBoundaries.shared.boundaries {
                for polygon in boundary.polygons {
                    nameByOverlay[ObjectIdentifier(polygon)] = boundary.name
                    map.addOverlay(polygon, level: .aboveRoads)
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            style(renderer, for: polygon)
            return renderer
        }

        func style(_ renderer: MKPolygonRenderer, for polygon: MKPolygon) {
            // Visited states fill in graduated Navy (deeper = more runs). Etch Blue is kept for
            // selection, so the choropleth reads as archival tone, not a flood of bright blue.
            let navy = UIColor(Theme.Palette.navy)
            let name = nameByOverlay[ObjectIdentifier(polygon)]
            if let name, let intensity = intensities[name] {
                renderer.fillColor = navy.withAlphaComponent(0.28 + 0.5 * CGFloat(intensity))
                renderer.strokeColor = navy.withAlphaComponent(0.85)
                renderer.lineWidth = 1
            } else {
                renderer.fillColor = .clear
                renderer.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.28)
                renderer.lineWidth = 0.5
            }
        }
    }
}
