import SwiftUI
import MapKit
import CoreLocation

/// How the route overlays are rendered.
enum RouteRenderStyle: Equatable {
    /// Per-run routes: recency colour, age fade, tappable. The default detail view.
    case routes
    /// "Etch" density view: every run drawn thin, low-opacity, in one colour so overlapping
    /// routes accumulate into a heat-like whole. For seeing all tracked history zoomed out.
    case history
}

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
    /// The base map style (standard / satellite / hybrid).
    var mapStyle: MapStyleOption = .standard
    /// Per-run detail vs. the accumulative "etch" history view.
    var renderStyle: RouteRenderStyle = .routes

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        map.preferredConfiguration = mapStyle.configuration()
        context.coordinator.appliedStyle = mapStyle

        // NOTE: the route-tap gesture is temporarily disabled to isolate a button
        // responsiveness issue — it was the prime suspect for swallowing control taps. If
        // the floating buttons work reliably without it, route selection will be
        // reimplemented in a way that can't interfere with the SwiftUI controls.

        context.coordinator.map = map
        // Ask for location so the blue user dot can appear; harmless if declined.
        context.coordinator.requestLocationAuthorization()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.appliedStyle != mapStyle {
            context.coordinator.appliedStyle = mapStyle
            map.preferredConfiguration = mapStyle.configuration()
        }

        // Switching between per-run and history rendering changes both geometry (history uses
        // simplified routes) and styling, so rebuild the overlay set from scratch on a change.
        let renderChanged = context.coordinator.appliedRenderStyle != renderStyle
        if renderChanged {
            context.coordinator.appliedRenderStyle = renderStyle
            context.coordinator.resetOverlays()
        }

        context.coordinator.updateOverlays(with: runs, fadeWithAge: fadeWithAge)
        context.coordinator.updateSelection(selectedRunID)
        context.coordinator.refreshRunPins()

        // On entering history, frame everything so the whole footprint is in view. Otherwise,
        // the first time we have runs to show, frame the map to them so it opens centered on
        // the user's runs rather than the default world view. Both only fire on a transition /
        // once, so the user's own panning and zooming is never fought afterwards.
        if renderChanged && renderStyle == .history {
            context.coordinator.didInitialFrame = true
            context.coordinator.frameAll(runs: runs)
        } else if !context.coordinator.didInitialFrame, runs.contains(where: { $0.hasRoute }) {
            context.coordinator.didInitialFrame = true
            context.coordinator.frameAll(runs: runs)
        }

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
        var appliedStyle: MapStyleOption?
        var appliedRenderStyle: RouteRenderStyle?
        /// Whether the map has framed the runs once on first appearance.
        var didInitialFrame = false

        /// run id → overlay, so we can diff efficiently between updates.
        private var overlaysByID: [UUID: RunPolyline] = [:]

        /// Lightweight start points for the mapped runs, used to place tappable pins.
        private var runPoints: [(id: UUID, coordinate: CLLocationCoordinate2D)] = []
        /// run id → its pin annotation.
        private var pinsByID: [UUID: RunStartAnnotation] = [:]

        private let locationManager = CLLocationManager()

        init(_ parent: RunMapView) { self.parent = parent }

        func requestLocationAuthorization() {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }

        // MARK: Overlay diffing

        /// Drops all route overlays so the next `updateOverlays` rebuilds them — used when the
        /// render style flips, since geometry and styling both differ between modes.
        func resetOverlays() {
            guard let map else { return }
            map.removeOverlays(Array(overlaysByID.values))
            overlaysByID.removeAll()
        }

        func updateOverlays(with runs: [Run], fadeWithAge: Bool) {
            guard let map else { return }
            let routed = runs.filter { $0.hasRoute }

            // Snapshot start points for the tappable pins (only mapped runs get one).
            runPoints = routed.compactMap { run in run.startCoordinate.map { (run.id, $0) } }

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
                var coords = run.coordinates
                guard coords.count > 1 else { continue }
                // History draws every run at once; thin them so hundreds of routes stay light
                // to render. Detail is unnecessary here — the value is the aggregate shape.
                if parent.renderStyle == .history {
                    coords = Self.simplify(coords, maxPoints: 80)
                }
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
            // History: one colour, thin, low alpha. Every route is identical, so where they
            // overlap the translucent strokes composite darker — turning frequently-run roads
            // into a denser "etch" without a real heatmap pass. Selection/age don't apply.
            if parent.renderStyle == .history {
                return RouteStyle(color: UIColor(Theme.Route.recent), width: 1.6, alpha: 0.30)
            }

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

        /// Simplifies a route to at most `maxPoints` by evenly striding, always keeping the
        /// first and last points. Cheap and shape-preserving enough for the zoomed-out etch.
        static func simplify(_ coords: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
            guard coords.count > maxPoints, maxPoints > 2 else { return coords }
            let step = Double(coords.count - 1) / Double(maxPoints - 1)
            var result: [CLLocationCoordinate2D] = []
            result.reserveCapacity(maxPoints)
            for i in 0..<maxPoints {
                result.append(coords[Int((Double(i) * step).rounded())])
            }
            return result
        }

        // MARK: Run pins

        /// Places one runner pin per mapped run and lets MapKit cluster them: zoomed out they
        /// collapse into count bubbles, and tapping drills in until single runs are tappable.
        /// All pins are added (not viewport-culled) so cluster counts are accurate. History
        /// mode shows none.
        func refreshRunPins() {
            guard let map else { return }
            guard parent.renderStyle == .routes else {
                removeAllRunPins()
                return
            }

            let desired = Dictionary(runPoints.map { ($0.id, $0.coordinate) },
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

        private func removeAllRunPins() {
            guard let map, !pinsByID.isEmpty else { return }
            map.removeAnnotations(Array(pinsByID.values))
            pinsByID.removeAll()
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            // Several pins on top of each other collapse into a count bubble; tapping it
            // zooms in to separate them.
            if let cluster = annotation as? MKClusterAnnotation {
                let id = "runCluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? CityClusterView)
                    ?? CityClusterView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.configure(count: cluster.memberAnnotations.count, total: max(runPoints.count, 1))
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
                var rect = MKMapRect.null
                for member in cluster.memberAnnotations {
                    let point = MKMapPoint(member.coordinate)
                    rect = rect.union(MKMapRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
                }
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 140, left: 80, bottom: 220, right: 80),
                    animated: true
                )
                mapView.deselectAnnotation(view.annotation, animated: false)
            } else if let pin = view.annotation as? RunStartAnnotation {
                // Open the run's detail sheet AND zoom to that run's full path, framing it into
                // the map area above the (roughly half-height) detail sheet.
                parent.selectedRunID = pin.runID
                if let overlay = overlaysByID[pin.runID] {
                    let bottomInset = max(mapView.bounds.height * 0.55, 220)
                    mapView.setVisibleMapRect(
                        overlay.boundingMapRect,
                        edgePadding: UIEdgeInsets(top: 120, left: 50, bottom: bottomInset, right: 50),
                        animated: true
                    )
                }
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
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

        /// Frames the full set of runs — used when entering the history view so the entire
        /// footprint of tracked history lands in view at once.
        func frameAll(runs: [Run]) {
            fit(runs: runs, animated: true)
        }

        private func fit(runs: [Run], padding: CGFloat = 60, animated: Bool = true) {
            guard let map, !runs.isEmpty else { return }
            var rect = MKMapRect.null
            // Only runs with a route have a real bounding box; route-less runs default to
            // (0,0) — a point off Africa — which would otherwise blow the fit out to the whole
            // globe. Skip them so the camera frames just the actual tracks.
            for run in runs where run.hasRoute {
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

        /// The floating controls sit in bands at the top (totals + filters) and bottom
        /// (toolbar, locate/layers). The map fills the whole screen underneath them, so its
        /// route-tap recognizer would otherwise swallow touches meant for those buttons —
        /// which is why they didn't even highlight. Ignore touches in those bands; route
        /// taps happen on the map body in between.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let map else { return true }
            let y = touch.location(in: map).y
            let height = map.bounds.height
            let topBandHeight: CGFloat = 200
            let bottomBandHeight: CGFloat = 220
            if y < topBandHeight || y > height - bottomBandHeight {
                return false
            }
            return true
        }
    }
}

/// A tappable pin marking a mapped run's start point; carries the run identity so tapping
/// it can open that run's detail sheet.
final class RunStartAnnotation: NSObject, MKAnnotation {
    let runID: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(runID: UUID, coordinate: CLLocationCoordinate2D) {
        self.runID = runID
        self.coordinate = coordinate
    }
}

/// A circular accent pin with a white runner glyph. Participates in clustering so stacks of
/// runs starting at the same place collapse into a count bubble until zoomed in.
final class RunPinView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let diameter: CGFloat = 30
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.cornerRadius = diameter / 2
        backgroundColor = UIColor(Theme.accent).withAlphaComponent(0.95)
        layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.borderWidth = 1.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        let glyph = UIImageView(frame: bounds)
        glyph.tintColor = .white
        glyph.contentMode = .center
        glyph.image = UIImage(
            systemName: "figure.run",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        )
        addSubview(glyph)

        canShowCallout = false
        clusteringIdentifier = "runPin"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
