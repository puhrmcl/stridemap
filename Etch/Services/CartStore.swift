import Foundation
import Observation

/// One piece waiting in the bag.
///
/// Everything shown in the Bag comes from here rather than from Shopify. The cart's authoritative
/// contents live on Shopify and its price is authoritative at checkout — but a bag that had to
/// fetch before it could draw would be a spinner every time the tab is tapped, and the tab carries
/// a count that has to be right the instant it appears.
struct CartItem: Codable, Identifiable, Equatable {
    var id: String { lineID }
    /// Shopify's cart-line id — what a removal needs.
    let lineID: String
    /// The uploaded print file this line is for. The order is unfulfillable without it, which is
    /// what makes the expiry below a correctness matter rather than a tidiness one.
    let assetID: String
    let title: String
    let detail: String
    let priceCents: Int
    let addedAt: Date
    /// Which shop product this line is, so the Bag can dress its proof as the right object —
    /// a frame, a hung sheet, a bound book. Optional: lines saved before proofs existed decode
    /// without them and show the bare sheet.
    var productHandle: String?
    /// The frame/hanger finish name, for the mockup's moulding colour. Empty for unframed lines.
    var finish: String?

    var price: String {
        (Double(priceCents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

/// The bag: a Shopify cart id, and a local mirror of what is in it.
///
/// **Why the bag expires.** The pipeline uploads a print file *before* payment, deliberately — a
/// paid order with no artwork behind it is the one failure this system must never produce. The
/// cost is that a file sitting in a bag nobody has paid for is an upload nobody has claimed, and
/// the worker sweeps those nightly so abandoned checkouts do not bill storage forever.
///
/// A bag therefore cannot outlive the sweeper's window, or a customer would check out against
/// lines whose files had been deleted underneath them and the order would be unfulfillable —
/// exactly the failure the upload-first ordering exists to prevent. The worker's window is seven
/// days; the bag expires at five, leaving two days of margin for a slow or retried webhook. When
/// it expires it says so rather than silently checking out something that cannot be printed.
@MainActor
@Observable
final class CartStore {
    static let shared = CartStore()

    private(set) var cartID: String?
    private(set) var checkoutURL: URL?
    private(set) var items: [CartItem] = []

    /// Days a bag may sit before its uploads are at risk. Two days inside the worker's
    /// `UNSOLD_ASSET_TTL_DAYS`, which is 7 — change one and change the other.
    private static let expiryDays = 5

    private let defaults = UserDefaults.standard
    private let cartKey = "etch.cart.id"
    private let urlKey = "etch.cart.url"
    private let itemsKey = "etch.cart.items"

    private init() {
        cartID = defaults.string(forKey: cartKey)
        if let url = defaults.string(forKey: urlKey) { checkoutURL = URL(string: url) }
        if let data = defaults.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([CartItem].self, from: data) {
            items = decoded
        }
        expireIfStale()
        // Proofs live and die with the lines they show; a failed add or a crash cannot leak one.
        ProofStore.sweep(keeping: Set(items.map(\.assetID)))
    }

    var count: Int { items.count }

    var subtotalCents: Int { items.reduce(0) { $0 + $1.priceCents } }

    var subtotal: String {
        (Double(subtotalCents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// True when a bag was dropped because its uploads were about to be swept — the Bag screen
    /// says so once, rather than leaving the customer to notice their pieces vanished.
    private(set) var expiredRecently = false

    func acknowledgeExpiry() { expiredRecently = false }

    // MARK: Mutation

    func adopt(cart: ShopifyStorefront.Cart, item: CartItem) {
        cartID = cart.id
        checkoutURL = cart.checkoutURL
        items.append(item)
        persist()
    }

    func replace(cart: ShopifyStorefront.Cart) {
        cartID = cart.id
        checkoutURL = cart.checkoutURL
        persist()
    }

    func remove(lineID: String) {
        if let removed = items.first(where: { $0.lineID == lineID }) {
            ProofStore.remove(removed.assetID)
        }
        items.removeAll { $0.lineID == lineID }
        if items.isEmpty { clear() } else { persist() }
    }

    /// Emptied after a completed order — the cart id is spent once its checkout completes, and
    /// reusing it would add the next piece to an order that has already been paid for.
    func clear() {
        for item in items { ProofStore.remove(item.assetID) }
        cartID = nil
        checkoutURL = nil
        items = []
        persist()
    }

    // MARK: Expiry

    private func expireIfStale() {
        guard let oldest = items.map(\.addedAt).min() else { return }
        let age = Date().timeIntervalSince(oldest)
        guard age > Double(Self.expiryDays) * 86_400 else { return }
        clear()
        expiredRecently = true
    }

    private func persist() {
        defaults.set(cartID, forKey: cartKey)
        defaults.set(checkoutURL?.absoluteString, forKey: urlKey)
        defaults.set(try? JSONEncoder().encode(items), forKey: itemsKey)
    }
}
