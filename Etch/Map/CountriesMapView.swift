import SwiftUI
import MapKit

/// A choropleth of the world: countries you've run in are filled with the Etch accent (deeper
/// where you've run more), the rest lightly outlined so the globe still reads. Read-only;
/// pan/zoom enabled. The country sibling of `StatesMapView`.
struct CountriesMapView: UIViewRepresentable {

    /// Boundary name → fill intensity 0…1 (already compressed by the caller). Only visited
    /// countries appear here; the rest render as faint outlines.
    var intensities: [String: Double]
    /// Base map style (standard / satellite / hybrid), shared with the other maps.
    var mapStyle: MapStyleOption = .standard
    /// Set by the home-map "jump to country" menu; zooms to that country's boundary, then clears.
    var focusCountryName: Binding<String?> = .constant(nil)

    func makeCoordinator() -> Coordinator { Coordinator(intensities: intensities) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        map.preferredConfiguration = mapStyle.configuration()
        map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
        context.coordinator.appliedStyle = mapStyle

        // A broad world view to start; the map re-frames to your visited countries once the
        // intensities arrive (computed asynchronously after appearance).
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 180)
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
            map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
        }
        // Intensities are computed asynchronously after the map appears, so restyle and force a
        // redraw of already-drawn renderers; not-yet-drawn ones pick up the update when first
        // rendered.
        context.coordinator.intensities = intensities
        for overlay in map.overlays {
            guard let renderer = map.renderer(for: overlay) as? MKPolygonRenderer,
                  let polygon = overlay as? MKPolygon else { continue }
            context.coordinator.style(renderer, for: polygon)
            renderer.setNeedsDisplay()
        }

        // Once we know which countries are visited, frame them — but only the first time, so the
        // user's own panning is never fought afterwards.
        context.coordinator.frameVisitedIfNeeded(on: map)

        // A jump-to-country request: frame that country's boundary, then clear the binding.
        if let name = focusCountryName.wrappedValue,
           let rect = WorldCountryBoundaries.shared.boundingMapRect(for: name) {
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 90, left: 40, bottom: 120, right: 40),
                animated: true
            )
            DispatchQueue.main.async { focusCountryName.wrappedValue = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var intensities: [String: Double]
        var appliedStyle: MapStyleOption?
        private var nameByOverlay: [ObjectIdentifier: String] = [:]
        private var didFrameVisited = false

        init(intensities: [String: Double]) { self.intensities = intensities }

        func install(on map: MKMapView) {
            for boundary in WorldCountryBoundaries.shared.boundaries {
                for polygon in boundary.polygons {
                    nameByOverlay[ObjectIdentifier(polygon)] = boundary.name
                    map.addOverlay(polygon, level: .aboveRoads)
                }
            }
        }

        /// Frames the union of visited-country boundaries once the intensities are known, so the
        /// map opens on where you've actually run rather than the whole globe.
        func frameVisitedIfNeeded(on map: MKMapView) {
            guard !didFrameVisited, !intensities.isEmpty else { return }
            var rect = MKMapRect.null
            for boundary in WorldCountryBoundaries.shared.boundaries where intensities[boundary.name] != nil {
                rect = rect.union(boundary.boundingMapRect)
            }
            guard !rect.isNull else { return }
            didFrameVisited = true
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 100, left: 50, bottom: 140, right: 50),
                animated: true
            )
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            style(renderer, for: polygon)
            return renderer
        }

        func style(_ renderer: MKPolygonRenderer, for polygon: MKPolygon) {
            // Mirrors the states choropleth: visited countries fill graduated (deeper = more
            // runs) and read on any base map; unvisited ones keep a faint outline so the globe
            // still reads.
            let dark = (appliedStyle ?? .standard).isDarkBase
            let name = nameByOverlay[ObjectIdentifier(polygon)]

            if let name, let intensity = intensities[name] {
                if dark {
                    let blue = UIColor(Theme.Palette.blue)
                    renderer.fillColor = blue.withAlphaComponent(0.60 + 0.35 * CGFloat(intensity))
                    renderer.strokeColor = UIColor(Theme.Palette.bone).withAlphaComponent(0.95)
                    renderer.lineWidth = 2.0
                } else {
                    let navy = UIColor(Theme.Palette.navy)
                    renderer.fillColor = navy.withAlphaComponent(0.50 + 0.4 * CGFloat(intensity))
                    renderer.strokeColor = navy.withAlphaComponent(1.0)
                    renderer.lineWidth = 1.6
                }
            } else {
                renderer.fillColor = .clear
                renderer.strokeColor = dark
                    ? UIColor(Theme.Palette.bone).withAlphaComponent(0.6)
                    : UIColor.label.withAlphaComponent(0.5)
                renderer.lineWidth = dark ? 1.2 : 1.0
            }
        }
    }
}
