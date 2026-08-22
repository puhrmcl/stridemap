import Foundation

/// The fulfilment contract for Etch Studio print orders.
///
/// One rule governs this layer: **the device never renders the file that gets printed, and never
/// holds a fulfilment credential.** The phone sends a *recipe* — which activity, which poster
/// config, which SKU — and the Etch backend renders the print-ready artwork at 300 DPI, uploads it,
/// and creates the Prodigi order. That keeps three promises: print files are reproducible for
/// reprints, colour is managed in one place, and a leaked build never exposes a Prodigi key.
///
/// `FulfilmentProvider` exists so Prodigi is an implementation detail from day one. Print partners
/// get switched — the first is rarely the last — and the adapter is the only thing that should
/// change when that happens.

// MARK: - Order model

/// A shipping destination. Deliberately minimal; the backend validates and normalises.
struct ShippingAddress: Codable, Equatable, Sendable {
    var recipientName: String
    var line1: String
    var line2: String?
    var city: String
    var region: String       // state / province
    var postalCode: String
    var countryCode: String  // ISO-3166-1 alpha-2
}

/// What the customer bought, described so the backend can re-render it exactly.
struct PrintOrderRequest: Codable, Equatable, Sendable {
    /// Idempotency key. One render and one charge per key, so a retry never bills or prints twice.
    var orderID: UUID
    /// The activity the artwork is made from.
    var runID: UUID
    /// The saved Studio project, when the user ordered from a kept poster.
    var posterID: UUID?
    /// Prodigi SKU for the chosen product + size.
    var sku: String
    /// Frame finish attribute, for framed products.
    var frameFinish: String?
    var quantity: Int
    var priceCents: Int
    var currency: String
    var shipTo: ShippingAddress
    /// Optional gift note, printed on the packing slip rather than the artwork.
    var giftNote: String?
}

/// Where an order is in its life. Mirrors what the backend derives from Prodigi's webhooks, so the
/// app can show honest status without knowing anything about the provider.
enum PrintOrderStatus: String, Codable, Sendable {
    case draft            // being configured on device
    case submitted        // accepted by the Etch backend
    case rendering        // backend is producing the print-ready file
    case inProduction     // provider is printing
    case shipped
    case delivered
    case cancelled
    case failed           // render or fulfilment failed; support workflow owns it

    var label: String {
        switch self {
        case .draft:        return "Draft"
        case .submitted:    return "Order placed"
        case .rendering:    return "Preparing your print"
        case .inProduction: return "Printing"
        case .shipped:      return "On its way"
        case .delivered:    return "Delivered"
        case .cancelled:    return "Cancelled"
        case .failed:       return "Needs attention"
        }
    }

    /// Whether the order is still moving on its own. Terminal states stop polling.
    var isActive: Bool {
        switch self {
        case .draft, .submitted, .rendering, .inProduction: return true
        case .shipped, .delivered, .cancelled, .failed:     return false
        }
    }
}

/// What the app knows about a placed order.
struct PrintOrder: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var runID: UUID
    var sku: String
    var productName: String
    var sizeLabel: String
    var status: PrintOrderStatus
    var placedAt: Date
    var trackingURL: URL?
    var carrier: String?
    var estimatedDelivery: Date?
}

// MARK: - Provider contract

enum FulfilmentError: Error, LocalizedError {
    case notConfigured
    case rejected(reason: String)
    case network(underlying: String)
    /// The artwork cannot be produced at an acceptable DPI for the requested size.
    case insufficientResolution(achievedDPI: Double, required: Double)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Print ordering isn't available yet."
        case .rejected(let reason):
            return reason
        case .network(let underlying):
            return "Couldn't reach the print service. \(underlying)"
        case .insufficientResolution(let achieved, let required):
            return "This activity can't be printed at that size yet "
                 + "(\(Int(achieved)) DPI, needs \(Int(required)))."
        }
    }
}

/// The interface the app talks to. An implementation always goes through the Etch backend — there
/// is deliberately no direct-to-Prodigi client here.
protocol FulfilmentProvider: Sendable {
    /// Whether ordering is live. False keeps the UI honest instead of offering a dead button.
    var isAvailable: Bool { get }
    /// Confirms price, tax and shipping for a configured order before charge.
    func quote(_ request: PrintOrderRequest) async throws -> PrintQuote
    /// Submits a paid order. Must be idempotent on `request.orderID`.
    func submit(_ request: PrintOrderRequest, paymentToken: String) async throws -> PrintOrder
    /// Current state of a previously placed order.
    func status(orderID: UUID) async throws -> PrintOrder
}

struct PrintQuote: Codable, Equatable, Sendable {
    var itemsCents: Int
    var shippingCents: Int
    var taxCents: Int
    var currency: String
    var estimatedDeliveryDays: ClosedRange<Int>?

    var totalCents: Int { itemsCents + shippingCents + taxCents }
    var total: String {
        (Double(totalCents) / 100).formatted(.currency(code: currency))
    }
}

/// The provider in use until the Etch backend is live. It reports itself unavailable, so the
/// Studio UI can show the real product, sizes and prices while being straight with the customer
/// that checkout isn't open — rather than presenting a button that fails.
struct UnavailableFulfilmentProvider: FulfilmentProvider {
    var isAvailable: Bool { false }
    func quote(_ request: PrintOrderRequest) async throws -> PrintQuote {
        throw FulfilmentError.notConfigured
    }
    func submit(_ request: PrintOrderRequest, paymentToken: String) async throws -> PrintOrder {
        throw FulfilmentError.notConfigured
    }
    func status(orderID: UUID) async throws -> PrintOrder {
        throw FulfilmentError.notConfigured
    }
}

/// The app's current provider. Swapping in the live backend adapter is a one-line change here.
enum Fulfilment {
    static let provider: FulfilmentProvider = UnavailableFulfilmentProvider()
}
