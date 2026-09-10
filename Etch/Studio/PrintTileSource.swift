import Foundation

/// A versioned tile identity prevents old on-device tile bodies from surviving encoding fixes.
/// Preserve the service's actual zoom range; do not hard-code a replacement archive's limits.
@MainActor
enum PrintTileSource {
    static let revision = "identity-mvt-20260910"
    private static var cached: [String: Any]?
    private static var pending: Task<Data?, Never>?

    static func resolve() async -> [String: Any]? {
        if let cached { return cached }
        let task: Task<Data?, Never>
        if let pending { task = pending }
        else { task = Task { await fetch() }; pending = task }
        let data = await task.value
        pending = nil
        guard let data,
              let metadata = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let resolved = source(from: metadata)
        cached = resolved
        return resolved
    }

    static func versioned(_ template: String) -> String {
        // Tile placeholders must remain literal for MapLibre's substitution.
        let parts = template.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        return path + (path.contains("?") ? "&" : "?") + "etchRevision=" + revision
            + (parts.count > 1 ? "#" + String(parts[1]) : "")
    }

    static func source(from metadata: [String: Any]) -> [String: Any]? {
        guard let tiles = metadata["tiles"] as? [String], !tiles.isEmpty,
              tiles.allSatisfy({ $0.hasPrefix(CommerceConfig.workerBase.absoluteString + "/tiles/") }),
              let min = metadata["minzoom"] as? Int,
              let max = metadata["maxzoom"] as? Int, min >= 0, max >= min, max <= 22 else { return nil }
        var result: [String: Any] = ["type": "vector", "tiles": tiles.map(versioned),
                                     "minzoom": min, "maxzoom": max]
        if let scheme = metadata["scheme"] as? String { result["scheme"] = scheme }
        if let bounds = metadata["bounds"] as? [Double], bounds.count == 4 { result["bounds"] = bounds }
        return result
    }

    private static func fetch() async -> Data? {
        guard let url = URL(string: versioned(EtchCartography.tileJSONURL.absoluteString)) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
