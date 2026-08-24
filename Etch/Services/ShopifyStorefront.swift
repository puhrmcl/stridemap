import Foundation

/// A minimal Shopify Storefront API client — exactly the two operations checkout needs:
/// resolve a product variant by SKU, and create a cart that carries the hidden Etch line-item
/// properties into the order. Everything else (payment, tax, address, receipts) happens inside
/// Shopify's own checkout, presented by Checkout Sheet Kit.
enum ShopifyStorefront {

    struct Variant: Sendable {
        let id: String            // Shopify GID, e.g. gid://shopify/ProductVariant/123
        let sku: String
        let availableForSale: Bool
        let priceCents: Int
        let currency: String
    }

    enum StorefrontError: Error, LocalizedError {
        case notConfigured
        case http(Int)
        case graphQL(String)
        case variantNotFound(sku: String)
        case unavailable(sku: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Ordering isn't available yet."
            case .http(let code):
                return "The shop couldn't be reached (\(code))."
            case .graphQL(let message):
                return message
            case .variantNotFound(let sku):
                return "This product isn't in the shop yet (\(sku))."
            case .unavailable(let sku):
                return "This option is temporarily unavailable (\(sku))."
            }
        }
    }

    // MARK: Variant lookup

    /// Finds the variant carrying `sku` in the product at `handle`. Handles are fixed by the
    /// catalogue (`PrintProduct.shopifyHandle`), and variant SKUs in Shopify are entered to
    /// match `PrintSize.shopifySKU(finish:)` exactly — the SKU is the join key between the
    /// app's catalogue and the store.
    static func variant(sku: String, productHandle: String) async throws -> Variant {
        let query = """
        query($handle: String!) {
          product(handle: $handle) {
            variants(first: 50) {
              nodes { id sku availableForSale price { amount currencyCode } }
            }
          }
        }
        """
        let data = try await execute(query: query, variables: ["handle": productHandle])

        guard
            let product = data["product"] as? [String: Any],
            let variants = (product["variants"] as? [String: Any])?["nodes"] as? [[String: Any]]
        else { throw StorefrontError.variantNotFound(sku: sku) }

        guard let node = variants.first(where: { ($0["sku"] as? String) == sku }) else {
            throw StorefrontError.variantNotFound(sku: sku)
        }
        guard
            let id = node["id"] as? String,
            let price = node["price"] as? [String: Any],
            let amount = price["amount"] as? String
        else { throw StorefrontError.variantNotFound(sku: sku) }

        let available = node["availableForSale"] as? Bool ?? false
        guard available else { throw StorefrontError.unavailable(sku: sku) }
        return Variant(
            id: id, sku: sku, availableForSale: available,
            priceCents: Int(((Double(amount) ?? 0) * 100).rounded()),
            currency: price["currencyCode"] as? String ?? "USD"
        )
    }

    // MARK: Cart

    /// Creates a single-line cart and returns its checkout URL. `attributes` are attached to
    /// the line; keys beginning with `_` are hidden from the customer and arrive on the order
    /// webhook as line-item properties — this is how `_etch_asset_id` reaches the fulfilment
    /// worker.
    static func checkoutURL(
        variantID: String, quantity: Int, attributes: [String: String]
    ) async throws -> URL {
        let mutation = """
        mutation($input: CartInput!) {
          cartCreate(input: $input) {
            cart { checkoutUrl }
            userErrors { message }
          }
        }
        """
        let lineAttributes = attributes
            .sorted { $0.key < $1.key }
            .map { ["key": $0.key, "value": $0.value] }
        let input: [String: Any] = [
            "lines": [[
                "merchandiseId": variantID,
                "quantity": quantity,
                "attributes": lineAttributes,
            ]]
        ]
        let data = try await execute(query: mutation, variables: ["input": input])

        guard let payload = data["cartCreate"] as? [String: Any] else {
            throw StorefrontError.graphQL("Unexpected cart response.")
        }
        if let errors = payload["userErrors"] as? [[String: Any]],
           let first = errors.first, let message = first["message"] as? String {
            throw StorefrontError.graphQL(message)
        }
        guard
            let cart = payload["cart"] as? [String: Any],
            let urlString = cart["checkoutUrl"] as? String,
            let url = URL(string: urlString)
        else { throw StorefrontError.graphQL("The checkout couldn't be created.") }
        return url
    }

    // MARK: Transport

    private static func execute(query: String, variables: [String: Any]) async throws -> [String: Any] {
        guard CommerceConfig.isConfigured else { throw StorefrontError.notConfigured }

        var request = URLRequest(url: CommerceConfig.storefrontEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(CommerceConfig.storefrontToken,
                         forHTTPHeaderField: "X-Shopify-Storefront-Access-Token")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw StorefrontError.http(status) }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let errors = json["errors"] as? [[String: Any]],
           let first = errors.first, let message = first["message"] as? String {
            throw StorefrontError.graphQL(message)
        }
        return json["data"] as? [String: Any] ?? [:]
    }
}
