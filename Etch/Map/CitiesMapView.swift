import SwiftUI
import MapKit

/// A proportional-symbol map of *where* you run. Every run's start point is dropped as a
/// dot and MapKit clusters nearby ones into a single bubble labelled with the run count —
/// so zoomed out you see one bubble per city/metro, and zooming in splits them into
/// neighbourhoods. Coordinate-only (no geocoding), so it fills in as soon as runs have GPS.
struct CitiesMapView: UIViewRepresentable {

    /// Start coordinates of every run to place (already filtered to those with GPS).
    var coordinates: [CLLocationCoordinate2D]
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
        context.coordinator.rebuild(on: map, coordinates: coordinates)
        context.coordinator.frame(map, coordinates: coordinates)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.appliedStyle != mapStyle {
            context.coordinator.appliedStyle = mapStyle
            map.preferredConfiguration = mapStyle.configuration()
        }
        if context.coordinator.installedCount != coordinates.count {
            context.coordinator.rebuild(on: map, coordinates: coordinates)
            context.coordinator.frame(map, coordinates: coordinates)
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

        func rebuild(on map: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            let annotations = coordinates.map(RunPointAnnotation.init)
            map.addAnnotations(annotations)
            installedCount = coordinates.count
            totalCount = max(coordinates.count, 1)
        }

        func frame(_ map: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            guard !coordinates.isEmpty else { return }
            var rect = MKMapRect.null
            for coordinate in coordinates {
                let point = MKMapPoint(coordinate)
                // Pad each point a little so single-run cities aren't framed to a pinprick.
                rect = rect.union(MKMapRect(x: point.x - 20_000, y: point.y - 20_000,
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

            let id = "runPoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            configureDot(view)
            return view
        }

        /// A single run's start point: a small accent dot that participates in clustering.
        private func configureDot(_ view: MKAnnotationView) {
            let size: CGFloat = 11
            view.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            view.backgroundColor = UIColor(Theme.accent).withAlphaComponent(0.9)
            view.layer.cornerRadius = size / 2
            view.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
            view.layer.borderWidth = 1
            view.clusteringIdentifier = "run"
            view.collisionMode = .circle
            view.canShowCallout = false
        }
    }
}

/// One run's start location. Kept as a distinct type so cluster vs. single is trivial to tell.
final class RunPointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// A clustered bubble sized by how many runs it contains, labelled with that count.
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
