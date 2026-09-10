import Foundation

/// User-requested diagnostics. No route coordinates, activity names, photos or tokens enter
/// the report or requests; only public service endpoints are probed.
enum MapBackgroundDiagnostic {
    static func report(edition: String, coordinateCount: Int, enabled: Bool, renderer: String) async -> String {
        async let config = probe("config")
        async let tiles = probe("tiles/tiles.json")
        let results = await [config, tiles]
        return (["Etch map diagnostic \(AppInfo.changeTag)",
                 "Background: \(edition)", "Route points: \(coordinateCount)",
                 "Map configuration enabled: \(enabled)", "Latest background result: \(renderer)",
                 "\(Date().formatted(.iso8601))"] + results).joined(separator: "\n")
    }

    private static func probe(_ path: String) async -> String {
        var request = URLRequest(url: CommerceConfig.workerBase.appendingPathComponent(path))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "\(path): no HTTP response" }
            let validJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
            return "\(path): HTTP \(http.statusCode), JSON \(validJSON ? "yes" : "no")"
        } catch {
            let error = error as NSError
            return "\(path): \(error.domain) code \(error.code)"
        }
    }
}
