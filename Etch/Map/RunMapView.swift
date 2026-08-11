import SwiftUI
import MapKit
import CoreLocation

/// High-performance route map. Wraps `MKMapView` so thousands of polylines render
/// smoothly with per-route colour, age fading, and a recency glow — something SwiftUI's
/// `Map` struggles with at scale.
struct RunMapView: UIViewRepresentable {

    /// The currently visible (already filtered) runs.
    var runs: [Run]
    /// Selected run's activity id.
    @Binding var selectedRunID: UUID?
    /// A one-shot camera command; cleared after it's applied.
    @Binding var command: MapCameraCommand?
    /// Whether older routes should fade (the "web through time" look).
    var fadeWithAge: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        let config = MKStandardMapConfiguration(elevationStyle: .flat)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        // Never swallow touches meant for the floating SwiftUI controls.
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)

        context.coordinator.map = map
        // Ask for location so the blue user dot can appear; harmless if declined.
        context.coordinator.requestLocationAuthorization()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateOverlays(with: runs, fadeWithAge: fadeWithAge)
        context.coordinator.updateSelection(selectedRunID)

        if let command, command.id != context.coordinator.lastCommandID {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command, runs: runs)
            // Clear on the next runloop tick to avoid mutating state during update.
            DispatchQueue.main.async { self.command = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: RunMapView
        weak var map: MKMapView?
        var lastCommandID: UUID?

        /// run id → overlay, so we can diff efficiently between updates.
        private var overlaysByID: [UUID: RunPolyline] = [:]

        private let locationManager = CLLocationManager()

        init(_ parent: RunMapView) { self.parent = parent }

        func requestLocationAuthorization() {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }

        // MARK: Overlay diffing

        func updateOverlays(with runs: [Run], fadeWithAge: Bool) {
            guard let map else { return }
            let routed = runs.filter { $0.hasRoute }
            let newIDs = Set(routed.map { $0.id })
            let oldIDs = Set(overlaysByID.keys)

            // Remove overlays no longer visible.
            for id in oldIDs.subtracting(newIDs) {
                if let overlay = overlaysByID[id] {
                    map.removeOverlay(overlay)
                    overlaysByID[id] = nil
                }
            }

            guard !routed.isEmpty else { return }

            // Age normalisation across the currently visible set.
            let ages = routed.map { $0.ageInDays }
            let maxAge = max(ages.max() ?? 1, 1)

            var toAdd: [RunPolyline] = []
            for run in routed {
                let fraction = fadeWithAge ? Double(run.ageInDays) / Double(maxAge) : 0
                if let existing = overlaysByID[run.id] {
                    // Refresh styling if the age fraction shifted meaningfully.
                    if abs(existing.ageFraction - fraction) > 0.001 {
                        existing.ageFraction = fraction
                        if let renderer = map.renderer(for: existing) as? MKPolylineRenderer {
                            renderer.apply(style(for: existing))
                        }
                    }
                    continue
                }
                let coords = run.coordinates
                guard coords.count > 1 else { continue }
                let polyline = RunPolyline(coordinates: coords, count: coords.count)
                polyline.runID = run.id
                polyline.ageFraction = fraction
                polyline.emphasised = run.isRace
                overlaysByID[run.id] = polyline
                toAdd.append(polyline)
            }
            if !toAdd.isEmpty { map.addOverlays(toAdd, level: .aboveRoads) }
        }

        func updateSelection(_ selectedID: UUID?) {
            for (id, overlay) in overlaysByID {
                let shouldSelect = id == selectedID
                if overlay.isSelected != shouldSelect {
                    overlay.isSelected = shouldSelect
                    if let renderer = map?.renderer(for: overlay) as? MKPolylineRenderer {
                        renderer.apply(style(for: overlay))
                    }
                }
            }
        }

        // MARK: Rendering

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let run = overlay as? RunPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: run)
            renderer.apply(style(for: run))
            return renderer
        }

        private func style(for overlay: RunPolyline) -> RouteStyle {
            let base = Theme.Route.color(forAgeFraction: overlay.ageFraction)
            if overlay.isSelected {
                return RouteStyle(color: UIColor(Theme.accent), width: 6, alpha: 1)
            }
            // Recent runs glow (wider, brighter); older runs recede.
            let recency = 1 - overlay.ageFraction
            let width = 2.4 + recency * 2.2
            let alpha = 0.35 + recency * 0.55
            return RouteStyle(color: UIColor(base), width: width, alpha: alpha)
        }

        // MARK: Camera

        func apply(_ command: MapCameraCommand, runs: [Run]) {
            guard let map else { return }
            switch command.target {
            case .fit(let ids):
                let subset = runs.filter { ids.contains($0.id) }
                fit(runs: subset.isEmpty ? runs : subset)
            case .focus(let id):
                if let run = runs.first(where: { $0.id == id }) {
                    fit(runs: [run], padding: 80, animated: true)
                }
            case .region(let lat, let lon, let span):
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                )
                map.setRegion(region, animated: true)
            case .userLocation:
                let coordinate = map.userLocation.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate),
                      !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return }
                let region = MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
                map.setRegion(region, animated: true)
            }
        }

        private func fit(runs: [Run], padding: CGFloat = 60, animated: Bool = true) {
            guard let map, !runs.isEmpty else { return }
            var rect = MKMapRect.null
            for run in runs {
                let box = MKMapRect(
                    minLat: run.minLatitude, maxLat: run.maxLatitude,
                    minLon: run.minLongitude, maxLon: run.maxLongitude
                )
                rect = rect.union(box)
            }
            guard !rect.isNull else { return }
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: padding + 60, left: padding, bottom: padding + 120, right: padding),
                animated: animated
            )
        }

        // MARK: Tap hit-testing

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            let tapMapPoint = MKMapPoint(coordinate)
            // Tolerance scales with zoom so taps stay forgiving when zoomed out.
            let tolerance = 12 * map.visibleMapRect.width / Double(map.bounds.width)

            var best: (id: UUID, distance: Double)?
            for (id, overlay) in overlaysByID {
                let distance = overlay.distance(to: tapMapPoint)
                if distance < tolerance, best == nil || distance < best!.distance {
                    best = (id, distance)
                }
            }
            if let best {
                parent.selectedRunID = best.id
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        /// Only treat taps that land on the map surface as route taps. Without this, the
        /// tap recognizer swallows touches on the floating SwiftUI controls (finding no
        /// route under them), so those buttons need several taps before they respond.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let map, let touchView = touch.view else { return true }
            return touchView.isDescendant(of: map)
        }
    }
}

/// Styling values applied to a polyline renderer.
private struct RouteStyle {
    var color: UIColor
    var width: CGFloat
    var alpha: CGFloat
}

private extension MKPolylineRenderer {
    func apply(_ style: RouteStyle) {
        strokeColor = style.color.withAlphaComponent(style.alpha)
        lineWidth = style.width
        lineCap = .round
        lineJoin = .round
    }
}

private extension MKMapRect {
    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        self = MKMapRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(topLeft.x - bottomRight.x),
            height: abs(topLeft.y - bottomRight.y)
        )
    }
}

private extension MKPolyline {
    /// Approximate distance (in map points) from a point to this polyline.
    func distance(to point: MKMapPoint) -> Double {
        let count = pointCount
        guard count > 1 else { return .greatestFiniteMagnitude }
        let points = self.points()
        var minDistance = Double.greatestFiniteMagnitude
        for i in 0..<(count - 1) {
            let d = point.distanceToSegment(points[i], points[i + 1])
            minDistance = min(minDistance, d)
        }
        return minDistance
    }
}

private extension MKMapPoint {
    func distanceToSegment(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        if dx == 0 && dy == 0 { return hypot(x - a.x, y - a.y) }
        let t = ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)
        let clamped = max(0, min(1, t))
        let projX = a.x + clamped * dx
        let projY = a.y + clamped * dy
        return hypot(x - projX, y - projY)
    }
}
