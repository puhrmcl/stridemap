import Foundation
import UIKit
import Observation
import AuthenticationServices

/// Handles the Strava OAuth flow and keeps a valid access token available.
///
/// The token set is persisted in the Keychain and refreshed automatically when
/// expired. UI observes `isAuthenticated` to switch between onboarding and the map.
@MainActor
@Observable
final class StravaAuthService: NSObject {

    static let shared = StravaAuthService()

    private(set) var token: StravaToken?
    var isAuthenticated: Bool { token != nil }
    var athlete: StravaAthlete? { token?.athlete }

    private let tokenKey = "strava.token"
    private var webSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        token = KeychainStore.read(StravaToken.self, for: tokenKey)
    }

    enum AuthError: LocalizedError {
        case notConfigured
        case cancelled
        case missingCode
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Add your Strava Client ID and Secret in StravaConfig.swift to connect."
            case .cancelled:
                return "Sign-in was cancelled."
            case .missingCode:
                return "Strava did not return an authorization code."
            case .server(let m):
                return m
            }
        }
    }

    // MARK: Sign in

    func signIn() async throws {
        guard StravaConfig.isConfigured else { throw AuthError.notConfigured }

        var components = URLComponents(url: StravaConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: StravaConfig.clientID),
            .init(name: "redirect_uri", value: StravaConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: StravaConfig.scope),
        ]

        let callbackURL = try await authenticate(url: components.url!)
        guard
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
            let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw AuthError.missingCode
        }
        try await exchangeCode(code)
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: StravaConfig.urlScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            session.start()
        }
    }

    // MARK: Token exchange & refresh

    private func exchangeCode(_ code: String) async throws {
        // The client secret lives only in the token-proxy Worker; the app sends just the
        // short-lived authorization code.
        let token = try await postToken([
            "grant_type": "authorization_code",
            "code": code,
        ])
        self.token = token
        KeychainStore.save(token, for: tokenKey)
    }

    /// Returns a currently-valid access token, refreshing if necessary.
    func validAccessToken() async throws -> String {
        guard var token else { throw AuthError.notConfigured }
        if token.isExpired {
            token = try await refresh(token)
            self.token = token
            KeychainStore.save(token, for: tokenKey)
        }
        return token.accessToken
    }

    private func refresh(_ token: StravaToken) async throws -> StravaToken {
        var refreshed = try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": token.refreshToken,
        ])
        // The refresh response omits the athlete; keep the one we already have.
        if refreshed.athlete == nil { refreshed.athlete = token.athlete }
        return refreshed
    }

    /// Posts a token request to the proxy Worker as JSON. The Worker adds the client
    /// secret and forwards to Strava, returning Strava's token JSON verbatim.
    private func postToken(_ payload: [String: String]) async throws -> StravaToken {
        var request = URLRequest(url: StravaConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.server(message)
        }
        return try JSONDecoder().decode(StravaToken.self, from: data)
    }

    // MARK: Sign out

    func signOut() {
        token = nil
        KeychainStore.delete(tokenKey)
    }
}

extension StravaAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
