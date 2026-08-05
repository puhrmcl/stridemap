import Foundation

/// Where a run originated. Covers the platforms that write running workouts into Apple
/// Health, plus a few direct integrations we may add later. This is deliberately open —
/// `unknown` and `other(_:)` keep us honest when a new app appears.
enum ActivitySource: Equatable, Hashable {
    case healthKit          // Recorded by Apple Watch / Apple Fitness ("Apple Workout")
    case nikeRunClub
    case strava
    case garmin
    case coros
    case polar
    case wahoo
    case adidasRunning
    case runna
    case suunto
    case unknown
    /// An unrecognised HealthKit source app, carrying its reported name.
    case other(String)

    /// Human label shown (subtly) on the run detail screen.
    var label: String {
        switch self {
        case .healthKit: return "Apple Workout"
        case .nikeRunClub: return "Nike Run Club"
        case .strava: return "Strava"
        case .garmin: return "Garmin"
        case .coros: return "COROS"
        case .polar: return "Polar"
        case .wahoo: return "Wahoo"
        case .adidasRunning: return "adidas Running"
        case .runna: return "Runna"
        case .suunto: return "Suunto"
        case .unknown: return "Unknown"
        case .other(let name): return name
        }
    }

    var symbol: String {
        switch self {
        case .healthKit: return "applewatch"
        case .strava: return "figure.run"
        case .nikeRunClub, .adidasRunning, .runna: return "figure.run.circle"
        case .garmin, .coros, .polar, .wahoo, .suunto: return "dot.radiowaves.left.and.right"
        case .unknown, .other: return "questionmark.circle"
        }
    }

    /// Stable string used to persist the source on the model.
    var rawValue: String {
        switch self {
        case .other(let name): return "other:\(name)"
        default: return String(describing: self)
        }
    }

    init(rawValue: String) {
        switch rawValue {
        case "healthKit": self = .healthKit
        case "nikeRunClub": self = .nikeRunClub
        case "strava": self = .strava
        case "garmin": self = .garmin
        case "coros": self = .coros
        case "polar": self = .polar
        case "wahoo": self = .wahoo
        case "adidasRunning": self = .adidasRunning
        case "runna": self = .runna
        case "suunto": self = .suunto
        case "unknown": self = .unknown
        default:
            if rawValue.hasPrefix("other:") {
                self = .other(String(rawValue.dropFirst("other:".count)))
            } else {
                self = .unknown
            }
        }
    }

    /// Maps a HealthKit source/product name (e.g. "Nike Run Club", "Garmin Connect")
    /// to a known ecosystem. Matching is fuzzy because vendors label themselves
    /// inconsistently across bundle name, product type, and source name.
    static func detect(fromSourceName name: String?) -> ActivitySource {
        guard let raw = name?.lowercased(), !raw.isEmpty else { return .unknown }
        if raw.contains("nike") { return .nikeRunClub }
        if raw.contains("strava") { return .strava }
        if raw.contains("garmin") { return .garmin }
        if raw.contains("coros") { return .coros }
        if raw.contains("polar") { return .polar }
        if raw.contains("wahoo") { return .wahoo }
        if raw.contains("adidas") || raw.contains("runtastic") { return .adidasRunning }
        if raw.contains("runna") { return .runna }
        if raw.contains("suunto") { return .suunto }
        // Apple's own recorders.
        if raw.contains("apple") || raw.contains("watch") || raw.contains("fitness") || raw.contains("workout") {
            return .healthKit
        }
        return .other(name ?? "Unknown")
    }
}
