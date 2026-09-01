import Foundation
import CoreLocation

/// Decides whether two activities from different providers are the *same run*, so the
/// import service can merge them into one record instead of drawing duplicate routes.
///
/// The score combines start-time closeness, distance similarity, duration similarity, and
/// (when both have GPS) how near their start points are. Any single strong disagreement
/// (e.g. starts hours apart) collapses the score toward zero.
enum ActivityMatcher {

    /// Runs scoring at or above this are treated as the same activity.
    static let matchThreshold = 0.72

    /// 0 (definitely different) … 1 (definitely the same).
    static func confidence(_ a: Run, _ b: ImportedActivity) -> Double {
        let timeScore = timeScore(a.startDate, b.startDate)
        // Start time is the strongest signal — two runs rarely begin within minutes.
        guard timeScore > 0 else { return 0 }

        let distanceScore = ratioScore(a.distance, b.distance, tolerance: 0.08)
        let durationScore = ratioScore(Double(a.movingTime), Double(b.movingTime), tolerance: 0.12)
        let gpsScore = startProximityScore(a.startCoordinate, b.coordinates.first)

        // Weighted blend. GPS is a bonus signal when present; otherwise its weight is
        // redistributed to time/distance/duration.
        if let gpsScore {
            return timeScore * 0.45 + distanceScore * 0.25 + durationScore * 0.15 + gpsScore * 0.15
        } else {
            return timeScore * 0.5 + distanceScore * 0.3 + durationScore * 0.2
        }
    }

    static func isMatch(_ a: Run, _ b: ImportedActivity) -> Bool {
        confidence(a, b) >= matchThreshold
    }

    // MARK: Components

    /// Full credit within 90s, decaying to zero by ~20 minutes apart.
    private static func timeScore(_ a: Date, _ b: Date) -> Double {
        let seconds = abs(a.timeIntervalSince(b))
        if seconds <= 90 { return 1 }
        if seconds >= 1200 { return 0 }
        return 1 - (seconds - 90) / (1200 - 90)
    }

    /// 1 when values are within `tolerance` (fractional), decaying to 0 at 3× tolerance.
    private static func ratioScore(_ a: Double, _ b: Double, tolerance: Double) -> Double {
        guard a > 0, b > 0 else { return 0 }
        let diff = abs(a - b) / max(a, b)
        if diff <= tolerance { return 1 }
        let cutoff = tolerance * 3
        if diff >= cutoff { return 0 }
        return 1 - (diff - tolerance) / (cutoff - tolerance)
    }

    /// Full credit within 100m, zero beyond ~1km. Nil when either lacks a start point.
    private static func startProximityScore(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Double? {
        guard let a, let b else { return nil }
        let distance = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        if distance <= 100 { return 1 }
        if distance >= 1000 { return 0 }
        return 1 - (distance - 100) / (1000 - 100)
    }
}
