import MapKit
import UIKit

/// The base map style the route map renders on. Persisted in `AppStorage`.
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case night
    case terrain
    case satellite
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:  return "Standard"
        case .night:     return "Night"
        case .terrain:   return "Terrain"
        case .satellite: return "Satellite"
        case .hybrid:    return "Hybrid"
        }
    }

    var symbol: String {
        switch self {
        case .standard:  return "map"
        case .night:     return "moon.stars.fill"
        case .terrain:   return "mountain.2.fill"
        case .satellite: return "globe.americas"
        case .hybrid:    return "globe.americas.fill"
        }
    }

    /// True when the base map is dark imagery (or the forced-dark Night style), so overlays need
    /// light (rather than dark) ink to stay legible.
    var isDarkBase: Bool {
        switch self {
        case .standard, .terrain: return false
        case .night, .satellite, .hybrid: return true
        }
    }

    /// Forces the map's appearance for styles that should look the same in light and dark mode.
    /// Night is always dark (a consistent archival canvas); the rest follow the system.
    var forcedInterfaceStyle: UIUserInterfaceStyle {
        self == .night ? .dark : .unspecified
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
        case .night:
            // Full (default) emphasis, forced dark: a high-contrast dark map that reads clearly
            // apart from the washed-out muted Standard — even when the system is already dark.
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            config.pointOfInterestFilter = .excludingAll
            return config
        case .terrain:
            // Natural (default) emphasis + realistic elevation, so terrain colouring and
            // hillshaded relief actually show — distinct from the desaturated Standard. Relief
            // reads best tilted into 3D or over hilly ground.
            let config = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
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
