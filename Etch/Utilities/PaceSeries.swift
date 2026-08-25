import Foundation
import CoreLocation

/// Builds a compact pace profile from timestamped track points — the data behind the poster's
/// pace band, the running sibling of the recorded elevation profile.
///
/// The series is seconds-per-kilometre, resampled to `sampleCount` uniform-*distance* samples
/// (uniform distance, not time, so the band lines up under the route the way elevation does).
/// GPS jitter is tamed by measuring each sample over a centred window of at least `minWindow`
/// metres, and absurd values (a tunnel dropout, a paused watch) clamp into a sane band.
enum PaceSeries {

    static let sampleCount = 120
    /// Minimum window (metres) a sample's pace is measured over.
    static let minWindow: Double = 50
    /// Clamp: 1:40/km (world-record-ish) … 30:00/km (a slow walk with stops).
    static let minSecPerKm: Double = 100
    static let maxSecPerKm: Double = 1800

    /// Pace series from aligned coordinates and timestamps. Empty when the data can't support
    /// an honest profile (too few points, missing times, or no distance covered).
    static func compute(coordinates: [CLLocationCoordinate2D], times: [Date]) -> [Double] {
        let n = min(coordinates.count, times.count)
        guard n > 4 else { return [] }

        // Cumulative distance and elapsed time per point.
        var distance: [Double] = [0]
        distance.reserveCapacity(n)
        for i in 1..<n {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            distance.append(distance[i - 1] + b.distance(from: a))
        }
        let total = distance[n - 1]
        guard total > minWindow * 2 else { return [] }
        let t0 = times[0]
        let elapsed: [Double] = (0..<n).map { times[$0].timeIntervalSince(t0) }
        guard let last = elapsed.last, last > 0 else { return [] }

        // For each uniform-distance sample, pace over a centred window (≥ minWindow metres).
        let window = max(minWindow, total / Double(sampleCount))
        var series: [Double] = []
        series.reserveCapacity(sampleCount)
        var cursor = 0
        for s in 0..<sampleCount {
            let center = total * (Double(s) + 0.5) / Double(sampleCount)
            let lo = max(0, center - window / 2)
            let hi = min(total, center + window / 2)
            // Advance a shared cursor (distances are monotonic) then bracket the window.
            while cursor + 1 < n && distance[cursor + 1] < lo { cursor += 1 }
            var j = cursor
            while j + 1 < n && distance[j + 1] < hi { j += 1 }
            let d = distance[j] - distance[cursor]
            let t = elapsed[j] - elapsed[cursor]
            if d > 1, t > 0 {
                series.append(min(maxSecPerKm, max(minSecPerKm, t / d * 1000)))
            } else {
                series.append(series.last ?? 0)
            }
        }
        // Backfill any leading zeros from the first honest sample.
        if let firstReal = series.first(where: { $0 > 0 }) {
            for i in series.indices where series[i] == 0 { series[i] = firstReal }
        } else {
            return []
        }
        return series
    }
}
