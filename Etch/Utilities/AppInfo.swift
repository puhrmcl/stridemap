import Foundation

/// Build identity, surfaced in-app so a specific TestFlight build can be identified on the
/// device — the marketing version alone stays "1.0" across every build, which makes it
/// impossible to tell which code is actually installed.
enum AppInfo {

    /// Hand-bumped on each meaningful change so we can confirm which fixes a build contains.
    /// If the number on the device is lower than expected, it's an older build.
    static let changeTag = "b450"

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// e.g. "v1.0 (24) · b14"
    static var label: String { "v\(shortVersion) (\(build)) · \(changeTag)" }
}
