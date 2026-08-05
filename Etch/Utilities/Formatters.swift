import Foundation

enum UnitSystem: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }
    var label: String { self == .miles ? "Miles" : "Kilometers" }
    var distanceSuffix: String { self == .miles ? "mi" : "km" }
    var paceSuffix: String { self == .miles ? "/mi" : "/km" }

    static var current: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: "unitSystem") ?? "") ?? .miles
    }
}

/// Formatting helpers shared across the app. All accept metres/seconds and honour the
/// user's chosen unit system.
enum Format {

    static func distance(_ meters: Double, unit: UnitSystem = .current, decimals: Int = 1) -> String {
        let value = unit == .miles ? meters / 1609.344 : meters / 1000
        return "\(value.formatted(.number.precision(.fractionLength(decimals)))) \(unit.distanceSuffix)"
    }

    static func distanceValue(_ meters: Double, unit: UnitSystem = .current) -> Double {
        unit == .miles ? meters / 1609.344 : meters / 1000
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Pace given a run's seconds-per-km, converted to the chosen unit.
    static func pace(secondsPerKm: Double, unit: UnitSystem = .current) -> String {
        guard secondsPerKm > 0 else { return "—" }
        let perUnit = unit == .miles ? secondsPerKm * 1.609344 : secondsPerKm
        let m = Int(perUnit) / 60
        let s = Int(perUnit) % 60
        return String(format: "%d:%02d %@", m, s, unit.paceSuffix)
    }

    static func elevation(_ meters: Double, unit: UnitSystem = .current) -> String {
        if unit == .miles {
            return "\(Int(meters * 3.28084)) ft"
        }
        return "\(Int(meters)) m"
    }

    private static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h:mm a"
        return f
    }()

    static func date(_ date: Date) -> String { mediumDate.string(from: date) }
    static func dateTime(_ date: Date) -> String { dayTime.string(from: date) }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }
}
