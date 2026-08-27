import Foundation

/// Apple Pay wiring for one-tap ordering.
///
/// There are two ways to pay for a print, and they are not the same experience. Shopify's hosted
/// checkout in a sheet is the complete one — every address field, every card, every receipt, and
/// Shopify carries the compliance. The native wallet buttons are the *fast* one: the buyer
/// confirms with Face ID against a card and address Apple already holds, and the order is placed
/// without a form. On a product bought on impulse from a phone, that difference is most of the
/// conversion.
///
/// Both check out the same cart, with the same line attributes, so a print ordered in one second
/// reaches the fulfilment worker carrying the same `_etch_asset_id` as one ordered in ten. The
/// sheet stays as the fallback and as the path for anyone without a wallet card.
///
/// Turning it on takes three things, and none of them are code:
///
/// 1. **A merchant identifier**, created at developer.apple.com → Certificates, Identifiers &
///    Profiles → Identifiers → Merchant IDs. Convention is a reverse-DNS string beginning
///    `merchant.` — `merchant.com.nwagtech.etch` is the one this app declares.
/// 2. **The Merchant IDs entitlement** on the App ID, listing that identifier. It is declared in
///    `Etch.entitlements` as `com.apple.developer.in-app-payments`; the App ID has to carry the
///    capability too or signing fails to mint a profile — the same failure mode WeatherKit hit.
/// 3. **A payment processing certificate**, which Shopify holds the private key for — the app
///    never sees a card. Apple's portal asks for "a CSR file from your Mac"; that is the path
///    for merchants who process their own payments and is the wrong one here. Shopify generates
///    the CSR through its REST Admin API, you upload it to Apple, and Apple's certificate goes
///    back to Shopify the same way. The `Apple Pay certificate` workflow runs all of that —
///    see `.github/apple-pay-request.txt`.
///
/// Two Shopify scopes gate it and both need approval before they can be granted, so they are
/// worth requesting early: `write_cart_wallet_payments` for the accelerated checkout buttons,
/// and `write_mobile_payments` + `read_mobile_payments` for the certificate.
///
/// The app that holds those scopes is created at dev.shopify.com, not in the store admin —
/// Shopify retired admin-created custom apps and with them the permanent `shpat_` token. What
/// exists now is a client id and secret exchanged for a 24-hour token through the client
/// credentials grant, which is why nothing durable is stored anywhere.
///
/// Note the ordering. The merchant identifier and the App ID capability are what unblock the
/// *build*; the certificate is what unblocks *transactions*. The entitlement can come back as
/// soon as the first two exist.
///
/// `isConfigured` also requires the storefront credentials, so the buttons stay hidden until the
/// shop can actually transact — the hosted checkout handles every order until then, and nothing
/// is half-on.
enum ApplePayConfig {

    /// The merchant identifier. Must match an entry in the app's Merchant IDs entitlement
    /// **and** a merchant on the App ID's Apple Pay capability — all three are the same string,
    /// and signing fails if any of them disagrees.
    ///
    /// This was empty for one build, and the reason is worth keeping. Declaring
    /// `com.apple.developer.in-app-payments` while the App ID carried no Apple Pay capability
    /// made automatic signing unable to mint *any* provisioning profile, so `exportArchive`
    /// failed with exit 70 for development, ad-hoc and App Store alike and nothing reached
    /// TestFlight. WeatherKit did the same thing earlier in this project. An entitlement is not
    /// a local declaration — it is a claim checked against the App ID at signing time.
    ///
    /// Both halves are now in place: the merchant exists in the developer portal and the
    /// capability is enabled on the App ID listing it. They were restored in a single commit,
    /// which is the only safe way — a merchant identifier set while the entitlement is missing
    /// gives wallet buttons that render and then fail at the payment sheet, which is worse than
    /// no buttons at all.
    static let merchantIdentifier = "merchant.com.nwagtech.etch"

    /// Contact fields the Apple Pay sheet collects.
    ///
    /// Email only. A print needs a shipping address — which Apple Pay always collects — and an
    /// email for the receipt and the tracking link. Asking for a phone number as well is a field
    /// the buyer has to think about for no fulfilment benefit: Prodigi's carriers don't require
    /// one for the destinations this ships to.
    static let requiresEmail = true
    static let requiresPhone = false

    /// Where prints can be sent. Deliberately narrow at launch: these are the markets whose
    /// shipping is quoted, whose duties are understood, and whose returns can be honoured.
    /// Widening it is a one-line change once a market's landed cost is known.
    static let supportedShippingCountries: Set<String> = ["US", "CA", "GB", "AU", "NZ", "IE"]

    /// Whether the wallet buttons should be offered at all.
    ///
    /// The storefront credentials gate it for the same reason they gate the sheet — a button that
    /// can't transact is worse than no button. The merchant identifier is checked too, so that
    /// clearing it is a working kill switch rather than a crash at the Apple Pay sheet.
    static var isConfigured: Bool {
        CommerceConfig.isConfigured && !merchantIdentifier.isEmpty
    }
}
