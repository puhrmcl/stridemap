import Foundation
import Observation

/// The gift card codes this phone has redeemed, and the job of applying them to every cart.
///
/// Etch has no accounts, so "the recipient's balance" lives where everything else does: on the
/// device, codes in the Keychain. Redeeming in the app stores the code; from then on every cart
/// the app creates — the bag, or a one-tap Buy Now — gets the codes applied *before* checkout,
/// which is what makes the credit visible up front: the bag shows it, the Apple Pay sheet asks
/// for the reduced total, and an order small enough is simply paid.
///
/// The balance itself stays Shopify's. A code's remaining value is authoritative there and only
/// there — the wallet never records an amount, only codes, so a card spent across two orders (or
/// topped up by the shop) is always read fresh from the cart it is applied to.
@Observable
@MainActor
final class GiftCardWallet {

    static let shared = GiftCardWallet()

    private static let keychainKey = "etch.giftcard.codes"

    /// Redeemed codes, oldest first. Private: nothing outside needs the codes themselves.
    private var codes: [String]

    /// What the most recent application reported — the bag renders this as its credit rows.
    private(set) var appliedCredits: [ShopifyStorefront.AppliedGiftCredit] = []

    private init() {
        codes = KeychainStore.read([String].self, for: Self.keychainKey) ?? []
    }

    var hasCodes: Bool { !codes.isEmpty }

    var appliedCents: Int { appliedCredits.reduce(0) { $0 + $1.amountUsedCents } }

    /// Validates and stores a code. There is no "check a code" endpoint on the storefront, so
    /// validation is the real thing: apply it to a throwaway cart and see whether the cart
    /// accepts it. Accepted → stored; not → thrown, with the storefront's own message when it
    /// has one.
    func redeem(_ rawCode: String) async throws {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw RedeemError.empty }
        guard !codes.contains(where: { $0.caseInsensitiveCompare(code) == .orderedSame }) else {
            throw RedeemError.alreadyRedeemed
        }
        let probe = try await ShopifyStorefront.createEmptyCart()
        let accepted = try await ShopifyStorefront.applyGiftCards(cartID: probe.id, codes: [code])
        // An empty cart uses none of the balance, so acceptance — the card appearing on the
        // cart at all — is the signal, not the amount.
        guard !accepted.isEmpty else { throw RedeemError.notAccepted }
        codes.append(code)
        persist()
    }

    /// Forgets every stored code (they stay valid in Shopify — this only clears the phone).
    func removeAll() {
        codes.removeAll()
        appliedCredits = []
        persist()
    }

    /// Applies the stored codes to a cart, remembering what stuck. Best-effort by design: a
    /// gift card must never be the reason a checkout fails to open, so errors clear the shown
    /// credit and nothing else — the buyer can still pay in full.
    func apply(to cartID: String) async {
        guard hasCodes else { return }
        do {
            appliedCredits = try await ShopifyStorefront.applyGiftCards(cartID: cartID, codes: codes)
        } catch {
            appliedCredits = []
        }
    }

    private func persist() {
        KeychainStore.save(codes, for: Self.keychainKey)
    }

    enum RedeemError: LocalizedError {
        case empty, alreadyRedeemed, notAccepted
        var errorDescription: String? {
            switch self {
            case .empty:           return "Enter the code from your gift card email."
            case .alreadyRedeemed: return "That gift card is already on this phone."
            case .notAccepted:     return "That code wasn't recognised. Check it against the email — codes have no spaces."
            }
        }
    }
}
