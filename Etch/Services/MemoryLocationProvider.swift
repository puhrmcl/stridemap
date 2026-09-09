import CoreLocation
import Combine

/// A foreground, one-shot lookup. Coordinates stay in memory and are matched on device.
@MainActor
final class MemoryLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var denied = false
    private let manager = CLLocationManager()
    private var generation = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        guard !isLoading else { return }
        generation += 1
        let token = generation
        location = nil; message = nil; isLoading = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: unavailable("Location access is off. You can enable it in Settings.", denied: true)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.generation == token, self.isLoading else { return }
            self.unavailable("Your location couldn’t be found. Try again when you have a clearer signal.")
        }
    }

    private func unavailable(_ text: String, denied: Bool = false) {
        isLoading = false; message = text; self.denied = denied
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.isLoading else { return }
            switch self.manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse: self.manager.requestLocation()
            case .denied, .restricted: self.unavailable("Location access is off. You can enable it in Settings.", denied: true)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.isLoading, let fix = locations.last else { return }
            guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 5_000,
                  abs(fix.timestamp.timeIntervalSinceNow) <= 300 else {
                self.unavailable("Your location isn’t accurate enough yet. Please try again.")
                return
            }
            self.location = fix; self.isLoading = false; self.denied = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.isLoading else { return }
            self.unavailable("Your location couldn’t be found. Please try again.")
        }
    }
}
