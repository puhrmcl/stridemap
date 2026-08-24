import Foundation

/// Commerce wiring: the Shopify storefront the app transacts against and the Etch fulfilment
/// worker it uploads print files to.
///
/// The two tokens live in `CommerceSecrets.generated.swift`, which is a checked-in placeholder
/// (empty strings) overwritten at build time by `ci_scripts/ci_post_clone.sh` from Xcode Cloud
/// environment variables. Until both are set on the Xcode Cloud workflow, `isConfigured` is
/// false and the shop presents "ordering opens soon" instead of a checkout that can't work.
enum CommerceConfig {

    /// The shop's permanent myshopify domain (byetch.com is the customer-facing alias; the
    /// Storefront API is addressed by this one, which never changes).
    static let shopDomain = "zn1ddh-it.myshopify.com"

    /// Storefront API version. Matches the webhook API version chosen for the fulfilment worker.
    static let storefrontAPIVersion = "2026-07"

    static var storefrontEndpoint: URL {
        URL(string: "https://\(shopDomain)/api/\(storefrontAPIVersion)/graphql.json")!
    }

    /// The Etch fulfilment worker (Cloudflare) — receives the print-ready file before checkout.
    static let workerBase = URL(string: "https://etch-fulfilment.clintpuhrmann.workers.dev")!

    /// Public Storefront API access token (safe to embed by design; scoped to reading products
    /// and creating carts).
    static var storefrontToken: String { CommerceSecrets.storefrontToken }

    /// Bearer token for print-file uploads to the worker. Same value as the worker's
    /// UPLOAD_TOKEN secret; grants uploads only, never Prodigi or Shopify access.
    static var uploadToken: String { CommerceSecrets.uploadToken }

    static var isConfigured: Bool {
        !storefrontToken.isEmpty && !uploadToken.isEmpty
    }
}
