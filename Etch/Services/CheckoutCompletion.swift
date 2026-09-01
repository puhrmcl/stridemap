import Foundation
import ShopifyCheckoutSheetKit

/// Records a Shopify checkout completion into the on-device `OrderStore`.
///
/// Every checkout surface calls this *before* any UI cleanup. The bag used to empty
/// itself the moment Shopify reported paid, so a completed cart vanished from the phone
/// without an order row — and there is no account system to recover it from.
@MainActor
enum CheckoutCompletion {

    /// Shopify's order id arrives as a GID (`gid://shopify/OrderIdentity/123`); the worker
    /// keys orders by the trailing numeric id.
    static func shopifyOrderID(from event: CheckoutCompletedEvent) -> String {
        event.orderDetails.id.components(separatedBy: "/").last ?? event.orderDetails.id
    }

    static func record(
        _ event: CheckoutCompletedEvent,
        productName: String,
        sizeLabel: String,
        sku: String = "",
        runID: UUID = UUID()
    ) {
        OrderStore.shared.record(PrintOrder(
            id: UUID(),
            shopifyOrderID: shopifyOrderID(from: event),
            runID: runID,
            sku: sku,
            productName: productName,
            sizeLabel: sizeLabel,
            status: .submitted,
            placedAt: .now
        ))
    }

    /// One on-device row per bag line, all keyed to the same Shopify order. Call before
    /// `CartStore.clear()` so a paid bag cannot vanish without an order record.
    static func recordBag(_ event: CheckoutCompletedEvent, items: [CartItem]) {
        let shopifyID = shopifyOrderID(from: event)
        if items.isEmpty {
            record(event, productName: "Order", sizeLabel: "")
            return
        }
        for item in items {
            OrderStore.shared.record(PrintOrder(
                id: UUID(),
                shopifyOrderID: shopifyID,
                runID: UUID(),
                sku: "",
                productName: item.title,
                sizeLabel: item.detail,
                status: .submitted,
                placedAt: .now
            ))
        }
    }
}
