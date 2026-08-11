import Foundation

/// Central configuration for Strava OAuth.
///
/// To connect the app to your own Strava API application:
///  1. Create an API application at https://www.strava.com/settings/api
///  2. Set the "Authorization Callback Domain" to `etch` (the URL scheme below).
///  3. Paste your **Client ID** below (it is public and safe to ship).
///  4. Deploy the token proxy in `worker/` (see `worker/README.md`) and paste its URL
///     into `tokenProxyURL`.
///
/// - Important: The Strava **client secret is never stored in the app**. Token exchange
///   and refresh are performed by the Cloudflare Worker in `worker/`, which holds the
///   secret server-side. This avoids shipping a secret inside the app bundle.
enum StravaConfig {

    /// Your Strava application's Client ID. Public — safe to ship in the app.
    static let clientID = "271462"

    /// URL of your deployed token proxy Worker (see `worker/README.md`), e.g.
    /// `https://etch-strava-proxy.<your-subdomain>.workers.dev`.
    /// The app POSTs `{ grant_type, code | refresh_token }` to `<tokenProxyURL>/oauth/token`.
    static let tokenProxyURL = "https://etch-strava-proxy.YOUR-SUBDOMAIN.workers.dev"

    /// Custom URL scheme registered in Info.plist (`CFBundleURLSchemes`).
    static let urlScheme = "etch"

    /// The redirect URI Strava will call back after authorization.
    static let redirectURI = "\(urlScheme)://callback"

    /// Scopes we request. `activity:read_all` is required to read private activities
    /// and their GPS polylines.
    static let scope = "read,activity:read_all"

    // MARK: Endpoints

    static let authorizeURL = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    static let apiBaseURL = URL(string: "https://www.strava.com/api/v3")!

    /// The token-proxy token endpoint the app calls for exchange/refresh.
    static var tokenEndpoint: URL {
        URL(string: tokenProxyURL)!.appendingPathComponent("oauth/token")
    }

    /// Whether the developer has filled in real credentials (Client ID + proxy URL).
    static var isConfigured: Bool {
        clientID != "YOUR_STRAVA_CLIENT_ID" && !clientID.isEmpty
            && !tokenProxyURL.contains("YOUR-SUBDOMAIN")
    }
}
