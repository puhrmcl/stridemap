import Foundation
import CoreLocation

/// A grid of real terrain elevations (metres) sampled across a rectangular geographic area.
/// Row 0 is the northern edge; column 0 the western edge. Used to trace topographic contour
/// lines behind a run.
struct ElevationField {
    let rows: Int
    let cols: Int
    /// Row-major, `rows * cols` metres. Sea/void samples are stored as 0.
    let values: [Double]
    let minElevation: Double
    let maxElevation: Double

    func value(row: Int, col: Int) -> Double { values[row * cols + col] }
}

/// Fetches an `ElevationField` from Open-Meteo's free, keyless elevation API and caches it on
/// disk per area, so opening a Topographic edition again is instant. Returns nil on any network
/// failure so the caller can fall back gracefully.
enum ElevationService {

    private struct Response: Decodable { let elevation: [Double?] }

    /// Samples a `rows × cols` grid over the bounding box and returns the field. Cached by a key
    /// derived from the (rounded) box and grid size.
    static func field(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double,
                      rows: Int, cols: Int) async -> ElevationField? {
        let key = cacheKey(latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax, rows: rows, cols: cols)
        if let cached = readCache(key) { return cached }

        // Grid coordinates, row-major (north→south, west→east).
        var coords: [(lat: Double, lon: Double)] = []
        coords.reserveCapacity(rows * cols)
        for r in 0..<rows {
            let lat = latMax - (latMax - latMin) * Double(r) / Double(rows - 1)
            for c in 0..<cols {
                let lon = lonMin + (lonMax - lonMin) * Double(c) / Double(cols - 1)
                coords.append((lat, lon))
            }
        }

        // Open-Meteo accepts up to 100 coordinates per request. Fetch batches in small
        // concurrent waves (not all at once) so a burst doesn't trip the API's rate limit and
        // null the whole grid; any failed batch after retry fails the field (caller falls back).
        let batchSize = 100
        var batches: [(start: Int, coords: [(lat: Double, lon: Double)])] = []
        var i = 0
        while i < coords.count {
            let end = min(i + batchSize, coords.count)
            batches.append((i, Array(coords[i..<end])))
            i = end
        }

        var values = [Double](repeating: 0, count: coords.count)
        // Three at a time, not five: sixteen batches in bursts of five was tripping the API's
        // rate limit on weak connections, and one nulled batch blanks the whole contour panel —
        // which is how the Contour style rendered as bare paper on device.
        let maxConcurrent = 3
        var waveStart = 0
        while waveStart < batches.count {
            let wave = Array(batches[waveStart..<min(waveStart + maxConcurrent, batches.count)])
            let waveResults = await withTaskGroup(of: (Int, [Double]?).self) { group in
                for batch in wave {
                    let start = batch.start
                    let slice = batch.coords
                    group.addTask { (start, await fetchBatch(slice)) }
                }
                var collected: [(Int, [Double]?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (start, elevations) in waveResults {
                guard let elevations else { return nil }
                for (offset, value) in elevations.enumerated() { values[start + offset] = value }
            }
            waveStart += maxConcurrent
        }

        let minE = values.min() ?? 0
        let maxE = values.max() ?? 0
        let field = ElevationField(rows: rows, cols: cols, values: values, minElevation: minE, maxElevation: maxE)
        writeCache(key, field)
        return field
    }

    /// Samples up to `sampleCount` points evenly along the route and returns their terrain
    /// elevations (metres) in order — a route elevation profile for the poster's silhouette
    /// strip. One request (≤100 points), cached per route. nil on failure.
    static func routeProfile(for coordinates: [CLLocationCoordinate2D],
                             sampleCount: Int = 100) async -> [Double]? {
        guard coordinates.count > 1 else { return nil }

        // Sample evenly by *distance* along the route so the profile's x-axis is true distance —
        // which lets the poster place accurate mile markers.
        let n = coordinates.count
        let count = min(sampleCount, n)
        var cumulative = [Double](repeating: 0, count: n)
        for i in 1..<n {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            cumulative[i] = cumulative[i - 1] + a.distance(from: b)
        }
        let total = cumulative[n - 1]

        var sampled: [(lat: Double, lon: Double)] = []
        sampled.reserveCapacity(count)
        var searchIdx = 0
        for i in 0..<count {
            let target = total > 0 ? Double(i) / Double(count - 1) * total : 0
            while searchIdx < n - 1 && cumulative[searchIdx] < target { searchIdx += 1 }
            let c = coordinates[min(searchIdx, n - 1)]
            sampled.append((c.latitude, c.longitude))
        }

        let key = routeCacheKey(sampled, sampleCount: sampleCount)
        if let cached = readProfileCache(key) { return cached }

        guard let profile = await fetchBatch(sampled) else { return nil }
        writeProfileCache(key, profile)
        return profile
    }

    /// Terrain elevations (metres) for an arbitrary set of points, batched in waves. Used for the
    /// state print's high/low elevation. Best-effort: nil if any batch fails.
    static func elevations(for coordinates: [CLLocationCoordinate2D]) async -> [Double]? {
        guard !coordinates.isEmpty else { return [] }
        let capped = coordinates.count > 400 ? Array(coordinates.prefix(400)) : coordinates
        let coords = capped.map { (lat: $0.latitude, lon: $0.longitude) }

        var batches: [(start: Int, coords: [(lat: Double, lon: Double)])] = []
        var i = 0
        while i < coords.count {
            let end = min(i + 100, coords.count)
            batches.append((i, Array(coords[i..<end])))
            i = end
        }

        var values = [Double](repeating: 0, count: coords.count)
        var waveStart = 0
        while waveStart < batches.count {
            let wave = Array(batches[waveStart..<min(waveStart + 5, batches.count)])
            let waveResults = await withTaskGroup(of: (Int, [Double]?).self) { group in
                for batch in wave {
                    let start = batch.start
                    let slice = batch.coords
                    group.addTask { (start, await fetchBatch(slice)) }
                }
                var collected: [(Int, [Double]?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            for (start, elevations) in waveResults {
                guard let elevations else { return nil }
                for (offset, value) in elevations.enumerated() { values[start + offset] = value }
            }
            waveStart += 5
        }
        return values
    }

    private static func routeCacheKey(_ coords: [(lat: Double, lon: Double)], sampleCount: Int) -> String {
        func r(_ v: Double) -> String { String(format: "%.3f", v) }
        let first = coords.first!, last = coords.last!
        let mid = coords[coords.count / 2]
        return "route_\(coords.count)_\(sampleCount)_\(r(first.lat))_\(r(first.lon))_\(r(mid.lat))_\(r(mid.lon))_\(r(last.lat))_\(r(last.lon))"
    }

    private static func readProfileCache(_ key: String) -> [Double]? {
        let url = cacheDirectory.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Double].self, from: data) else { return nil }
        return values
    }

    private static func writeProfileCache(_ key: String, _ values: [Double]) {
        let url = cacheDirectory.appendingPathComponent(key + ".json")
        if let data = try? JSONEncoder().encode(values) { try? data.write(to: url) }
    }

    /// One request of ≤100 coordinates, retried with a growing pause — a contour field is
    /// sixteen of these and a single dead batch blanks the whole panel, so each one gets a
    /// real chance to ride out a rate-limit blip or a weak-signal timeout before giving up.
    private static func fetchBatch(_ coords: [(lat: Double, lon: Double)]) async -> [Double]? {
        let lats = coords.map { String(format: "%.5f", $0.lat) }.joined(separator: ",")
        let lons = coords.map { String(format: "%.5f", $0.lon) }.joined(separator: ",")
        var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: lats),
            URLQueryItem(name: "longitude", value: lons)
        ]
        guard let url = components?.url else { return nil }

        let pauses: [UInt64] = [400_000_000, 1_200_000_000, 2_500_000_000]
        for attempt in 0...pauses.count {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    if attempt < pauses.count { try? await Task.sleep(nanoseconds: pauses[attempt]); continue }
                    return nil
                }
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                guard decoded.elevation.count == coords.count else { return nil }
                return decoded.elevation.map { $0 ?? 0 }   // null (void/water) → sea level
            } catch {
                if attempt < pauses.count { try? await Task.sleep(nanoseconds: pauses[attempt]); continue }
                return nil
            }
        }
        return nil
    }

    // MARK: Disk cache

    private static func cacheKey(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double,
                                 rows: Int, cols: Int) -> String {
        // Round the box so tiny region jitter still hits the same cache entry.
        func r(_ v: Double) -> String { String(format: "%.3f", v) }
        return "elev_\(r(latMin))_\(r(latMax))_\(r(lonMin))_\(r(lonMax))_\(rows)x\(cols)"
    }

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("EtchElevation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct Cached: Codable {
        let rows: Int, cols: Int, values: [Double], minElevation: Double, maxElevation: Double
    }

    private static func readCache(_ key: String) -> ElevationField? {
        let url = cacheDirectory.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url),
              let c = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
        return ElevationField(rows: c.rows, cols: c.cols, values: c.values,
                              minElevation: c.minElevation, maxElevation: c.maxElevation)
    }

    private static func writeCache(_ key: String, _ field: ElevationField) {
        let url = cacheDirectory.appendingPathComponent(key + ".json")
        let c = Cached(rows: field.rows, cols: field.cols, values: field.values,
                       minElevation: field.minElevation, maxElevation: field.maxElevation)
        if let data = try? JSONEncoder().encode(c) { try? data.write(to: url) }
    }
}
