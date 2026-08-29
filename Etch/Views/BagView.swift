import SwiftUI
import ShopifyCheckoutSheetKit
import ShopifyAcceleratedCheckouts

/// The Bag: what you are about to order, and what you already have.
///
/// It is a tab rather than a screen reached from inside a product page because of who it is for.
/// The customer this shop is built around finishes a marathon and wants three things: the book of
/// the year, the framed print of the race, the medal on the wall. Those are assembled in three
/// different places — Studio, a piece's own print sheet, a frame's picker — and a bag reachable
/// only from inside one of them is a bag the other two never reach. A persistent tab with a count
/// on it is what makes a basket feel like a basket rather than three separate purchases.
///
/// The bag holds a real Shopify cart now: pieces are rendered and uploaded when they are added,
/// so every line already has a print file behind it, and the whole bag checks out in one payment.
/// One-tap Apple Pay is unchanged for a single piece — the accelerated buttons take a cart, and a
/// cart with three lines is still a cart.
///
/// `OrderStore` below it is on-device by design — Etch has no account system, and the phone is
/// the record.
struct BagView: View {
    @State private var orders: [PrintOrder] = []
    @State private var isRefreshing = false
    @State private var cart = CartStore.shared
    @State private var checkout: URL?
    @State private var removing: String?

    var body: some View {
        NavigationStack {
            Group {
                if orders.isEmpty && cart.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing in your bag", systemImage: "bag")
                    } description: {
                        Text("Add pieces here and check out together, or buy one on its own. Orders stay here so you can follow one from the press to your door.")
                    }
                } else {
                    List {
                        if !cart.items.isEmpty {
                            Section("Ready to order") {
                                ForEach(cart.items) { item in cartRow(item) }
                                checkoutBlock
                            }
                        }
                        if !orders.isEmpty {
                            Section("Orders") {
                                ForEach(orders) { order in orderRow(order) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .sheet(item: Binding(
                get: { checkout.map { BagCheckoutTarget(url: $0) } },
                set: { if $0 == nil { checkout = nil } }
            )) { target in
                CheckoutSheet(checkout: target.url)
                    .title("Checkout")
                    .colorScheme(.automatic)
                    .tintColor(UIColor(Theme.accent))
                    .onCancel { checkout = nil }
                    .onComplete { _ in
                        // The cart id is spent the moment its order completes; keeping it would
                        // add the next piece to an order that has already been paid for.
                        cart.clear()
                        checkout = nil
                        Task { await refresh() }
                    }
                    .onFail { _ in checkout = nil }
                    .interactiveDismissDisabled()
            }
            .alert("Your bag expired", isPresented: Binding(
                get: { cart.expiredRecently }, set: { if !$0 { cart.acknowledgeExpiry() } }
            )) {
                Button("OK", role: .cancel) { cart.acknowledgeExpiry() }
            } message: {
                Text("Print files are prepared when a piece is added and are not kept indefinitely. Add your pieces again and they will be ready to order.")
            }
            // The shared header rather than a large navigation title: the same masthead every
            // surface but the map wears, so moving between tabs changes the words and nothing
            // else.
            .safeAreaInset(edge: .top, spacing: 0) {
                EtchPageHeader("Bag")
                    .padding(.bottom, 10)
                    .background(.bar)
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await refresh() }
            .task { await refresh() }
        }
    }

    /// One piece waiting to be ordered.
    private func cartRow(_ item: CartItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(.headline, design: .rounded))
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.price)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Button {
                    remove(item)
                } label: {
                    if removing == item.lineID {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Remove")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(removing != nil)
            }
        }
        .padding(.vertical, 4)
    }

    /// Subtotal and the two ways out. The wallet buttons take the whole bag, so one tap pays for
    /// three pieces exactly as it pays for one — the accelerated checkout works on a cart, and a
    /// cart with three lines is still a cart.
    @ViewBuilder private var checkoutBlock: some View {
        VStack(spacing: 12) {
            HStack {
                Text(cart.count == 1 ? "1 piece" : "\(cart.count) pieces")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(cart.subtotal)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }

            if let url = cart.checkoutURL {
                if ApplePayConfig.isConfigured, let id = cart.cartID {
                    AcceleratedCheckoutButtons(cartID: id)
                        .wallets([.applePay, .shopPay])
                        .cornerRadius(14)
                        .onComplete { _ in
                            cart.clear()
                            Task { await refresh() }
                        }
                        .environmentObject(ShopifyAcceleratedCheckouts.Configuration(
                            storefrontDomain: CommerceConfig.shopDomain,
                            storefrontAccessToken: CommerceConfig.storefrontToken
                        ))
                        .environmentObject(ShopifyAcceleratedCheckouts.ApplePayConfiguration(
                            merchantIdentifier: ApplePayConfig.merchantIdentifier,
                            contactFields: ApplePayConfig.requiresPhone ? [.email, .phone] : [.email],
                            supportedShippingCountries: ApplePayConfig.supportedShippingCountries
                        ))
                }
                Button { checkout = url } label: {
                    Text(ApplePayConfig.isConfigured ? "Other ways to pay" : "Check out · \(cart.subtotal)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(ApplePayConfig.isConfigured ? Theme.accent : .white)
                        .background(ApplePayConfig.isConfigured ? Theme.accent.opacity(0.12) : Theme.accent,
                                    in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            Text("Shipping and any duties are calculated at checkout. Every piece is printed to order.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 6)
    }

    private func remove(_ item: CartItem) {
        guard let cartID = cart.cartID else { return }
        removing = item.lineID
        Task {
            defer { removing = nil }
            // The local mirror is updated whether or not Shopify answers: a line the customer has
            // taken out must not reappear because the network was slow, and an orphaned Shopify
            // line simply never gets checked out.
            if let updated = try? await ShopifyStorefront.removeLine(cartID: cartID,
                                                                    lineID: item.lineID) {
                cart.replace(cart: updated)
            }
            cart.remove(lineID: item.lineID)
        }
    }

    private func orderRow(_ order: PrintOrder) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(order.productName)
                    .font(.system(.headline, design: .rounded))
                Spacer(minLength: 8)
                Text(order.sizeLabel)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(order.status.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusTint(order.status).opacity(0.14), in: .capsule)
                    .foregroundStyle(statusTint(order.status))
                Text(order.placedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let tracking = order.trackingURL {
                Link(destination: tracking) {
                    Label(order.carrier.map { "Track with \($0)" } ?? "Track this order",
                          systemImage: "shippingbox")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Status carries colour as well as words, so a bag of several orders can be read at a glance
    /// rather than line by line. `failed` is the only one that earns a warning colour — everything
    /// else is progress, and colouring progress red teaches people to ignore the colour.
    private func statusTint(_ status: PrintOrderStatus) -> Color {
        switch status {
        case .delivered:            return .green
        case .failed:               return .orange
        case .cancelled:            return .secondary
        default:                    return Theme.accent
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await OrderStore.shared.refreshActive()
        orders = OrderStore.shared.orders
        isRefreshing = false
    }
}

/// Identifiable wrapper so the checkout URL can drive a `sheet(item:)`.
private struct BagCheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
