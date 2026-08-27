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
/// 3. **Apple Pay enabled in Shopify**, under Settings → Payments. Shopify holds the payment
///    processing certificate; the app never sees a card.
///
/// Until the identifier resolves, `isConfigured` is false and the buttons are simply not drawn —
/// the sheet handles every order, exactly as it does today. Nothing breaks while this is pending.
enum ApplePayConfig {

    /// The merchant identifier, which must match an entry in the app's Merchant IDs entitlement.
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
