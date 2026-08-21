import Foundation

/// A single data "complication" that can occupy a stat slot on an Etch Studio poster. The user
/// retunes each slot from a curated set — like choosing an Apple Watch complication. Metrics know
/// only how to label and format themselves from a run; unavailable ones (no heart rate, etc.)
/// report nil so the editor can grey them out.
enum StatMetric: String, CaseIterable, Identifiable {
    /// A deliberately empty slot — renders as blank space on the poster. Selectable for any data
    /// point (headline or slot) so the user can leave gaps in the composition.
    case none
    case distance, time, pace, speed, elevationGain, startElevation, avgHeartRate, calories, cadence, place, date, weather

    var id: String { rawValue }

    /// Wide-tracked uppercase label shown beneath the value.
    var label: String {
        switch self {
        case .none:         return ""
        case .distance:     return "DISTANCE"
        case .time:         return "TIME"
        case .pace:         return "PACE"
        case .speed:        return "AVG SPEED"
        case .elevationGain: return "ELEV GAIN"
        case .startElevation: return "START ELEV"
        case .avgHeartRate: return "AVG HR"
        case .calories:     return "CALORIES"
        case .cadence:      return "CADENCE"
        case .place:        return "PLACE"
        case .date:         return "DATE"
        case .weather:      return "WEATHER"
        }
    }

    /// An SF Symbol paired with the metric on editorial layouts, the way keepsake prints pin an
    /// icon to each data point.
    var icon: String {
        switch self {
        case .none:          return "minus"
        case .distance:      return "point.topleft.down.to.point.bottomright.curvepath"
        case .time:          return "stopwatch"
        case .pace:          return "speedometer"
        case .speed:         return "gauge.with.dots.needle.67percent"
        case .elevationGain: return "arrow.up.forward"
        case .startElevation: return "mountain.2"
        case .avgHeartRate:  return "heart.fill"
        case .calories:      return "flame.fill"
        case .cadence:       return "metronome"
        case .place:         return "mappin.and.ellipse"
        case .date:          return "calendar"
        case .weather:       return "cloud.sun.fill"
        }
    }

    /// A short name for the picker menu.
    var menuName: String {
        switch self {
        case .none:           return "None"
        case .speed:          return "Avg speed"
        case .elevationGain:  return "Elevation gain"
        case .startElevation: return "Start elevation"
        case .avgHeartRate:   return "Avg heart rate"
        default:              return label.capitalized
        }
    }

    /// The default hero metric and stat slots for a poster, tuned to the activity type — rides lead
    /// with speed, hikes with elevation, both dropping the running-only pace. Distance stays the hero.
    static func defaults(for type: ActivityType) -> (hero: StatMetric, slots: [StatMetric]) {
        switch type {
        case .ride: return (.distance, [.time, .speed, .elevationGain])
        case .hike: return (.distance, [.time, .elevationGain, .startElevation])
        default:    return (.distance, [.time, .pace, .elevationGain])   // runs & walks
        }
    }

    /// Start elevation is derived from the fetched terrain profile, not the run itself.
    var needsElevationProfile: Bool { self == .startElevation }

    /// The formatted value for a run, or nil when the run has no data for this metric.
    func value(for run: Run) -> String? {
        switch self {
        case .none:
            return nil
        case .distance:
            return Format.distance(run.distance)
        case .time:
            return Format.duration(run.movingTime)
        case .pace:
            return Format.pace(secondsPerKm: run.paceSecondsPerKm)
        case .speed:
            guard run.movingTime > 0, run.distance > 0 else { return nil }
            let hours = Double(run.movingTime) / 3600
            let value = Format.distanceValue(run.distance) / hours
            return "\(value.formatted(.number.precision(.fractionLength(1)))) \(UnitSystem.current.speedSuffix)"
        case .elevationGain:
            return Format.elevationGain(run.elevationGain)
        case .startElevation:
            return nil   // resolved from the terrain profile by the composition
        case .avgHeartRate:
            guard let hr = run.averageHeartRate, hr > 0 else { return nil }
            return "\(Int(hr.rounded())) BPM"
        case .calories:
            guard let kcal = run.activeEnergy, kcal > 0 else { return nil }
            return "\(Int(kcal.rounded())) CAL"
        case .cadence:
            guard let spm = run.averageCadence, spm > 0 else { return nil }
            return "\(Int(spm.rounded())) SPM"
        case .place:
            let place = [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return place.isEmpty ? nil : place
        case .date:
            return Format.date(run.startDate)
        case .weather:
            return run.weatherLine()
        }
    }

    func isAvailable(for run: Run) -> Bool {
        // The blank slot is always selectable.
        if self == .none { return true }
        // Start elevation comes from a terrain lookup along the route, so it's available whenever
        // the run has a route.
        if self == .startElevation { return run.coordinates.count > 1 }
        return value(for: run) != nil
    }
}
