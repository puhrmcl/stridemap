import SwiftUI
import MapKit

/// A run's identity paired with its start coordinate — used for the States attribution.
struct RunMapPoint: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
}

/// A map of the cities you've run in: one labelled marker per city, showing the city name and
/// its run count. Nearby cities cluster into a total when zoomed out; tapping a city lists its
/// runs, tapping a cluster zooms in.
struct CitiesMapView: UIViewRepresentable {

    /// One entry per city (name, coordinate, runs) — from `RunStatistics.travelPlaces`.
    var cities: [RunStatistics.TravelPlace]
    /// Selecting a single run opens its detail sheet via this binding.
    @Binding var selectedRunID: UUID?
    /// Tapping a city surfaces its runs as a pick-list through this binding.
    @Binding var stackedRunIDs: [UUID]?
    /// Set by the home-map "jump to city" menu; zooms to that coordinate, then clears.
    var focusCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil)
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
        map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
        context.coordinator.appliedStyle = mapStyle
        // Tonal wash so geography recedes; the Etch chips (annotations) stay above it.
        map.addOverlay(MapWash.makeOverlay(), level: .aboveLabels)
        context.coordinator.rebuild(on: map, cities: cities)
        context.coordinator.frame(map, cities: cities)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.appliedStyle != mapStyle {
            context.coordinator.appliedStyle = mapStyle
            map.preferredConfiguration = mapStyle.configuration()
            map.overrideUserInterfaceStyle = mapStyle.forcedInterfaceStyle
        }
        if context.coordinator.installedCount != cities.count {
            context.coordinator.rebuild(on: map, cities: cities)
            context.coordinator.frame(map, cities: cities)
        }

        // A jump-to-city request: zoom to that city, then clear the binding so the same city
        // can be picked again later.
        if let coordinate = focusCoordinate.wrappedValue {
            map.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
                ),
                animated: true
            )
            DispatchQueue.main.async { focusCoordinate.wrappedValue = nil }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CitiesMapView
        var appliedStyle: MapStyleOption?
        private(set) var installedCount = -1

        init(_ parent: CitiesMapView) { self.parent = parent }

        func rebuild(on map: MKMapView, cities: [RunStatistics.TravelPlace]) {
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            let annotations = cities.map {
                CityAnnotation(coordinate: $0.coordinate, name: $0.label, runIDs: $0.runs.map(\.id))
            }
            map.addAnnotations(annotations)
            installedCount = cities.count
        }

        func frame(_ map: MKMapView, cities: [RunStatistics.TravelPlace]) {
            guard !cities.isEmpty else { return }
            var rect = MKMapRect.null
            for city in cities {
                let point = MKMapPoint(city.coordinate)
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

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            return MapWash.renderer(for: polygon)   // the only polygon here is the wash
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            func chip() -> EtchMarkerView {
                (mapView.dequeueReusableAnnotationView(withIdentifier: EtchMarkerView.reuseID) as? EtchMarkerView)
                    ?? EtchMarkerView(annotation: annotation, reuseIdentifier: EtchMarkerView.reuseID)
            }

            if let cluster = annotation as? MKClusterAnnotation {
                // A cluster of cities shows the total runs across them (no name).
                let total = cluster.memberAnnotations
                    .compactMap { $0 as? CityAnnotation }
                    .reduce(0) { $0 + $1.count }
                let view = chip()
                view.annotation = annotation
                view.configure(count: total, name: nil)
                return view
            }

            guard let city = annotation as? CityAnnotation else { return nil }
            let view = chip()
            view.annotation = annotation
            view.configure(count: city.count, name: city.name)
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
            } else if let city = view.annotation as? CityAnnotation {
                // Surface that city's runs as a pick-list.
                parent.stackedRunIDs = city.runIDs
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }
    }
}

/// One city on the Cities map: its name, location, and the runs that started there.
final class CityAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let name: String
    let runIDs: [UUID]
    var count: Int { runIDs.count }
    var title: String? { name }

    init(coordinate: CLLocationCoordinate2D, name: String, runIDs: [UUID]) {
        self.coordinate = coordinate
        self.name = name
        self.runIDs = runIDs
    }
}

/// A clustered bubble sized by how many runs it contains, labelled with that count. Used by
/// the Home route map.
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
        let t = total > 1 ? min(1, (Double(count).squareRoot() / Double(total).squareRoot())) : 1
        let diameter = 30 + 34 * CGFloat(t)
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        layer.cornerRadius = diameter / 2
        backgroundColor = UIColor(Theme.Palette.ink).withAlphaComponent(0.92)
        layer.borderColor = UIColor(Theme.Palette.bone).withAlphaComponent(0.9).cgColor
        layer.borderWidth = 2
        label.frame = bounds
        label.font = .systemFont(ofSize: diameter > 44 ? 15 : 13, weight: .bold)
        label.text = count.formatted()
    }
}
