import Foundation

/// A single data "complication" that can occupy a stat slot on an Etch Studio poster. The user
/// retunes each slot from a curated set — like choosing an Apple Watch complication. Metrics know
/// only how to label and format themselves from a run; unavailable ones (no heart rate, etc.)
/// report nil so the editor can grey them out.
enum StatMetric: String, CaseIterable, Identifiable {
    case distance, time, pace, elevationGain, avgHeartRate, calories, cadence, place, date, weather

    var id: String { rawValue }

    /// Wide-tracked uppercase label shown beneath the value.
    var label: String {
        switch self {
        case .distance:     return "DISTANCE"
        case .time:         return "TIME"
        case .pace:         return "PACE"
        case .elevationGain: return "ELEV GAIN"
        case .avgHeartRate: return "AVG HR"
        case .calories:     return "CALORIES"
        case .cadence:      return "CADENCE"
        case .place:        return "PLACE"
        case .date:         return "DATE"
        case .weather:      return "WEATHER"
        }
    }

    /// A short name for the picker menu.
    var menuName: String {
        switch self {
        case .elevationGain: return "Elevation gain"
        case .avgHeartRate:  return "Avg heart rate"
        default:             return label.capitalized
        }
    }

    /// The formatted value for a run, or nil when the run has no data for this metric.
    func value(for run: Run) -> String? {
        switch self {
        case .distance:
            return Format.distance(run.distance)
        case .time:
            return Format.duration(run.movingTime)
        case .pace:
            return Format.pace(secondsPerKm: run.paceSecondsPerKm)
        case .elevationGain:
            return Format.elevationGain(run.elevationGain)
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

    func isAvailable(for run: Run) -> Bool { value(for: run) != nil }
}
