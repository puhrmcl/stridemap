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
    /// A created cart: the web checkout URL, and the cart's own id.
    ///
    /// Both are needed because there are two ways to pay. The URL opens Shopify's hosted checkout
    /// in the sheet — address, card, receipt, all Shopify's. The id is what the native Apple Pay
    /// and Shop Pay buttons check out, and those never open the sheet at all: the buyer confirms
    /// with Face ID and the order is placed. Same cart, same line attributes, same fulfilment
    /// path — so a print ordered in one second carries the asset id exactly as one ordered in ten.
    struct Cart: Sendable {
        /// `gid://shopify/Cart/…` — what `AcceleratedCheckoutButtons(cartID:)` takes.
        let id: String
        let checkoutURL: URL
    }

    static func checkoutURL(
        variantID: String, quantity: Int, attributes: [String: String]
    ) async throws -> URL {
        try await cart(variantID: variantID, quantity: quantity, attributes: attributes).checkoutURL
    }

    static func cart(
        variantID: String, quantity: Int, attributes: [String: String]
    ) async throws -> Cart {
        let mutation = """
        mutation($input: CartInput!) {
          cartCreate(input: $input) {
            cart { id checkoutUrl }
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
            let id = cart["id"] as? String,
            let urlString = cart["checkoutUrl"] as? String,
            let url = URL(string: urlString)
        else { throw StorefrontError.graphQL("The checkout couldn't be created.") }
        return Cart(id: id, checkoutURL: url)
    }

    /// An empty cart, for the bag to fill a line at a time.
    ///
    /// The bag always creates empty and then adds, even for its first item, because `cartCreate`
    /// does not report the ids of the lines it creates and a bag needs them to remove anything.
    /// One extra round trip buys a uniform path: every line in the bag arrived the same way and
    /// every one of them can be taken out again.
    static func createEmptyCart() async throws -> Cart {
        let mutation = """
        mutation {
          cartCreate(input: {}) {
            cart { id checkoutUrl }
            userErrors { message }
          }
        }
        """
        let data = try await execute(query: mutation, variables: [:])
        guard let payload = data["cartCreate"] as? [String: Any] else {
            throw StorefrontError.graphQL("Unexpected cart response.")
        }
        if let errors = payload["userErrors"] as? [[String: Any]],
           let first = errors.first, let message = first["message"] as? String {
            throw StorefrontError.graphQL(message)
        }
        guard
            let cart = payload["cart"] as? [String: Any],
            let id = cart["id"] as? String,
            let urlString = cart["checkoutUrl"] as? String,
            let url = URL(string: urlString)
        else { throw StorefrontError.graphQL("The bag couldn't be created.") }
        return Cart(id: id, checkoutURL: url)
    }

    /// Adds a line to a cart that already exists, and hands back the cart plus the id of the line
    /// just added.
    ///
    /// The line id is found by matching `_etch_asset_id` rather than by taking the last edge:
    /// Shopify does not promise line order, and taking the wrong id here would mean a customer
    /// removing one piece from their bag and watching a different one disappear.
    static func addLine(
        cartID: String, variantID: String, quantity: Int, attributes: [String: String]
    ) async throws -> (cart: Cart, lineID: String) {
        let mutation = """
        mutation($cartId: ID!, $lines: [CartLineInput!]!) {
          cartLinesAdd(cartId: $cartId, lines: $lines) {
            cart {
              id
              checkoutUrl
              lines(first: 50) { edges { node { id attributes { key value } } } }
            }
            userErrors { message }
          }
        }
        """
        let lineAttributes = attributes
            .sorted { $0.key < $1.key }
            .map { ["key": $0.key, "value": $0.value] }
        let lines: [[String: Any]] = [[
            "merchandiseId": variantID,
            "quantity": quantity,
            "attributes": lineAttributes,
        ]]
        let data = try await execute(query: mutation,
                                     variables: ["cartId": cartID, "lines": lines])

        guard let payload = data["cartLinesAdd"] as? [String: Any] else {
            throw StorefrontError.graphQL("Unexpected cart response.")
        }
        if let errors = payload["userErrors"] as? [[String: Any]],
           let first = errors.first, let message = first["message"] as? String {
            throw StorefrontError.graphQL(message)
        }
        guard
            let cart = payload["cart"] as? [String: Any],
            let id = cart["id"] as? String,
            let urlString = cart["checkoutUrl"] as? String,
            let url = URL(string: urlString)
        else { throw StorefrontError.graphQL("The bag couldn't be updated.") }

        let wanted = attributes["_etch_asset_id"] ?? ""
        let edges = (cart["lines"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []
        let lineID = edges.compactMap { edge -> String? in
            guard let node = edge["node"] as? [String: Any],
                  let nodeID = node["id"] as? String,
                  let attrs = node["attributes"] as? [[String: Any]] else { return nil }
            let matches = attrs.contains {
                ($0["key"] as? String) == "_etch_asset_id" && ($0["value"] as? String) == wanted
            }
            return matches ? nodeID : nil
        }.first

        guard let lineID else {
            throw StorefrontError.graphQL("The bag couldn't confirm what was added.")
        }
        return (Cart(id: id, checkoutURL: url), lineID)
    }

    /// Removes one line. Returns the cart so the caller can refresh its checkout URL, which
    /// changes as the cart does.
    static func removeLine(cartID: String, lineID: String) async throws -> Cart {
        let mutation = """
        mutation($cartId: ID!, $lineIds: [ID!]!) {
          cartLinesRemove(cartId: $cartId, lineIds: $lineIds) {
            cart { id checkoutUrl }
            userErrors { message }
          }
        }
        """
        let data = try await execute(query: mutation,
                                     variables: ["cartId": cartID, "lineIds": [lineID]])
        guard let payload = data["cartLinesRemove"] as? [String: Any] else {
            throw StorefrontError.graphQL("Unexpected cart response.")
        }
        if let errors = payload["userErrors"] as? [[String: Any]],
           let first = errors.first, let message = first["message"] as? String {
            throw StorefrontError.graphQL(message)
        }
        guard
            let cart = payload["cart"] as? [String: Any],
            let id = cart["id"] as? String,
            let urlString = cart["checkoutUrl"] as? String,
            let url = URL(string: urlString)
        else { throw StorefrontError.graphQL("The bag couldn't be updated.") }
        return Cart(id: id, checkoutURL: url)
    }

    // MARK: Gift cards

    /// One buyable gift amount — a variant of the shop's gift card product. Hashable because
    /// the picker that offers the amounts tags its rows with whole values.
    struct GiftDenomination: Sendable, Identifiable, Hashable {
        let id: String        // variant gid, what a cart line takes
        let title: String     // e.g. "$50"
        let amountCents: Int
        let currency: String
    }

    /// A gift card the cart accepted: enough to *show* the credit, never the code itself.
    struct AppliedGiftCredit: Sendable, Equatable {
        let lastCharacters: String
        let amountUsedCents: Int
    }

    /// The gift card product's denominations, cheapest first. Throws `.graphQL` when the shop
    /// has no product at the handle — the storefront isn't set up for gifting yet, and the page
    /// says so instead of showing an empty picker.
    static func giftDenominations(productHandle: String) async throws -> [GiftDenomination] {
        let query = """
        query($handle: String!) {
          product(handle: $handle) {
            variants(first: 20) {
              edges { node { id title price { amount currencyCode } } }
            }
          }
        }
        """
        let data = try await execute(query: query, variables: ["handle": productHandle])
        guard let product = data["product"] as? [String: Any],
              let edges = (product["variants"] as? [String: Any])?["edges"] as? [[String: Any]]
        else { throw StorefrontError.graphQL("The shop has no gift card product yet.") }
        let denominations: [GiftDenomination] = edges.compactMap { edge in
            guard let node = edge["node"] as? [String: Any],
                  let id = node["id"] as? String,
                  let title = node["title"] as? String,
                  let price = node["price"] as? [String: Any],
                  let amount = price["amount"] as? String,
                  let currency = price["currencyCode"] as? String,
                  let value = Double(amount) else { return nil }
            return GiftDenomination(id: id, title: title,
                                    amountCents: Int((value * 100).rounded()),
                                    currency: currency)
        }
        guard !denominations.isEmpty else {
            throw StorefrontError.graphQL("The gift card product has no amounts yet.")
        }
        return denominations.sorted { $0.amountCents < $1.amountCents }
    }

    /// Applies gift card codes to a cart, so the credit is on the order *before* checkout —
    /// the total the buyer sees in the bag, in the Apple Pay sheet and in the hosted checkout
    /// is already reduced. Returns what the cart accepted; a code that is invalid, empty or
    /// foreign simply doesn't appear in the result rather than erroring the whole cart.
    static func applyGiftCards(cartID: String, codes: [String])
        async throws -> [AppliedGiftCredit] {
        let mutation = """
        mutation($cartId: ID!, $codes: [String!]!) {
          cartGiftCardCodesUpdate(cartId: $cartId, giftCardCodes: $codes) {
            cart {
              appliedGiftCards {
                lastCharacters
                amountUsed { amount }
              }
            }
            userErrors { message }
          }
        }
        """
        let data = try await execute(query: mutation,
                                     variables: ["cartId": cartID, "codes": codes])
        guard let payload = data["cartGiftCardCodesUpdate"] as? [String: Any] else {
            throw StorefrontError.graphQL("Unexpected gift card response.")
        }
        if let errors = payload["userErrors"] as? [[String: Any]],
           let first = errors.first, let message = first["message"] as? String {
            throw StorefrontError.graphQL(message)
        }
        let applied = ((payload["cart"] as? [String: Any])?["appliedGiftCards"]
                       as? [[String: Any]]) ?? []
        return applied.compactMap { card in
            guard let last = card["lastCharacters"] as? String,
                  let used = card["amountUsed"] as? [String: Any],
                  let amount = used["amount"] as? String,
                  let value = Double(amount) else { return nil }
            return AppliedGiftCredit(lastCharacters: last,
                                     amountUsedCents: Int((value * 100).rounded()))
        }
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
