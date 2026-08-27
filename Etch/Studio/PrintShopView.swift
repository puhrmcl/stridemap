import SwiftUI
import ShopifyCheckoutSheetKit
import ShopifyAcceleratedCheckouts

/// Browse Etch Studio's print formats and order one.
///
/// The audit's finding was that the old flow never showed the artwork — it presented an SF Symbol,
/// a product name and a material string, with the user's own poster (the entire emotional payload)
/// absent from the buying flow. This version leads with the piece itself, in a frame, at the size
/// being considered. The frame preview is what converts.
///
/// Ordering runs the P4 pipeline: render at print resolution → freeze into the fulfilment
/// worker → Shopify checkout in-sheet (Checkout Sheet Kit). The shop can only transact when it
/// was opened from a piece (it has the render recipe); from Studio home it browses formats.
struct PrintShopView: View {
    /// The name of the piece being printed.
    var subjectTitle: String?
    /// The rendered artwork. Nil when the shop is opened from the Studio home (browsing formats
    /// rather than ordering a specific piece), in which case the mockup shows a placeholder sheet.
    var artwork: UIImage?
    /// The full render recipe — required to produce the print file at order time.
    var renderRequest: StudioRenderer.Request?
    /// Stable id of the creation being printed (saved poster id, or the run id).
    var creationID: String?
    /// The activity behind the piece, for the on-device order record.
    var runID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var product: PrintProduct = .framed
    @State private var size: PrintSize
    @State private var finish: FrameFinish = .natural
    @State private var hangerFinish: HangerFinish = .natural

    /// The finish as the order path takes it — one value, so a framed order can never carry a
    /// wood colour or the other way round.
    private var selectedFinish: PrintFinish {
        switch product {
        case .framed: return .frame(finish)
        case .hanger: return .hanger(hangerFinish)
        case .print:  return .none
        }
    }

    /// Full-screen look at the product — tap the mockup to inspect the piece in its frame.
    @State private var showProductPreview = false

    /// Non-nil while the pre-checkout pipeline runs; drives the button's progress narration.
    @State private var orderPhase: PrintOrderService.Phase?
    @State private var orderError: String?
    @State private var checkout: CheckoutTarget?

    private struct CheckoutTarget: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// The cart the wallet buttons check out, once the print file is uploaded and a cart exists.
    ///
    /// Apple Pay can't be offered before this point, and that ordering is the whole design: the
    /// artwork has to be rendered and frozen into the fulfilment worker *before* money moves, or
    /// a paid order could exist with no file behind it. So the first tap prepares the order and
    /// the second is the payment — which is still one tap on the price, one on Apple Pay, and no
    /// form at all.
    @State private var preparedCart: ShopifyStorefront.Cart?

    init(subjectTitle: String?, artwork: UIImage? = nil,
         renderRequest: StudioRenderer.Request? = nil,
         creationID: String? = nil, runID: UUID? = nil) {
        self.subjectTitle = subjectTitle
        self.artwork = artwork
        self.renderRequest = renderRequest
        self.creationID = creationID
        self.runID = runID
        // Open on the middle framed size — the one most people buy.
        _size = State(initialValue: PrintProduct.framed.sizes[1])
    }

    private var sizes: [PrintSize] { product.sizes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    mockup
                    productPicker
                    sizePicker
                    if product.takesFrameFinish { finishPicker }
                    if product.takesHangerFinish { hangerPicker }
                    orderPanel
                }
                .padding(20)
            }
            .background(Theme.Palette.bone.opacity(0.35).ignoresSafeArea())
            .navigationTitle("Prints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onChange(of: product) { _, new in
                // Keep the nearest size when switching products rather than resetting to the top.
                size = new.sizes.min { abs($0.width - size.width) < abs($1.width - size.width) } ?? new.sizes[0]
                invalidatePreparedCart()
            }
            .onChange(of: size) { invalidatePreparedCart() }
            .onChange(of: finish) { invalidatePreparedCart() }
            .onChange(of: hangerFinish) { invalidatePreparedCart() }
            .sheet(item: $checkout) { target in
                CheckoutSheet(checkout: target.url)
                    .title("Checkout")
                    .colorScheme(.automatic)
                    .tintColor(UIColor(Theme.accent))
                    .onComplete { event in recordOrder(event) }
                    .onCancel { checkout = nil }
                    .onFail { error in
                        checkout = nil
                        orderError = error.localizedDescription
                    }
                    .interactiveDismissDisabled()  // mid-payment swipe-away protection
            }
            .alert("Couldn't start the order", isPresented: .init(
                get: { orderError != nil }, set: { if !$0 { orderError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(orderError ?? "")
            }
        }
    }

    // MARK: Ordering

    /// Ordering also honours the served kill switch, so a fulfilment problem can be contained
    /// without an App Store release.
    private var canOrderHere: Bool {
        renderRequest != nil && PrintOrderService.isConfigured && EtchConfig.current.ordering.enabled
    }

    /// Whether this build can offer the native wallet buttons at all. When it can't — no
    /// merchant identifier, or no storefront credentials — the panel keeps the single "Order"
    /// button that opens the hosted checkout, which is the behaviour it has today, unchanged.
    private var offersWallets: Bool { ApplePayConfig.isConfigured }

    /// Renders, uploads and creates the cart. `openSheet` decides what happens next: the hosted
    /// checkout opens immediately, or the wallet buttons appear over the prepared cart.
    private func beginOrder(openSheet: Bool = true) {
        guard let renderRequest, orderPhase == nil, renderRequest.edition.printReady else { return }
        let creation = creationID ?? runID?.uuidString ?? UUID().uuidString
        Task {
            do {
                let cart = try await PrintOrderService.beginCheckout(
                    request: renderRequest, creationID: creation,
                    product: product, size: size,
                    finish: selectedFinish,
                    onPhase: { orderPhase = $0 }
                )
                orderPhase = nil
                preparedCart = cart
                if openSheet { checkout = CheckoutTarget(url: cart.checkoutURL) }
            } catch {
                orderPhase = nil
                orderError = error.localizedDescription
            }
        }
    }

    /// A prepared cart is only valid for what was configured when it was made — change the size,
    /// the format or the finish and the uploaded file no longer matches the line. Dropping it
    /// sends the next order back through render-and-upload rather than paying for the wrong thing
    /// in one tap, which is the failure a fast checkout makes easy.
    private func invalidatePreparedCart() {
        preparedCart = nil
    }

    /// Shopify reported payment complete: keep the on-device record the worker will update.
    private func recordOrder(_ event: CheckoutCompletedEvent) {
        // The order id arrives as a gid (`gid://shopify/OrderIdentity/123`); the worker keys
        // orders by the trailing numeric id.
        let shopifyID = event.orderDetails.id.components(separatedBy: "/").last ?? event.orderDetails.id
        OrderStore.shared.record(PrintOrder(
            id: UUID(), shopifyOrderID: shopifyID,
            runID: runID ?? UUID(),
            sku: size.prodigiSKU, productName: product.name, sizeLabel: size.label,
            status: .submitted, placedAt: .now
        ))
        checkout = nil
        dismiss()
    }

    // MARK: The object

    /// The piece as a physical object: the artwork in a frame (or as a bare sheet), on a neutral
    /// wall, sized relative to the other options so the size choice is felt rather than read.
    private var mockup: some View {
        VStack(spacing: 14) {
            Button {
                if artwork != nil { showProductPreview = true }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.93), Color(white: 0.87)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    framedPiece
                        .padding(.vertical, 26)
                }
                .frame(height: 320)
                .clipShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View full screen")
            .fullScreenCover(isPresented: $showProductPreview) {
                ArtworkPreviewView(image: productPreviewImage())
            }

            if let subjectTitle {
                Text(subjectTitle)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            Text("\(product.name) · \(size.label)")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var framedPiece: some View {
        // Scale the piece within the mockup by its real size, so 24×36 visibly dwarfs 12×18.
        let largest = CGFloat(product.sizes.map(\.height).max() ?? size.height)
        let relative = CGFloat(size.height) / largest
        let sheet = Group {
            if let artwork {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit)
            } else {
                Rectangle().fill(Theme.Palette.bone)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: "mountain.2")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.Palette.ink.opacity(0.18))
                    }
            }
        }

        Group {
            switch product {
            case .framed:
                // Full-bleed in the moulding — the verified product (Classic Frame, no mount) has
                // no mat, so the mockup doesn't draw one. Honest previews only.
                sheet
                    .padding(9)                                    // moulding
                    .background(Color(hex: finish.mouldingHex) ?? .black)
                    .shadow(color: .black.opacity(0.30), radius: 16, y: 10)
            case .hanger:
                // The wood sits *over* the print, so the strips are drawn on top of the sheet and
                // the artwork behind them is inset by what they cover — the same reserve the
                // uploaded file carries. A mockup that drew the wood outside the paper would
                // promise a bigger image than ships.
                sheet
                    .padding(.vertical, hangerStripHeight)
                    .background(Theme.Palette.bone)
                    .overlay(alignment: .top) { hangerStrip }
                    .overlay(alignment: .bottom) { hangerStrip }
                    .shadow(color: .black.opacity(0.24), radius: 14, y: 9)
            case .print:
                sheet
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
            }
        }
        .scaleEffect(0.55 + 0.45 * relative, anchor: .center)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: size)
        .animation(.easeInOut(duration: 0.2), value: finish)
        .animation(.easeInOut(duration: 0.2), value: hangerFinish)
    }

    /// The wood strip, drawn at its true proportion of the sheet: 15mm of a 36″ print is 1.6% of
    /// the height, and the mockup is 320pt tall, so it is genuinely a thin band rather than the
    /// chunky batten a decorative drawing would give it.
    private var hangerStripHeight: CGFloat {
        let sheetInches = CGFloat(size.height)
        let coverInches = PosterHangerCatalog.hangerCoverMM / 25.4
        return max(3, 250 * (coverInches / max(sheetInches, 1)))
    }

    private var hangerStrip: some View {
        Rectangle()
            .fill(Color(hex: hangerFinish.woodHex) ?? .brown)
            .frame(height: hangerStripHeight)
            .overlay(Rectangle().fill(.black.opacity(0.12)).frame(height: 0.5), alignment: .bottom)
    }

    /// The product as one flat image for the full-screen viewer: the artwork inside its chosen
    /// moulding for a framed print, or the bare sheet for fine art. Composed at tap time from the
    /// current finish, so what's inspected is exactly what's configured.
    private func productPreviewImage() -> UIImage? {
        guard let artwork else { return nil }

        if product == .hanger {
            // The same compositing the order path does, at preview scale: artwork inside the
            // band-free box on its own ground, with the wood drawn over the bands. Inspecting the
            // product should show the covered strips, not a bare sheet.
            let sheetHeight = artwork.size.width * CGFloat(size.height) / CGFloat(size.width)
            let sheet = CGSize(width: artwork.size.width, height: sheetHeight)
            guard let composed = PosterHangerCatalog.composite(
                artwork: artwork, sheetPixels: sheet, ground: UIColor(Theme.Palette.bone)
            ) else { return artwork }
            let band = min(PosterHangerCatalog.hangerCoverMM / 25.4 / CGFloat(size.height),
                           0.1) * sheetHeight
            let format = UIGraphicsImageRendererFormat()
            format.opaque = true
            format.scale = 1
            return UIGraphicsImageRenderer(size: sheet, format: format).image { context in
                composed.draw(in: CGRect(origin: .zero, size: sheet))
                UIColor(Color(hex: hangerFinish.woodHex) ?? .brown).setFill()
                context.fill(CGRect(x: 0, y: 0, width: sheet.width, height: band))
                context.fill(CGRect(x: 0, y: sheet.height - band, width: sheet.width, height: band))
            }
        }

        guard product == .framed else { return artwork }

        // Moulding proportion matches the real Classic frame (~4% of the long edge), drawn in the
        // chosen finish with a shadow-line where the moulding lips over the sheet.
        let moulding = max(artwork.size.width, artwork.size.height) * 0.04
        let canvas = CGSize(width: artwork.size.width + moulding * 2,
                            height: artwork.size.height + moulding * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = artwork.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { context in
            let mouldingColor = UIColor(Color(hex: finish.mouldingHex) ?? .black)
            mouldingColor.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))

            let sheet = CGRect(x: moulding, y: moulding,
                               width: artwork.size.width, height: artwork.size.height)
            artwork.draw(in: sheet)

            // The rebate shadow: a thin dark line where the frame overlaps the print.
            UIColor.black.withAlphaComponent(0.28).setStroke()
            let edge = UIBezierPath(rect: sheet)
            edge.lineWidth = max(1, moulding * 0.08)
            edge.stroke()
        }
    }

    // MARK: Choices

    private var productPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Format")
            ForEach(PrintProduct.offered) { p in
                Button { product = p } label: {
                    HStack(spacing: 14) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(product == p ? .white : Theme.accent)
                            .frame(width: 44, height: 44)
                            .background(product == p ? Theme.accent : Theme.accent.opacity(0.10),
                                        in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(.headline, design: .rounded))
                            Text(p.tagline)
                                .font(.footnote).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        if product == p {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(product == p ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Size")
            HStack(spacing: 10) {
                ForEach(sizes) { s in
                    Button { size = s } label: {
                        VStack(spacing: 3) {
                            Text(s.label)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text(s.price)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            size == s ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.05),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(size == s ? Theme.accent : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var finishPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Frame")
            HStack(spacing: 10) {
                ForEach(FrameFinish.allCases) { f in
                    Button { finish = f } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: f.mouldingHex) ?? .black)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                            Text(f.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            finish == f ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.04),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(finish == f ? Theme.accent : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hangerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Wood")
            HStack(spacing: 10) {
                ForEach(HangerFinish.allCases) { h in
                    Button { hangerFinish = h } label: {
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(Color(hex: h.woodHex) ?? .brown)
                                .frame(width: 34, height: 12)
                                .overlay(Capsule().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                                .frame(height: 30)
                            Text(h.name).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            hangerFinish == h ? Theme.accent.opacity(0.12) : Color.primary.opacity(0.04),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(hangerFinish == h ? Theme.accent : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("The hangers cover 15mm of the print at the top and bottom, so the piece is composed with that margin kept clear.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Order

    private var orderPanel: some View {
        VStack(spacing: 12) {
            // Served, dated copy — the Christmas shipping deadline being the case that matters,
            // since the date moves and a stale one is worse than none at all.
            if let seasonal = EtchConfig.current.seasonal, seasonal.isActive {
                Label(seasonal.message, systemImage: "shippingbox")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: 10))
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(size.price)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text(size.geometry.summary)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            Text(product.material)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canOrderHere {
                if let edition = renderRequest?.edition, !edition.printReady {
                    // Apple-snapshot editions are licensed for screens, not merchandise. Honest
                    // gate rather than a failed order; lifts when our own cartography lands.
                    unavailableNote("This style is coming to print",
                                    detail: "Map styles are being remade with our own cartography for print. Contour, paper, and photo styles are ready to order today.")
                } else if size.deviceRenderable {
                    // A prepared order pays in one tap. Until one exists the print file has to be
                    // made and frozen first, because a paid order with no artwork behind it is
                    // the one failure this pipeline must never produce — so the wallet buttons
                    // appear after preparation rather than instead of it.
                    if let preparedCart, offersWallets {
                        walletButtons(cart: preparedCart)
                        Button { checkout = CheckoutTarget(url: preparedCart.checkoutURL) } label: {
                            Text("Other ways to pay")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(Theme.accent)
                                .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: { beginOrder(openSheet: !offersWallets) }) {
                            Group {
                                if let orderPhase {
                                    HStack(spacing: 10) {
                                        ProgressView().tint(.white)
                                        Text(orderPhase.label)
                                    }
                                } else {
                                    Label(offersWallets ? "Continue · \(size.price)"
                                                        : "Order · \(size.price)",
                                          systemImage: "bag")
                                }
                            }
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: .rect(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(orderPhase != nil)
                    }

                    Text("Secure checkout with Apple Pay or card. Printed to order and shipped to your door.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else {
                    unavailableNote("This size is coming soon",
                                    detail: "\(size.label) prints need our studio renderer — it's on the way. The other sizes are ready to order today.")
                }
            } else if PrintOrderService.isConfigured && EtchConfig.current.ordering.enabled {
                unavailableNote("Order from a piece",
                                detail: "Open one of your pieces in Studio and tap Prints there — your own artwork is what gets printed.")
            } else {
                // Copy is served, so the reason ordering is closed can be stated accurately
                // (opening soon / paused / back in the new year) without a release.
                unavailableNote(EtchConfig.current.ordering.closedTitle,
                                detail: EtchConfig.current.ordering.closedDetail)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    /// Apple Pay and Shop Pay over the prepared cart.
    ///
    /// These are native buttons, not a web checkout: the buyer confirms with Face ID against the
    /// card and address Apple already holds, and no form is ever shown. The order is the same
    /// cart the sheet would have opened, carrying the same hidden line attributes, so fulfilment
    /// cannot tell the two apart. Apple Pay leads because it is the one most buyers have.
    private func walletButtons(cart: ShopifyStorefront.Cart) -> some View {
        AcceleratedCheckoutButtons(cartID: cart.id)
            .wallets([.applePay, .shopPay])
            .cornerRadius(14)
            .onComplete { event in recordOrder(event) }
            .onFail { error in orderError = error.localizedDescription }
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

    private func unavailableNote(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: "clock")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 14))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
