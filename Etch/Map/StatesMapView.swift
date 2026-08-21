import SwiftUI
import MapKit

/// A choropleth of the United States: states you've run in are filled with the Etch accent
/// (deeper where you've run more), the rest lightly outlined. Read-only; pan/zoom enabled.
///
/// When a single state is *selected* (from the home-map "View" menu), the map centres on it,
/// unshades every other state, and drops a tappable pin for each run that started inside it —
/// so a chosen state reads on its own with its runs laid over it.
struct StatesMapView: UIViewRepresentable {

    /// Boundary name → fill intensity 0…1 (already compressed by the caller). Only visited
    /// regions appear here; the others render as faint outlines so the country still reads.
    var intensities: [String: Double]
    /// Base map style (standard / satellite / hybrid), shared with the route map.
    var mapStyle: MapStyleOption = .standard
    /// Set by the home-map "jump to state" menu — the state to zoom to.
    var focusStateName: Binding<String?> = .constant(nil)
    /// Advances on each "jump to state" pick; the map re-frames whenever it changes.
    var focusToken: Int = 0
    /// The single selected state, if any. Only this state is shaded; its runs are pinned.
    var selectedName: String? = nil
    /// Start points of the runs inside the selected state, pinned when a state is selected.
    var runPoints: [RunMapPoint] = []
    /// Tapping a run pin opens its detail through this binding.
    var selectedRunID: Binding<UUID?> = .constant(nil)
    /// Tapping a stack of co-located run pins surfaces them as a pick-list.
    var stackedRunIDs: Binding<[UUID]?> = .constant(nil)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        map.preferredConfiguration = mapStyle.configuration()
        map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
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
        context.coordinator.parent = self
        if context.coordinator.appliedStyle != mapStyle {
            context.coordinator.appliedStyle = mapStyle
            map.preferredConfiguration = mapStyle.configuration()
            map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
        }
        // Intensities and the selected state are set/changed after the map appears, so restyle
        // and force a redraw of any already-drawn renderers; not-yet-drawn ones pick up the
        // updated values from the coordinator when they're first rendered.
        context.coordinator.intensities = intensities
        context.coordinator.selectedName = selectedName
        for overlay in map.overlays {
            guard let renderer = map.renderer(for: overlay) as? MKPolygonRenderer,
                  let polygon = overlay as? MKPolygon else { continue }
            context.coordinator.style(renderer, for: polygon)
            renderer.setNeedsDisplay()
        }
        context.coordinator.refreshPins(on: map)

        // A jump-to-state request: when the focus token advances, frame that state's boundary.
        if focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            if let name = focusStateName.wrappedValue,
               let rect = USStateBoundaries.shared.boundingMapRect(for: name) {
                map.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 90, left: 40, bottom: 120, right: 40),
                    animated: true
                )
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: StatesMapView
        var intensities: [String: Double]
        var appliedStyle: MapStyleOption?
        var selectedName: String?
        var lastFocusToken = 0
        /// Overlay identity → boundary name (overlays are the shared boundary polygons).
        private var nameByOverlay: [ObjectIdentifier: String] = [:]
        /// run id → its pin annotation, for diffing the selected state's runs.
        private var pinsByID: [UUID: RunStartAnnotation] = [:]

        init(_ parent: StatesMapView) {
            self.parent = parent
            self.intensities = parent.intensities
            self.selectedName = parent.selectedName
        }

        func install(on map: MKMapView) {
            for boundary in USStateBoundaries.shared.boundaries {
                for polygon in boundary.polygons {
                    nameByOverlay[ObjectIdentifier(polygon)] = boundary.name
                    map.addOverlay(polygon, level: .aboveRoads)
                }
            }
        }

        /// Adds/removes run-start pins so exactly the selected state's runs are shown (none when
        /// no state is selected). Pins cluster into counts when zoomed out.
        func refreshPins(on map: MKMapView) {
            let desired = Dictionary(parent.runPoints.map { ($0.id, $0.coordinate) },
                                     uniquingKeysWith: { first, _ in first })
            for (id, pin) in pinsByID where desired[id] == nil {
                map.removeAnnotation(pin)
                pinsByID[id] = nil
            }
            var toAdd: [RunStartAnnotation] = []
            for (id, coordinate) in desired where pinsByID[id] == nil {
                let pin = RunStartAnnotation(runID: id, coordinate: coordinate)
                pinsByID[id] = pin
                toAdd.append(pin)
            }
            if !toAdd.isEmpty { map.addAnnotations(toAdd) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            style(renderer, for: polygon)
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // A stack of run pins collapses into a count bubble; tapping it zooms in.
            if let cluster = annotation as? MKClusterAnnotation {
                let id = "runCluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? CityClusterView)
                    ?? CityClusterView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.configure(count: cluster.memberAnnotations.count, total: max(parent.runPoints.count, 1))
                return view
            }

            guard annotation is RunStartAnnotation else { return nil }
            let id = "runPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RunPinView)
                ?? RunPinView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let members = cluster.memberAnnotations.compactMap { $0 as? RunStartAnnotation }
                var rect = MKMapRect.null
                for member in cluster.memberAnnotations {
                    let point = MKMapPoint(member.coordinate)
                    rect = rect.union(MKMapRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                }
                // Co-located runs can't be separated by zooming — list them; otherwise drill in.
                if members.count > 1, clusterSpanMeters(rect, at: cluster.coordinate.latitude) < 150 {
                    parent.stackedRunIDs.wrappedValue = members.map(\.runID)
                } else {
                    mapView.setVisibleMapRect(
                        rect,
                        edgePadding: UIEdgeInsets(top: 140, left: 80, bottom: 220, right: 80),
                        animated: true
                    )
                }
                mapView.deselectAnnotation(view.annotation, animated: false)
            } else if let pin = view.annotation as? RunStartAnnotation {
                parent.selectedRunID.wrappedValue = pin.runID
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }

        /// Largest side of a bounding map rect in meters — decides co-located (list) vs spread
        /// (zoom to separate).
        private func clusterSpanMeters(_ rect: MKMapRect, at latitude: CLLocationDegrees) -> Double {
            guard !rect.isNull else { return 0 }
            let metersPerPoint = 1 / MKMapPointsPerMeterAtLatitude(latitude)
            return max(rect.size.width, rect.size.height) * metersPerPoint
        }

        func style(_ renderer: MKPolygonRenderer, for polygon: MKPolygon) {
            let dark = (appliedStyle ?? .standard).isDarkBase
            let name = nameByOverlay[ObjectIdentifier(polygon)]

            // A state is selected: shade only it, and let every other state fall back to a faint
            // outline so the selection reads on its own.
            if let selectedName = selectedName {
                if let name, name == selectedName {
                    fillVisited(renderer, dark: dark, intensity: intensities[name] ?? 1)
                } else {
                    outlineOnly(renderer, dark: dark, faint: true)
                }
                return
            }

            // No selection: the full choropleth. Visited states fill graduated (deeper = more
            // runs); every state keeps a visible outline so the country reads even where nothing's
            // been run.
            if let name, let intensity = intensities[name] {
                fillVisited(renderer, dark: dark, intensity: intensity)
            } else {
                outlineOnly(renderer, dark: dark, faint: false)
            }
        }

        private func fillVisited(_ renderer: MKPolygonRenderer, dark: Bool, intensity: Double) {
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
        }

        private func outlineOnly(_ renderer: MKPolygonRenderer, dark: Bool, faint: Bool) {
            renderer.fillColor = .clear
            let base: UIColor = dark ? UIColor(Theme.Palette.bone) : .label
            renderer.strokeColor = base.withAlphaComponent(faint ? (dark ? 0.35 : 0.28) : (dark ? 0.6 : 0.5))
            renderer.lineWidth = faint ? (dark ? 1.0 : 0.8) : (dark ? 1.2 : 1.0)
        }
    }
}
