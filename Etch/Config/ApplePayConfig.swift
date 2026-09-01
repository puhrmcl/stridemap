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
    /// **Withdrawn again, with the entitlement, to get a build to TestFlight.**
    ///
    /// The history matters because the obvious diagnosis is now the wrong one. b414 emptied this
    /// because the App ID carried no Apple Pay capability, and an entitlement is not a local
    /// declaration — it is a claim checked against the App ID at signing time, so automatic
    /// signing could mint no provisioning profile at all and `exportArchive` failed with exit 70
    /// for development, ad-hoc and App Store alike. b415 restored it once the merchant existed.
    ///
    /// The portal has since been confirmed correct: Apple Pay Payment Processing is enabled on
    /// the App ID with one enabled merchant, and that merchant is `merchant.com.nwagtech.etch`.
    /// So whatever is failing now is *not* the b414 cause repeating, and this withdrawal is not a
    /// fix — it removes the one variable between a green GitHub build and a red Xcode Cloud one so
    /// a build can reach testers while the real cause is found. If Xcode Cloud still fails with
    /// this absent, the entitlement was never the problem and the search moves elsewhere, which
    /// is worth knowing either way.
    ///
    /// Restoring it is the same paired edit as b415: this string and the
    /// `com.apple.developer.in-app-payments` key in `Etch.entitlements`, in one commit. Apart
    /// they are worse than either alone — an identifier set without the entitlement gives wallet
    /// buttons that render and then fail at the payment sheet.
    ///
    /// Nothing else is lost meanwhile. `isConfigured` goes false, the wallet buttons are simply
    /// not drawn, and Shopify's hosted checkout takes every order exactly as it does today. The
    /// payment processing certificate — still waiting on Shopify's scope approval — was never
    /// going to let a tap take money before this landed anyway.
    static let merchantIdentifier = ""

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
