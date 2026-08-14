import MapKit

/// The base map style the route map renders on. Persisted in `AppStorage`.
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }

    var symbol: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas"
        case .hybrid: return "globe.americas.fill"
        }
    }

    /// True when the base map is dark imagery, so overlays need light (rather than dark) ink to
    /// stay legible.
    var isDarkBase: Bool {
        switch self {
        case .standard: return false
        case .satellite, .hybrid: return true
        }
    }

    /// A fresh MapKit configuration for this style. Points of interest are excluded so the
    /// map stays calm and the routes are the focus.
    func configuration() -> MKMapConfiguration {
        switch self {
        case .standard:
            // Muted emphasis desaturates the base map so geography recedes and the Etch route /
            // markers are the only high-contrast thing on screen — archival, not navigational.
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            return config
        case .satellite:
            return MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid:
            let config = MKHybridMapConfiguration(elevationStyle: .flat)
            config.pointOfInterestFilter = .excludingAll
            return config
        }
    }
}
