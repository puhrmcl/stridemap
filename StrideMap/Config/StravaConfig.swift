import Foundation

/// Central configuration for Strava OAuth.
///
/// To connect the app to your own Strava API application:
///  1. Create an API application at https://www.strava.com/settings/api
///  2. Set the "Authorization Callback Domain" to `stridemap` (the URL scheme below).
///  3. Paste your Client ID and Client Secret here (or better, inject them via an
///     `.xcconfig` / environment so they are not committed to source control).
///
/// - Important: Strava's token exchange requires the client secret. Embedding a
///   secret in a shipping app is inherently insecure — for a production release you
///   should proxy the token exchange through a small backend you control. For a
///   personal build the values below are sufficient.
enum StravaConfig {

    /// Your Strava application's Client ID.
    static let clientID = "YOUR_STRAVA_CLIENT_ID"

    /// Your Strava application's Client Secret.
    static let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"

    /// Custom URL scheme registered in Info.plist (`CFBundleURLSchemes`).
    static let urlScheme = "stridemap"

    /// The redirect URI Strava will call back after authorization.
    static let redirectURI = "\(urlScheme)://callback"

    /// Scopes we request. `activity:read_all` is required to read private activities
    /// and their GPS polylines.
    static let scope = "read,activity:read_all"

    // MARK: Endpoints

    static let authorizeURL = URL(string: "https://www.strava.com/oauth/mobile/authorize")!
    static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    static let apiBaseURL = URL(string: "https://www.strava.com/api/v3")!

    /// Whether the developer has filled in real credentials.
    static var isConfigured: Bool {
        clientID != "YOUR_STRAVA_CLIENT_ID" && !clientID.isEmpty
    }
}
