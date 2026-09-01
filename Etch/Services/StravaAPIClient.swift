import Foundation

/// Thin async client over the Strava v3 REST API.
struct StravaAPIClient {

    let auth: StravaAuthService

    enum APIError: LocalizedError {
        case rateLimited
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return "Strava rate limit reached. Try again in a few minutes."
            case .http(let code, let message):
                return "Strava error \(code): \(message)"
            }
        }
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Bad date: \(string)"
            )
        }
        return d
    }

    /// Fetches a page of the athlete's activities.
    /// - Parameters:
    ///   - page: 1-based page index.
    ///   - perPage: up to 200.
    ///   - after: only return activities recorded after this epoch second (for incremental sync).
    func activities(page: Int, perPage: Int = 100, after: TimeInterval? = nil) async throws -> [StravaActivity] {
        var components = URLComponents(
            url: StravaConfig.apiBaseURL.appendingPathComponent("athlete/activities"),
            resolvingAgainstBaseURL: false
        )!
        var query: [URLQueryItem] = [
            .init(name: "page", value: String(page)),
            .init(name: "per_page", value: String(perPage)),
        ]
        if let after { query.append(.init(name: "after", value: String(Int(after)))) }
        components.queryItems = query

        return try await get([StravaActivity].self, url: components.url!)
    }

    /// Fetches detail for a single activity (adds city/state/country).
    func activityDetail(id: Int64) async throws -> StravaActivityDetail {
        let url = StravaConfig.apiBaseURL.appendingPathComponent("activities/\(id)")
        return try await get(StravaActivityDetail.self, url: url)
    }

    private func get<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        let accessToken = try await auth.validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(-1, "No response")
        }
        if http.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }
}
