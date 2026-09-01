import Foundation

/// GENERATED AT BUILD TIME — do not put real values here.
///
/// This checked-in copy is the empty placeholder that keeps local and CI builds compiling.
/// On Xcode Cloud, `ci_scripts/ci_post_clone.sh` overwrites this file from the workflow's
/// ETCH_STOREFRONT_TOKEN and ETCH_UPLOAD_TOKEN environment variables before the build, so
/// TestFlight builds carry the live tokens without them ever entering the repository.
enum CommerceSecrets {
    static let storefrontToken = ""
    static let uploadToken = ""
}
