import SwiftUI
import MapKit

/// A run's identity paired with its start coordinate — the input to the cluster maps.
struct RunMapPoint: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
}

/// A proportional-symbol map of *where* you run. Every run's start point is dropped and
/// MapKit clusters nearby ones into a bubble labelled with the run count — one bubble per
/// city/metro zoomed out, splitting into neighbourhoods as you zoom in. Tap a bubble to
/// drill in; tap a single runner pin to open that run's detail. Coordinate-only, so it
/// populates as soon as runs have GPS.
struct CitiesMapView: UIViewRepresentable {

    /// Every run to place (already filtered to those with GPS).
    var points: [RunMapPoint]
    /// Selecting a single run opens its detail sheet via this binding.
    @Binding var selectedRunID: UUID?
    /// Base map style (standard / satellite / hybrid), shared with the other maps.
    var mapStyle: MapStyleOption = .standard

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.preferredConfiguration = mapStyle.configuration()
        context.coordinator.appliedStyle = mapStyle
        context.coordinator.rebuild(on: map, points: points)
        context.coordinator.frame(map, points: points)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.appliedStyle != mapStyle {
            context.coordinator.appliedStyle = mapStyle
            map.preferredConfiguration = mapStyle.configuration()
        }
        if context.coordinator.installedCount != points.count {
            context.coordinator.rebuild(on: map, points: points)
            context.coordinator.frame(map, points: points)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CitiesMapView
        var appliedStyle: MapStyleOption?
        private(set) var installedCount = -1
        /// Stable reference for sizing cluster bubbles (a cluster can't exceed the total).
        private var totalCount = 1

        init(_ parent: CitiesMapView) { self.parent = parent }

        func rebuild(on map: MKMapView, points: [RunMapPoint]) {
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            let annotations = points.map { RunStartAnnotation(runID: $0.id, coordinate: $0.coordinate) }
            map.addAnnotations(annotations)
            installedCount = points.count
            totalCount = max(points.count, 1)
        }

        func frame(_ map: MKMapView, points: [RunMapPoint]) {
            guard !points.isEmpty else { return }
            var rect = MKMapRect.null
            for point in points {
                let mapPoint = MKMapPoint(point.coordinate)
                // Pad each point a little so single-run cities aren't framed to a pinprick.
                rect = rect.union(MKMapRect(x: mapPoint.x - 20_000, y: mapPoint.y - 20_000,
                                            width: 40_000, height: 40_000))
            }
            guard !rect.isNull else { return }
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 120, left: 48, bottom: 160, right: 48),
                animated: false
            )
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let id = "cityCluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? CityClusterView)
                    ?? CityClusterView(annotation: annotation, reuseIdentifier: id)
                view.annotation = annotation
                view.configure(count: cluster.memberAnnotations.count, total: totalCount)
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
                // Drill in: frame the cluster's members so they separate.
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
                parent.selectedRunID = pin.runID
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }
    }
}

/// A clustered bubble sized by how many runs it contains, labelled with that count. Shared
/// by both the Cities map and the Home route map.
final class CityClusterView: MKAnnotationView {
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        addSubview(label)
        canShowCallout = false
        collisionMode = .circle
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(count: Int, total: Int) {
        // Area-proportional feel via a sqrt scale, clamped so bubbles stay tappable but never
        // swallow the map. `total` keeps sizing stable regardless of zoom-dependent grouping.
        let t = total > 1 ? min(1, (Double(count).squareRoot() / Double(total).squareRoot())) : 1
        let diameter = 30 + 34 * CGFloat(t)
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.cornerRadius = diameter / 2
        backgroundColor = UIColor(Theme.accent).withAlphaComponent(0.9)
        layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        layer.borderWidth = 2
        label.frame = bounds
        label.font = .systemFont(ofSize: diameter > 44 ? 15 : 13, weight: .bold)
        label.text = count.formatted()
    }
}
