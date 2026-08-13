import Foundation

/// A normalized weather condition, distilled from whatever a source recorded (HealthKit's
/// `HKWeatherCondition`, or nothing when only a temperature is known). Kept small and
/// brand-appropriate — a handful of legible states, not a meteorological taxonomy.
enum WeatherCondition: String {
    case clear, partlyCloudy, cloudy, fog, hazy, wind, rain, drizzle, snow, sleet, thunderstorm

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .hazy: return "Hazy"
        case .wind: return "Windy"
        case .rain: return "Rain"
        case .drizzle: return "Drizzle"
        case .snow: return "Snow"
        case .sleet: return "Sleet"
        case .thunderstorm: return "Storms"
        }
    }

    var symbol: String {
        switch self {
        case .clear: return "sun.max"
        case .partlyCloudy: return "cloud.sun"
        case .cloudy: return "cloud"
        case .fog: return "cloud.fog"
        case .hazy: return "sun.haze"
        case .wind: return "wind"
        case .rain: return "cloud.rain"
        case .drizzle: return "cloud.drizzle"
        case .snow: return "cloud.snow"
        case .sleet: return "cloud.sleet"
        case .thunderstorm: return "cloud.bolt.rain"
        }
    }

    /// Maps Apple Health's `HKWeatherCondition` raw value to a normalized condition.
    static func fromHealthKit(_ raw: Int) -> WeatherCondition? {
        switch raw {
        case 1, 2: return .clear                 // clear, fair
        case 3: return .partlyCloudy
        case 4, 5: return .cloudy                // mostlyCloudy, cloudy
        case 6: return .fog
        case 7, 10, 11: return .hazy             // haze, smoky, dust
        case 8, 9: return .wind                  // windy, blustery
        case 12, 30, 31, 32, 33: return .snow    // snow, flurries, showers, heavy, blizzard
        case 13, 14, 15, 16, 17, 18, 19, 20: return .sleet
        case 21: return .drizzle
        case 22, 23: return .rain                // scatteredShowers, showers
        case 24, 25, 26, 27, 28, 29: return .thunderstorm
        default: return nil                      // none / unknown
        }
    }
}

/// Formats a run's recorded weather for display, honouring the user's unit system for
/// temperature (Fahrenheit alongside miles, Celsius alongside kilometres).
enum WeatherFormat {

    static func temperature(celsius: Double, unit: UnitSystem = .current) -> String {
        if unit == .miles {
            return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
        return "\(Int(celsius.rounded()))°C"
    }

    /// A single metadata line, e.g. "58°F · Clear". Nil when nothing is recorded.
    static func line(temperatureC: Double?, condition: WeatherCondition?, unit: UnitSystem = .current) -> String? {
        var parts: [String] = []
        if let temperatureC { parts.append(temperature(celsius: temperatureC, unit: unit)) }
        if let condition { parts.append(condition.label) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
