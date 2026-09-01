import Foundation

/// The order model shared with the Etch fulfilment worker.
///
/// The transacting pipeline itself lives in `PrintOrderService` (render → upload → Shopify
/// checkout). What remains here is the vocabulary both sides speak: the normalized order
/// status the worker derives from Prodigi's webhooks, and the on-device record of a placed
/// order. The phone holds no fulfilment credential — the upload token grants uploads only,
/// and payment happens entirely inside Shopify's checkout.
///
/// Print files are rendered on-device at order time (Operating Plan, decision 2) and frozen
/// into the worker's asset store before checkout opens, so the file that was paid for is the
/// file that prints — reproducible for reprints, immutable once ordered.

/// Where an order is in its life. Raw values MUST match the worker's normalized statuses, so
/// the app can show honest status without knowing anything about the provider.
enum PrintOrderStatus: String, Codable, Sendable {
    case draft            // being configured on device
    case submitted        // paid; accepted by the Etch backend
    case rendering        // backend is producing the print-ready file (server-render sizes)
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

/// What the app knows about a placed order — written when Shopify reports checkout complete,
/// then refreshed from the worker's `/orders/by-shopify/{id}`.
struct PrintOrder: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    /// Shopify's order id, the key the worker tracks the order under.
    var shopifyOrderID: String?
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
