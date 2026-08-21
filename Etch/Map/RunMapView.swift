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

/// A plain reference holder for the map's live center. A class (not `@State` value) so the map
/// can update it on every pan without invalidating SwiftUI views; readers pull the latest on demand.
final class MapCenterBox {
    var coordinate: CLLocationCoordinate2D?
}

/// High-performance route map. Wraps `MKMapView` so thousands of polylines render
/// smoothly with per-route colour, age fading, and a recency glow — something SwiftUI's
/// `Map` struggles with at scale.
struct RunMapView: UIViewRepresentable {

    /// The currently visible (already filtered) runs.
    var runs: [Run]
    /// Runs that are milestones (personal records / superlatives) — their pins show the activity
    /// glyph on a gold ground.
    var milestoneRunIDs: Set<UUID> = []
    /// Selected run's activity id.
    @Binding var selectedRunID: UUID?
    /// When a tight cluster is tapped, the runs stacked there — to show a pick-list.
    @Binding var stackedRunIDs: [UUID]?
    /// A one-shot camera command; cleared after it's applied.
    @Binding var command: MapCameraCommand?
    /// Whether older routes should fade (the "web through time" look).
    var fadeWithAge: Bool = true
    /// The base map style (standard / satellite / hybrid).
    var mapStyle: MapStyleOption = .standard
    /// Per-run detail vs. the accumulative "etch" history view.
    var renderStyle: RouteRenderStyle = .routes
    /// When false, the tappable start pins are hidden and only the route lines are drawn.
    var showPins: Bool = true
    /// Tilts the camera into a 3D view when true, flat 2D when false.
    var is3D: Bool = false
    /// Receives the map's current center as it pans, so callers (e.g. the Look Around binoculars)
    /// can act on it without the churn of a `@State` update on every frame.
    var centerBox: MapCenterBox? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false

        map.preferredConfiguration = mapStyle.configuration()
        map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
        context.coordinator.appliedStyle = mapStyle

        // Tap a route line to open its run. The recognizer never cancels touches and only acts
        // when the tap lands on (or very near) a route, so it can't swallow taps meant for the
        // floating SwiftUI controls or the map's own gestures.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleRouteTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        map.addGestureRecognizer(tap)

        context.coordinator.map = map

        // A transparent overlay that carries the History heatmap image (hidden otherwise). It
        // sits above the map tiles but ignores touches so map gestures still work.
        let heat = UIImageView(frame: map.bounds)
        heat.isUserInteractionEnabled = false
        heat.contentMode = .scaleToFill
        heat.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        heat.isHidden = true
        map.addSubview(heat)
        context.coordinator.heatView = heat

        // Ask for location so the blue user dot can appear; harmless if declined.
        context.coordinator.requestLocationAuthorization()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Reapply the base configuration — and re-assert the tilt — when the style changes or 3D
        // toggles, so terrain/buildings actually rise (realistic elevation) rather than staying
        // flat. Doing both together means switching the base map while 3D is on keeps the tilt.
        if context.coordinator.appliedStyle != mapStyle || context.coordinator.appliedIs3D != is3D {
            context.coordinator.appliedStyle = mapStyle
            context.coordinator.appliedIs3D = is3D
            map.preferredConfiguration = mapStyle.configuration(elevated: is3D)
            map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
            // Imagery (Satellite/Hybrid) takes longer than a single runloop to switch to realistic
            // elevation; a tilt applied before it settles gets clamped back to flat — which is why
            // 3D used to work only on Standard. `applyTilt` retries, backing off, until the pitch
            // actually takes on whatever base map is active.
            context.coordinator.applyTilt(to: map, pitch: is3D ? 60 : 0)
        }

        // Switching between per-run and history rendering changes both geometry (history uses
        // simplified routes) and styling, so rebuild the overlay set from scratch on a change.
        let renderChanged = context.coordinator.appliedRenderStyle != renderStyle
        if renderChanged {
            context.coordinator.appliedRenderStyle = renderStyle
            context.coordinator.resetOverlays()
        }

        // Rebuild overlays/pins/clusters only when the run set (or its styling inputs) actually
        // changed. A search-sheet drag re-evaluates the parent body ~60×/s with an identical run
        // list; skipping the rebuild there keeps the map from re-diffing hundreds of routes each
        // frame. Selection is always applied (it's cheap and must track taps).
        var hasher = Hasher()
        hasher.combine(runs.count)
        for run in runs { hasher.combine(run.id) }
        hasher.combine(milestoneRunIDs.count)
        hasher.combine(fadeWithAge)
        let signature = hasher.finalize()
        if renderChanged || context.coordinator.lastRunsSignature != signature {
            context.coordinator.lastRunsSignature = signature
            context.coordinator.updateOverlays(with: runs, fadeWithAge: fadeWithAge)
            context.coordinator.rebuildClusters(force: false)
        }
        context.coordinator.updateSelection(selectedRunID)

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
        var appliedIs3D: Bool?
        /// Whether the map has framed the runs once on first appearance.
        var didInitialFrame = false
        /// A cheap signature of the last-rendered run set, so pure re-layouts (e.g. the search sheet
        /// dragging, which re-evaluates the parent's body every frame) skip the overlay/cluster
        /// rebuild when the runs haven't actually changed — keeping the map buttery during drags.
        var lastRunsSignature: Int?

        /// run id → overlay, so we can diff efficiently between updates.
        private var overlaysByID: [UUID: RunPolyline] = [:]

        /// Lightweight start points for the mapped runs, used to place tappable pins — with each
        /// run's pin kind (race / milestone / normal) so single-run pins can style themselves.
        private var runPoints: [(id: UUID, coordinate: CLLocationCoordinate2D, kind: RunPinKind, type: ActivityType)] = []
        /// run id → its start coordinate, for framing a cluster's members on drill-in.
        private var coordByID: [UUID: CLLocationCoordinate2D] = [:]
        /// Our own zoom-aware clusters. MapKit's automatic clustering silently drops annotations
        /// at low zoom (pins must be below `.required` to cluster, which lets MapKit *declutter*
        /// them), so with hundreds of runs many count bubbles vanish when zoomed out. We instead
        /// grid-cluster the runs ourselves and mark every bubble `.required` — so every run is
        /// always represented and the counts sum correctly at any zoom.
        private var clusterAnnotations: [RunClusterAnnotation] = []
        /// The map-point cell size the current clusters were built at; rebuild when zoom changes it.
        private var clusterCellSize: Double = 0

        /// History heatmap: the overlay image view and the decimated points feeding it.
        var heatView: UIImageView?
        private var heatPoints: [MKMapPoint] = []

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

            // History renders as a heatmap, not per-run polylines. Decimate each route into
            // points, drop the line overlays, and (re)draw the heat for the current viewport.
            if parent.renderStyle == .history {
                heatPoints = routed.flatMap { run in
                    Self.simplify(run.coordinates, maxPoints: 40).map { MKMapPoint($0) }
                }
                updateHeatmap()
                return
            }
            heatView?.isHidden = true

            // Snapshot start points for the tappable pins (only mapped runs get one), each with its
            // pin kind — milestone (a record/superlative) wins over race, then plain.
            runPoints = runs.compactMap { run -> (id: UUID, coordinate: CLLocationCoordinate2D, kind: RunPinKind, type: ActivityType)? in
                guard let coordinate = run.startCoordinate else { return nil }
                // A route-less run the user hand-placed (indoor/treadmill) reads as a treadmill pin.
                guard run.hasRoute else { return (run.id, coordinate, .indoor, run.activityType) }
                let isMilestone = parent.milestoneRunIDs.contains(run.id)
                let kind: RunPinKind = run.isRace && isMilestone ? .raceMilestone
                    : isMilestone ? .milestone
                    : run.isRace ? .race
                    : .normal
                return (run.id, coordinate, kind, run.activityType)
            }
            coordByID = Dictionary(runPoints.map { ($0.id, $0.coordinate) }, uniquingKeysWith: { first, _ in first })

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

            if overlay.isSelected {
                return RouteStyle(color: UIColor(Theme.accent), width: 6, alpha: 1)
            }
            // Every route renders in the signature blue at a consistent, clearly-visible
            // weight. (The old age-based fade turned most routes slate-grey and translucent,
            // which read as "greyed out" on the default map.)
            return RouteStyle(color: UIColor(Theme.Route.recent), width: 3, alpha: 0.85)
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

        /// Groups the run start points into screen-grid cells at the current zoom, one annotation
        /// per cell (a runner pin for a single run, a count bubble for several). Rebuilds when the
        /// zoom changes the cell size or the run set changes; panning doesn't churn (the grid is
        /// anchored in map space). History mode shows none.
        func rebuildClusters(force: Bool) {
            guard let map, parent.renderStyle == .routes, parent.showPins, !runPoints.isEmpty else {
                removeAllClusters()
                return
            }
            let width = Double(map.bounds.width)
            guard width > 0 else { return }
            // A cell ~68 screen points wide, expressed in map points so it's zoom-aware.
            let cell = max(1, (map.visibleMapRect.width / width) * 68)
            let cellChanged = clusterCellSize <= 0 || abs(cell - clusterCellSize) / max(clusterCellSize, 1) > 0.25
            let represented = clusterAnnotations.reduce(0) { $0 + $1.runIDs.count }
            guard force || cellChanged || represented != runPoints.count else { return }

            var buckets: [String: (ids: [UUID], sumX: Double, sumY: Double, kind: RunPinKind, type: ActivityType)] = [:]
            for point in runPoints {
                let mp = MKMapPoint(point.coordinate)
                let gx = Int(floor(mp.x / cell)), gy = Int(floor(mp.y / cell))
                let key = "\(gx),\(gy)"
                var bucket = buckets[key] ?? (ids: [], sumX: 0, sumY: 0, kind: .normal, type: .run)
                bucket.ids.append(point.id)
                bucket.sumX += mp.x
                bucket.sumY += mp.y
                // A single-run cell shows that run's kind + activity glyph; a cell with several is
                // a neutral count bubble (the type is unused there).
                bucket.kind = bucket.ids.count == 1 ? point.kind : .normal
                bucket.type = point.type
                buckets[key] = bucket
            }
            var newAnnotations: [RunClusterAnnotation] = []
            newAnnotations.reserveCapacity(buckets.count)
            for bucket in buckets.values {
                let n = Double(bucket.ids.count)
                let coordinate = MKMapPoint(x: bucket.sumX / n, y: bucket.sumY / n).coordinate
                newAnnotations.append(RunClusterAnnotation(runIDs: bucket.ids, coordinate: coordinate, kind: bucket.kind, activityType: bucket.type))
            }

            map.removeAnnotations(clusterAnnotations)
            clusterAnnotations = newAnnotations
            map.addAnnotations(newAnnotations)
            clusterCellSize = cell
        }

        private func removeAllClusters() {
            guard let map, !clusterAnnotations.isEmpty else { return }
            map.removeAnnotations(clusterAnnotations)
            clusterAnnotations.removeAll()
            clusterCellSize = 0
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let cluster = annotation as? RunClusterAnnotation else { return nil }

            // Several runs in one grid cell → a count bubble; a single run → a runner pin. Both
            // are `.required` and carry no clusteringIdentifier, so MapKit never re-clusters or
            // hides them — our grid already resolved the density.
            if cluster.runIDs.count > 1 {
                let id = "runCluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? CityClusterView)
                    ?? CityClusterView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.configure(count: cluster.runIDs.count, total: max(runPoints.count, 1))
                view.displayPriority = .required
                return view
            }

            let id = "runPin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? RunPinView)
                ?? RunPinView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.configure(cluster.kind, activityType: cluster.activityType)
            view.clusteringIdentifier = nil
            view.displayPriority = .required
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let cluster = view.annotation as? RunClusterAnnotation else { return }
            mapView.deselectAnnotation(view.annotation, animated: false)

            // A single run: open its detail and frame its path above the (half-height) sheet.
            if cluster.runIDs.count == 1 {
                let runID = cluster.runIDs[0]
                parent.selectedRunID = runID
                if let overlay = overlaysByID[runID] {
                    let bottomInset = max(mapView.bounds.height * 0.55, 220)
                    mapView.setVisibleMapRect(
                        overlay.boundingMapRect,
                        edgePadding: UIEdgeInsets(top: 120, left: 50, bottom: bottomInset, right: 50),
                        animated: true
                    )
                }
                return
            }

            // A count bubble: zoom to its members' extent, or list them if they're co-located.
            var rect = MKMapRect.null
            for id in cluster.runIDs {
                guard let coordinate = coordByID[id] else { continue }
                let point = MKMapPoint(coordinate)
                rect = rect.union(MKMapRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
            }
            if clusterSpanMeters(rect, at: cluster.coordinate.latitude) < 150 {
                parent.stackedRunIDs = cluster.runIDs
            } else if !rect.isNull {
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 140, left: 80, bottom: 220, right: 80),
                    animated: true
                )
            }
        }

        // MARK: Route tapping

        /// Opens the run whose route line is closest to the tap, if any is within a small radius.
        @objc func handleRouteTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map, parent.renderStyle == .routes else { return }
            let tapPoint = gesture.location(in: map)

            // If the tap landed on a pin / cluster bubble, let MapKit's selection handle it.
            var view: UIView? = map.hitTest(tapPoint, with: nil)
            while let current = view {
                if current is MKAnnotationView { return }
                view = current.superview
            }

            let threshold: CGFloat = 22
            var best: (id: UUID, distance: CGFloat)?
            for (id, overlay) in overlaysByID {
                let count = overlay.pointCount
                guard count > 1 else { continue }
                let points = overlay.points()
                let step = max(1, count / 160)   // sample to keep the tap cheap
                var i = 0
                while i < count {
                    let screen = map.convert(points[i].coordinate, toPointTo: map)
                    let distance = hypot(screen.x - tapPoint.x, screen.y - tapPoint.y)
                    if distance <= threshold, best == nil || distance < best!.distance {
                        best = (id, distance)
                    }
                    i += step
                }
            }

            guard let best else { return }
            parent.selectedRunID = best.id
            if let overlay = overlaysByID[best.id] {
                let bottomInset = max(map.bounds.height * 0.55, 220)
                map.setVisibleMapRect(
                    overlay.boundingMapRect,
                    edgePadding: UIEdgeInsets(top: 120, left: 50, bottom: bottomInset, right: 50),
                    animated: true
                )
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Largest side of a bounding map rect converted to meters — used to decide whether a
        /// cluster's members are co-located (list them) or spread out (zoom to separate).
        func clusterSpanMeters(_ rect: MKMapRect, at latitude: CLLocationDegrees) -> Double {
            guard !rect.isNull else { return 0 }
            let metersPerPoint = 1 / MKMapPointsPerMeterAtLatitude(latitude)
            return max(rect.size.width, rect.size.height) * metersPerPoint
        }

        // MARK: Heatmap (History mode)

        /// Redraw the heatmap whenever the viewport changes so the glow stays registered to
        /// the map as the user pans and zooms.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.centerBox?.coordinate = mapView.centerCoordinate
            if parent.renderStyle == .history { updateHeatmap() }
            else { rebuildClusters(force: false) }
        }

        /// Renders the History heat image for the current viewport (or hides it outside
        /// History / when there's nothing to show).
        func updateHeatmap() {
            guard let map, let heatView else { return }
            guard parent.renderStyle == .history, !heatPoints.isEmpty else {
                heatView.isHidden = true
                heatView.image = nil
                return
            }
            heatView.frame = map.bounds
            let image = Heatmap.image(points: heatPoints, visible: map.visibleMapRect, size: map.bounds.size)
            heatView.image = image
            heatView.isHidden = (image == nil)
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

        /// Tilts the camera to `pitch` (0 = flat 2D, 60 = 3D), retrying with a short back-off until
        /// it takes. Satellite/Hybrid imagery only accept a tilt once their realistic-elevation
        /// configuration has settled, which lags a base-map/3D change by a variable amount; a single
        /// set lands too early on those styles and gets clamped flat (the reason 3D used to work only
        /// on Standard). Each attempt bails if the requested state is already satisfied or the user
        /// has since toggled 3D again, so the retries self-terminate.
        func applyTilt(to map: MKMapView, pitch: CGFloat, attempt: Int = 0) {
            let delays: [Double] = [0.05, 0.35, 0.7, 1.1]
            guard attempt < delays.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self, weak map] in
                guard let self, let map, self.parent.is3D == (pitch > 0) else { return }
                // Already where we want it? (tilted when asking for 3D, flat when asking for 2D.)
                let satisfied = pitch > 0 ? map.camera.pitch >= 5 : map.camera.pitch < 5
                if satisfied { return }
                let camera = MKMapCamera(
                    lookingAtCenter: map.camera.centerCoordinate,
                    fromDistance: max(map.camera.centerCoordinateDistance, 300),
                    pitch: pitch,
                    heading: map.camera.heading
                )
                // Animate the first attempt for a smooth tilt; snap on retries so the check below
                // reads the settled pitch rather than a mid-animation value.
                map.setCamera(camera, animated: attempt == 0)
                self.applyTilt(to: map, pitch: pitch, attempt: attempt + 1)
            }
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
/// it can open that run's detail sheet. Used by the States map (MapKit-clustered).
final class RunStartAnnotation: NSObject, MKAnnotation {
    let runID: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(runID: UUID, coordinate: CLLocationCoordinate2D) {
        self.runID = runID
        self.coordinate = coordinate
    }
}

/// How a single-run map pin reads: a plain runner, a blue checkered flag for a race, the activity
/// glyph on gold for a milestone (a record / superlative), or — when a run is both — a gold
/// checkered flag that keeps the race identity while marking it a record.
enum RunPinKind {
    case normal, race, milestone, raceMilestone, indoor
}

/// A home-map cluster: the runs grouped into one screen-grid cell. Carries the member run ids so
/// a tap can drill in (zoom to their extent) or list them. One run → shown as a runner pin, styled
/// by its `kind` (race / milestone). Multi-run cells are neutral count bubbles.
final class RunClusterAnnotation: NSObject, MKAnnotation {
    let runIDs: [UUID]
    let kind: RunPinKind
    /// The run's activity type — drives the pin glyph for a plain (`.normal`) single-run pin so a
    /// ride reads as a bike, a hike as a hiker, etc. Unused for count bubbles and styled kinds.
    let activityType: ActivityType
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(runIDs: [UUID], coordinate: CLLocationCoordinate2D, kind: RunPinKind = .normal, activityType: ActivityType = .run) {
        self.runIDs = runIDs
        self.kind = kind
        self.activityType = activityType
        self.coordinate = coordinate
    }
}

/// A circular accent pin with a white runner glyph. Participates in clustering so stacks of
/// runs starting at the same place collapse into a count bubble until zoomed in.
final class RunPinView: MKAnnotationView {
    private let glyph = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let diameter: CGFloat = 30
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.cornerRadius = diameter / 2
        layer.borderColor = UIColor(Theme.Palette.bone).withAlphaComponent(0.9).cgColor
        layer.borderWidth = 1.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)

        glyph.frame = bounds
        glyph.contentMode = .center
        addSubview(glyph)

        canShowCallout = false
        clusteringIdentifier = "runPin"
        // Clustering only kicks in when the priority is below `.required` — the default. Leaving
        // it `.required` keeps every pin on screen, so close runs pile up as overlapping glyphs
        // instead of collapsing into a single numbered count bubble you can tap to drill into.
        displayPriority = .defaultHigh
        configure(.normal)
    }

    /// Styles the pin by run kind: a race reads as a blue checkered flag so it stands out, a
    /// milestone as the activity glyph on gold; a run that's both keeps the checkered flag but on
    /// gold. A plain run shows its activity glyph — a runner, cyclist, hiker, or walker per
    /// `activityType`.
    func configure(_ kind: RunPinKind, activityType: ActivityType = .run) {
        let symbol: String
        let background: UIColor
        switch kind {
        case .race:
            symbol = "flag.checkered"
            background = UIColor(Theme.accent)          // Etch Blue — races stand out
        case .milestone:
            // A record still shows the activity's own glyph (runner / cyclist / hiker / walker),
            // just on gold — so the pin says *what* the activity is, and its gold ground marks it a
            // record, rather than a generic trophy.
            symbol = activityType.detailIcon
            background = UIColor(Theme.Palette.brass)   // gold
        case .raceMilestone:
            symbol = "flag.checkered"                   // still a race…
            background = UIColor(Theme.Palette.brass)   // …but gold, because it's also a record
        case .indoor:
            symbol = IndoorGlyph.symbol                 // treadmill — a hand-placed route-less run
            background = UIColor(Theme.Palette.ink).withAlphaComponent(0.9)
        case .normal:
            symbol = activityType.detailIcon            // runner / cyclist / hiker / walker
            background = UIColor(Theme.Palette.ink).withAlphaComponent(0.95)
        }
        let compact = kind == .race || kind == .raceMilestone || kind == .indoor
        backgroundColor = background
        glyph.tintColor = .white
        glyph.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: compact ? 13 : 15, weight: .bold)
        )
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
