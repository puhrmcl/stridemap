import Foundation

/// Compact storage for a run's recorded altitude profile — the per-point elevation stream the
/// source actually recorded (GPX `<ele>`, TCX `AltitudeMeters`, FIT altitude, HealthKit route
/// altitude, …). We downsample to at most `maxSamples` points and store metres as a
/// comma-separated string: plenty for a faithful profile, without bloating the store or widening
/// the SwiftData migration surface with a new array-of-Double property.
enum ElevationSeries {

    /// Enough points for a smooth profile at any display width, far smaller than a raw track
    /// (which can be thousands of points).
    static let maxSamples = 256

    /// Downsamples (evenly, keeping the first and last) and encodes to "m0,m1,…" with one decimal.
    static func encode(_ values: [Double]) -> String {
        let sampled = downsample(values, to: maxSamples)
        guard sampled.count > 1 else { return "" }
        return sampled.map { String(format: "%.1f", $0) }.joined(separator: ",")
    }

    static func decode(_ raw: String) -> [Double] {
        guard !raw.isEmpty else { return [] }
        return raw.split(separator: ",").compactMap { Double($0) }
    }

    /// Evenly reduces a series to at most `count` points, always keeping the first and last.
    static func downsample(_ values: [Double], to count: Int) -> [Double] {
        guard values.count > count, count > 1 else { return values }
        var out: [Double] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let idx = Int((Double(i) / Double(count - 1)) * Double(values.count - 1))
            out.append(values[idx])
        }
        return out
    }
}
