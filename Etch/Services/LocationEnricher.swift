import Foundation
import CoreLocation

/// Reverse-geocodes run start points into city / state / country. HealthKit doesn't
/// provide place names, so this fills them in for runs that arrive without location
/// metadata — keeping the Travel map and city filters useful even without Strava.
///
/// `CLGeocoder` is rate-limited, so the import service calls this for a bounded number of
/// runs per sync; missing locations are filled gradually across syncs.
actor LocationEnricher {

    private let geocoder = CLGeocoder()

    struct Place {
        var city: String?
        var state: String?
        var country: String?
    }

    func place(for coordinate: CLLocationCoordinate2D) async -> Place? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        return Place(
            city: placemark.locality ?? placemark.subAdministrativeArea,
            state: placemark.administrativeArea,
            country: placemark.country
        )
    }
}
