import Foundation
import MapKit

/// Finds the notable place a run started at or next to — a park, university, museum, and the
/// like — so the Landmarks overlay shows real points of interest rather than arbitrary spots.
///
/// Uses MapKit's points-of-interest search around the run's start, filtered to "destination"
/// categories. Distinguishes a genuine "no landmark nearby" (empty result) from a failed
/// request (throws), so the caller can mark the former checked and back off on the latter.
enum LandmarkFinder {

    /// POI categories that count as a landmark. Recreation, culture, and education — the kinds
    /// of place worth naming a run after. (Historic-site / monument / castle categories are
    /// iOS 18-only and can be added once the build targets that SDK.)
    static let categories: [MKPointOfInterestCategory] = [
        .nationalPark, .park, .beach, .campground, .marina,
        .university, .school, .library, .museum, .theater,
        .stadium, .amusementPark, .aquarium, .zoo, .winery, .brewery
    ]

    /// The nearest landmark POI within `radius` metres of `coordinate`, or nil if there is
    /// none. Throws if the search itself fails (network / throttling) so the caller can retry.
    static func nearest(to coordinate: CLLocationCoordinate2D,
                        radius: CLLocationDistance = 400) async throws -> String? {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)

        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return response.mapItems
            .compactMap { item -> (name: String, distance: CLLocationDistance)? in
                guard let location = item.placemark.location,
                      let name = item.name, !name.isEmpty else { return nil }
                return (name, location.distance(from: origin))
            }
            .filter { $0.distance <= radius }
            .min { $0.distance < $1.distance }?
            .name
    }
}
