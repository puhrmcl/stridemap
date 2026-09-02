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
    /// The line whose proof is open full screen.
    @State private var inspecting: CartItem?

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
                    .onComplete { event in
                        // Record first: emptying the bag without an order row loses the
                        // purchase — Etch has no account, the phone is the record.
                        CheckoutCompletion.recordBag(event, items: cart.items)
                        cart.clear()
                        checkout = nil
                        Task { await refresh() }
                    }
                    .onFail { _ in checkout = nil }
                    .interactiveDismissDisabled()
            }
            .fullScreenCover(item: $inspecting) { item in ProofInspector(item: item) }
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

    /// One piece waiting to be ordered — shown as the object it will arrive as, not as a receipt
    /// line. The proof is a small copy of the exact file that was uploaded for print, dressed in
    /// the product it was added as: the moulding for a framed piece, the bare sheet for fine art,
    /// the cover for a book. What you see here is what you are paying for.
    private func cartRow(_ item: CartItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button { inspecting = item } label: {
                CartProofView(item: item)
                    .frame(width: 76)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Inspect the proof")
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.etch(.headline))
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The proof travels with the line — approved before the piece could be added,
                // and inspectable right up to checkout.
                Button { inspecting = item } label: {
                    Label("View proof", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(item.price)
                    .font(.etch(.subheadline, weight: .semibold))
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
        .padding(.vertical, 6)
    }

    /// Subtotal and the two ways out. The wallet buttons take the whole bag, so one tap pays for
    /// three pieces exactly as it pays for one — the accelerated checkout works on a cart, and a
    /// cart with three lines is still a cart.
    @ViewBuilder private var checkoutBlock: some View {
        VStack(spacing: 12) {
            HStack {
                Text(cart.count == 1 ? "1 piece" : "\(cart.count) pieces")
                    .font(.etch(.subheadline))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(cart.subtotal)
                    .font(.etch(.title3, weight: .semibold))
                    .monospacedDigit()
            }

            if let url = cart.checkoutURL {
                if ApplePayConfig.isConfigured, let id = cart.cartID {
                    AcceleratedCheckoutButtons(cartID: id)
                        .wallets([.applePay, .shopPay])
                        .cornerRadius(14)
                        .onComplete { event in
                            CheckoutCompletion.recordBag(event, items: cart.items)
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
                        .font(.etch(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(ApplePayConfig.isConfigured ? Theme.accent : .white)
                        .background(ApplePayConfig.isConfigured ? Theme.accent.opacity(0.12) : Theme.accent,
                                    in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            DeliveryNote()
                .frame(maxWidth: .infinity)

            Text(EtchConfig.current.ordering.delivery?.isEmpty == false
                 ? "Any duties are calculated at checkout. Every piece is printed to order."
                 : "Shipping and any duties are calculated at checkout. Every piece is printed to order.")
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
                    .font(.etch(.headline))
                Spacer(minLength: 8)
                Text(order.sizeLabel)
                    .font(.etch(.subheadline))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(order.status.label)
                    .font(.etch(size: 11, weight: .semibold))
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
                        .font(.etch(.footnote, weight: .semibold))
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

/// The proof, full screen: the exact file that was uploaded for print, zoomable, named as the
/// piece it belongs to. It was approved before the line could be added, and the badge says so —
/// what the bag shows is what the lab receives, not a preview that could drift from it.
private struct ProofInspector: View {
    let item: CartItem

    var body: some View {
        ZStack(alignment: .bottom) {
            ArtworkPreviewView(image: ProofStore.image(for: item.assetID))

            VStack(spacing: 8) {
                Text(item.title)
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Label("Proof approved — this is what gets printed", systemImage: "checkmark.seal.fill")
                    .font(.etch(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.18), in: .capsule)
            }
            .padding(.bottom, 28)
        }
    }
}

/// A cart line's proof, dressed as its product.
///
/// The image is the uploaded print file, downsampled — the lab's input, not a preview that could
/// drift from it. The dressing comes from the line's product handle: framed pieces wear the
/// drawn moulding in their chosen finish, the hanger gets its timber strips, everything else is
/// the sheet itself with a hairline and a shadow. A line without a stored proof (added before
/// proofs existed, or a generation failure) shows a quiet placeholder rather than pretending.
private struct CartProofView: View {
    let item: CartItem
    @State private var proof: UIImage?

    var body: some View {
        Group {
            if let proof {
                dressed(Image(uiImage: proof).resizable().aspectRatio(contentMode: .fit))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.10))
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .task(id: item.assetID) { proof = ProofStore.image(for: item.assetID) }
    }

    @ViewBuilder
    private func dressed(_ art: some View) -> some View {
        switch item.productHandle {
        case PrintProduct.framed.shopifyHandle,
             MedalFrameCatalog.shopifyHandle,
             MultiPhotoFrameCatalog.shopifyHandle:
            FramedPrintMockup(
                moulding: mouldingColor,
                hasGrain: grain,
                mouldingWidth: 5,
                showsGlazing: true
            ) { art }
        case PrintProduct.hanger.shopifyHandle:
            VStack(spacing: 0) {
                Rectangle().fill(mouldingColor).frame(height: 4)
                art
                Rectangle().fill(mouldingColor).frame(height: 4)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        default:
            art
                .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .compositingGroup()
                .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
        }
    }

    private var mouldingColor: Color {
        let finish = (item.finish ?? "").lowercased()
        // The medal frame and the photo wall name their finishes in the catalog's own strings
        // ("dark grey", "gold"), which the poster range's FrameFinish never carries.
        if item.productHandle == MedalFrameCatalog.shopifyHandle
            || item.productHandle == MultiPhotoFrameCatalog.shopifyHandle {
            return Color(hex: MedalFrameCatalog.mouldingHex(finish)) ?? .black
        }
        if let match = FrameFinish.allCases.first(where: { $0.prodigiAttribute == finish }) {
            return Color(hex: match.mouldingHex) ?? .black
        }
        return Color(hex: FrameFinish.black.mouldingHex) ?? .black
    }

    private var grain: Bool {
        let finish = (item.finish ?? "").lowercased()
        return finish.contains("natural") || finish.contains("brown") || finish.contains("oak")
    }
}
