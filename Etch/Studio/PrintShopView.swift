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

    /// The medal display frame, configured alongside the poster formats.
    ///
    /// It sits beside `product` rather than inside `PrintProduct` because it breaks every
    /// assumption that enum encodes: one size instead of three, a 2397 × 3000 aperture instead
    /// of 2:3, and two colour attributes instead of one finish. What matters is that the *shop*
    /// treats it as one more format — the whole point being that a piece open in the editor can
    /// move between a sheet, a frame and the medal frame without leaving the buying flow.
    @State private var isMedal = false
    @State private var medalFrameColour = "black"
    @State private var medalMountColour = "Black"

    @State private var isAddingToBag = false
    /// Drives the confirmation, so adding says something happened rather than looking inert.
    @State private var addedToBag = false

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

    /// Whether the product-details panel is open. Starts open; see `specs`.
    @State private var specsExpanded = true

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
            // Anchored the same way Studio home is, and for the same reason: the page is now
            // taller than a screen, and CI can only photograph a screenful at a time. Inert
            // without the environment variable.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 26) {
                        titleBlock.id("top")
                        mockup
                        productPicker.id("options")
                        if isMedal {
                            medalColourPicker("Frame", options: MedalFrameCatalog.frameColours,
                                              selection: $medalFrameColour,
                                              hex: MedalFrameCatalog.mouldingHex)
                            medalColourPicker("Mount", options: MedalFrameCatalog.mountColours,
                                              selection: $medalMountColour,
                                              hex: MedalFrameCatalog.mountHex)
                        } else {
                            sizePicker
                            if product.takesFrameFinish { finishPicker }
                            if product.takesHangerFinish { hangerPicker }
                        }
                        orderPanel.id("order")
                        specs.id("details")
                        alsoLike.id("more")
                    }
                    .padding(20)
                }
                .onAppear {
                    guard let anchor = ProcessInfo.processInfo
                        .environment["ETCH_PREVIEW_SCROLL"], !anchor.isEmpty else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                }
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
            .onChange(of: isMedal) { invalidatePreparedCart() }
            .onChange(of: medalFrameColour) { invalidatePreparedCart() }
            .onChange(of: medalMountColour) { invalidatePreparedCart() }
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
            .overlay(alignment: .top) {
                if addedToBag {
                    Label("Added to your bag", systemImage: "checkmark.circle.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.accent, in: .capsule)
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(1.8))
                            withAnimation(.easeInOut(duration: 0.3)) { addedToBag = false }
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: addedToBag)
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
                let cart: ShopifyStorefront.Cart
                if isMedal {
                    // The medal path: the panel re-renders to the frame's own 2397 × 3000
                    // aperture, and the order carries both of Prodigi's colour attributes —
                    // the same pipeline the medal screen runs, from inside the shop.
                    orderPhase = .rendering
                    var printRequest = renderRequest
                    let geometry = PrintGeometry(trimWidth: 7.99, trimHeight: 10.0)
                    printRequest.printAspect = geometry.aspect
                    printRequest.outputSize = .poster
                    let fileURL = try await StudioRenderer.printFile(for: printRequest,
                                                                     geometry: geometry)
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    cart = try await PrintOrderService.checkout(
                        fileAt: fileURL,
                        pixels: geometry.trimPixels,
                        creationID: "medal-\(creation)",
                        shopifySKU: MedalFrameCatalog.sku,
                        prodigiSKU: MedalFrameCatalog.sku,
                        productHandle: MedalFrameCatalog.shopifyHandle,
                        finishAttribute: medalFrameColour,
                        mountAttribute: medalMountColour,
                        onPhase: { orderPhase = $0 }
                    )
                } else {
                    cart = try await PrintOrderService.beginCheckout(
                        request: renderRequest, creationID: creation,
                        product: product, size: size,
                        finish: selectedFinish,
                        onPhase: { orderPhase = $0 }
                    )
                }
                orderPhase = nil
                preparedCart = cart
                if openSheet { checkout = CheckoutTarget(url: cart.checkoutURL) }
            } catch {
                orderPhase = nil
                orderError = error.localizedDescription
            }
        }
    }

    /// Renders and uploads this configuration, then parks it in the bag instead of checking out.
    private func addToBag() {
        guard let renderRequest, !isAddingToBag, renderRequest.edition.printReady else { return }
        let creation = creationID ?? runID?.uuidString ?? UUID().uuidString
        isAddingToBag = true
        Task {
            defer { isAddingToBag = false }
            do {
                if isMedal {
                    let geometry = PrintGeometry(trimWidth: 7.99, trimHeight: 10.0)
                    var printRequest = renderRequest
                    printRequest.printAspect = geometry.aspect
                    printRequest.outputSize = .poster
                    let fileURL = try await StudioRenderer.printFile(for: printRequest,
                                                                     geometry: geometry)
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    try await PrintOrderService.addToBag(
                        fileAt: fileURL, pixels: geometry.trimPixels,
                        creationID: "medal-\(creation)",
                        shopifySKU: MedalFrameCatalog.sku, prodigiSKU: MedalFrameCatalog.sku,
                        productHandle: MedalFrameCatalog.shopifyHandle,
                        finishAttribute: medalFrameColour, mountAttribute: medalMountColour,
                        title: subjectTitle ?? "Medal Frame",
                        detail: "Medal Frame · \(medalFrameColour.capitalized)",
                        priceCents: EtchConfig.current.prices.medalFrameCents ?? 24900,
                        onPhase: { orderPhase = $0 }
                    )
                } else {
                    let geometry = size.geometry
                    var printRequest = renderRequest
                    printRequest.printAspect = geometry.aspect
                    printRequest.outputSize = .poster
                    var reserve: CGFloat = 0
                    if case .hanger = selectedFinish {
                        reserve = (PosterHangerCatalog.hangerCoverMM / 25.4) / CGFloat(size.height)
                    }
                    let fileURL = try await StudioRenderer.printFile(
                        for: printRequest, geometry: geometry, reserveFraction: reserve
                    )
                    defer { try? FileManager.default.removeItem(at: fileURL) }
                    try await PrintOrderService.addToBag(
                        fileAt: fileURL, pixels: geometry.trimPixels, creationID: creation,
                        shopifySKU: size.shopifySKU(finish: selectedFinish),
                        prodigiSKU: size.prodigiSKU,
                        productHandle: product.shopifyHandle,
                        finishAttribute: selectedFinish.prodigiAttribute,
                        title: subjectTitle ?? product.name,
                        detail: configurationLine,
                        priceCents: size.resolvedPriceCents,
                        onPhase: { orderPhase = $0 }
                    )
                }
                orderPhase = nil
                addedToBag = true
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
            sku: isMedal ? MedalFrameCatalog.sku : size.prodigiSKU,
            productName: isMedal ? "Medal Frame" : product.name,
            sizeLabel: isMedal ? "12 × 16″" : size.label,
            status: .submitted, placedAt: .now
        ))
        checkout = nil
        dismiss()
    }

    // MARK: The title block

    /// The configured product, named and priced, *above* the image.
    ///
    /// This is the shape of every product page that sells well, and the one this screen didn't
    /// have: the old layout showed the mockup first, a caption under it, and the price down in
    /// the order panel below three pickers — so the price was below the fold and the thing being
    /// priced had to be reconstructed from three separate controls. A buyer deciding whether to
    /// keep reading is deciding on the name and the number, and both were somewhere else.
    ///
    /// The subtitle names the *whole* configuration — format, size and finish — the way a
    /// hardware page titles a variant rather than a model. It changes as the pickers change, so
    /// the top of the page and the bottom can never disagree about what is in the cart.
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subjectTitle ?? (isMedal ? "Medal Frame" : product.name))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text(configurationLine)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            Text(isMedal ? MedalFrameCatalog.price : size.price)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()

            if let delivery = EtchConfig.current.ordering.delivery, !delivery.isEmpty {
                Label(delivery, systemImage: "shippingbox")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: size)
    }

    /// "Framed Print · 18 × 24″ · Natural" — every choice the order carries, in one line.
    ///
    /// Browsing without a piece leaves the format standing in as the title, so it drops out of
    /// this line rather than being printed twice in a row.
    private var configurationLine: String {
        if isMedal {
            var parts = subjectTitle == nil ? [] : ["Medal Frame"]
            parts.append("12 × 16″")
            parts.append("\(medalFrameColour.capitalized) · \(medalMountColour) mount")
            return parts.joined(separator: " · ")
        }
        var parts = subjectTitle == nil ? [size.label] : [product.name, size.label]
        switch product {
        case .framed: parts.append(finish.name)
        case .hanger: parts.append(hangerFinish.name)
        case .print:  break
        }
        return parts.joined(separator: " · ")
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
                    MockupWall()
                    framedPiece
                        .padding(.vertical, 30)
                }
                .frame(height: 320)
                .clipShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View full screen")
            .fullScreenCover(isPresented: $showProductPreview) {
                ArtworkPreviewView(image: productPreviewImage())
            }

            // No caption here any more — the title block above the image now names the piece and
            // its whole configuration, and repeating it under the mockup put the same three
            // facts on screen twice.
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
            if isMedal {
                // The medal display frame: the aperture drawn empty — what hangs there is the
                // buyer's own medal — and the piece as the printed panel beside it, behind the
                // snow-white top mount. The same honest mockup the medal screen draws.
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: MedalFrameCatalog.mountHex(medalMountColour)) ?? .black)
                        .frame(width: 78, height: 106)
                        .overlay {
                            Image(systemName: "medal")
                                .font(.system(size: 23, weight: .light))
                                .foregroundStyle(.white.opacity(0.22))
                        }
                    Group {
                        if let artwork {
                            Image(uiImage: artwork).resizable().scaledToFill()
                        } else {
                            Rectangle().fill(Theme.Palette.bone)
                        }
                    }
                    .frame(width: 78, height: 106)
                    .clipped()
                }
                .padding(15)
                .background(Color(white: 0.97))                    // the snow-white top mount
                .padding(12)                                       // moulding
                .background(Color(hex: MedalFrameCatalog.mouldingHex(medalFrameColour)) ?? .black)
                .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            } else {
            switch product {
            case .framed:
                // Full-bleed in the moulding — the verified product (Classic Frame, no mount) has
                // no mat, so the mockup doesn't draw one. Honest previews only: the depth, grain
                // and glazing below are all things this frame has; a mat is not.
                FramedPrintMockup(
                    moulding: Color(hex: finish.mouldingHex) ?? .black,
                    hasGrain: finish == .natural,
                    mouldingWidth: 11
                ) { sheet }
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
                // A loose sheet, unframed and unmounted. Two shadows for the same reason the
                // frame has two: a single soft one reads as a sticker on the wall.
                sheet
                    .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 11)
            }
            }
        }
        .scaleEffect(isMedal ? 1.0 : 0.55 + 0.45 * relative, anchor: .center)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: size)
        .animation(.easeInOut(duration: 0.2), value: finish)
        .animation(.easeInOut(duration: 0.2), value: hangerFinish)
        .animation(.easeInOut(duration: 0.2), value: medalFrameColour)
        .animation(.easeInOut(duration: 0.2), value: medalMountColour)
        .animation(.easeInOut(duration: 0.25), value: isMedal)
    }

    /// The wood strip, drawn at its true proportion of the sheet: 15mm of a 36″ print is 1.6% of
    /// the height, and the mockup is 320pt tall, so it is genuinely a thin band rather than the
    /// chunky batten a decorative drawing would give it.
    private var hangerStripHeight: CGFloat {
        let sheetInches = CGFloat(size.height)
        let coverInches = PosterHangerCatalog.hangerCoverMM / 25.4
        return max(3, 250 * (coverInches / max(sheetInches, 1)))
    }

    /// The magnetic batten. A solid timber has a lit face and a shaded one like any other, and the
    /// edge where it meets the paper casts a line — without those it reads as a printed band rather
    /// than a piece of wood clamped over the sheet.
    private var hangerStrip: some View {
        let wood = Color(hex: hangerFinish.woodHex) ?? .brown
        return LinearGradient(
            stops: [
                .init(color: wood.mixed(with: .white, amount: 0.16), location: 0),
                .init(color: wood, location: 0.55),
                .init(color: wood.mixed(with: .black, amount: 0.18), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: hangerStripHeight)
        .overlay(Rectangle().fill(.black.opacity(0.22)).frame(height: 0.75), alignment: .bottom)
        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
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
            sectionLabel("Format", value: isMedal ? "Medal Frame" : product.name)
            ForEach(PrintProduct.offered) { p in
                formatCard(name: p.name, tagline: p.tagline, symbol: p.symbol,
                           isSelected: !isMedal && product == p) {
                    isMedal = false
                    product = p
                }
            }
            // The medal frame sits in the same list as the paper formats — the request this
            // answers was being taken from the medal screen into an editor whose only exit
            // sold posters. One list, every format, switchable mid-edit.
            if MedalFrameCatalog.isAvailable {
                formatCard(name: "Medal Frame",
                           tagline: "Your medal behind its aperture, this piece printed beside it.",
                           symbol: "medal", isSelected: isMedal) {
                    isMedal = true
                }
            }
        }
    }

    private func formatCard(name: String, tagline: String, symbol: String,
                            isSelected: Bool, select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Theme.accent : Theme.accent.opacity(0.10),
                                in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(.headline, design: .rounded))
                    Text(tagline)
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    /// The medal frame's two colour rows — the moulding and the mount board — in the shop's own
    /// swatch style.
    private func medalColourPicker(_ label: String, options: [String],
                                   selection: Binding<String>,
                                   hex: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label, value: selection.wrappedValue.capitalized)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(options, id: \.self) { option in
                        Button { selection.wrappedValue = option } label: {
                            Circle()
                                .fill(Color(hex: hex(option)) ?? .gray)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                                .padding(3)
                                .overlay {
                                    Circle().strokeBorder(
                                        selection.wrappedValue == option ? Theme.accent : .clear,
                                        lineWidth: 2
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Size", value: size.label)
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
            sectionLabel("Frame", value: finish.name)
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
            sectionLabel("Wood", value: hangerFinish.name)
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
            // The price and the material line used to live here. Both moved: the price to the
            // title block above the image, where the decision is actually made, and the material
            // into the specs disclosure below, where a buyer who wants it can find it without it
            // sitting between them and the button.

            if canOrderHere {
                if let edition = renderRequest?.edition, !edition.printReady {
                    // Apple-snapshot editions are licensed for screens, not merchandise. Honest
                    // gate rather than a failed order; lifts when our own cartography lands.
                    unavailableNote("This style is coming to print",
                                    detail: "Map styles are being remade with our own cartography for print. Contour, paper, and photo styles are ready to order today.")
                } else if isMedal || size.deviceRenderable {
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
                                    let price = isMedal ? MedalFrameCatalog.price : size.price
                                    Label(offersWallets ? "Continue · \(price)"
                                                        : "Order · \(price)",
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

                    // Buying one piece stays one tap; assembling several is the other button.
                    // Both render and upload before anything is charged, so a bagged line and a
                    // bought line are the same thing to fulfilment.
                    if renderRequest != nil {
                        Button(action: addToBag) {
                            Group {
                                if isAddingToBag {
                                    HStack(spacing: 8) {
                                        ProgressView().controlSize(.small)
                                        Text("Adding…")
                                    }
                                } else {
                                    Label("Add to Bag", systemImage: "bag.badge.plus")
                                }
                            }
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(orderPhase != nil || isAddingToBag)
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

    /// An option group's heading, carrying what is currently chosen.
    ///
    /// "Frame — Natural" rather than "FRAME". The selection is already drawn in the row below as
    /// a ring around a swatch, but a ring is a weak signal on a page with four groups of them,
    /// and it is unreadable to anyone who isn't looking straight at it. Naming the value in the
    /// heading means the page can be understood from the headings alone, which is also what makes
    /// it legible to VoiceOver in one pass.
    private func sectionLabel(_ text: String, value: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            if let value {
                Text("—")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: The detail below the fold

    /// What the object is made of and what turns up in the box, folded away.
    ///
    /// A product page has two readers: one who has already decided and wants the button, and one
    /// who needs to know the paper weight before spending $139. Printing the specs inline serves
    /// the second and obstructs the first; omitting them serves the first and loses the second.
    /// Disclosure serves both, and it is where the material line went when it came out from
    /// between the pickers and the button.
    private var specs: some View {
        VStack(spacing: 0) {
            // Open by default, the way the reference's "Product Information" is. It sits *below*
            // the order button, so an expanded panel costs the decided buyer nothing and saves
            // the undecided one a tap — the tap being the only thing standing between them and
            // the paper weight they came to check.
            DisclosureGroup(isExpanded: $specsExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    if isMedal {
                        specRow("Overview", "Your medal behind a pre-cut aperture, with this piece printed on the panel beside it. Made in the UK.")
                        specRow("Materials", "240gsm lustre print · classic wood frame · snow-white top mount · Perspex glaze")
                        specRow("In the box", "One assembled frame, glazed, with the printed panel mounted. The medal aperture arrives empty — your medal is yours to fit.")
                        specRow("Print", "8 × 10″ panel · 300 DPI, composed to the frame's own aperture")
                    } else {
                        specRow("Overview", product.tagline)
                        specRow("Materials", product.material)
                        specRow("In the box", product.whatShips)
                        specRow("Print", size.geometry.summary)
                    }
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Product details")
                    .font(.system(.headline, design: .rounded))
            }
            .tint(.primary)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private func specRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The same piece in the formats this buyer isn't looking at.
    ///
    /// The formats are already listed as a picker at the top of the page, but a picker is read as
    /// "which one of these am I configuring" and closes as soon as it's answered. A shelf at the
    /// foot of the page is read as "what else could this be", which is a different question and
    /// the one that moves a $59 sheet to a $139 framed object. Tapping a card reconfigures this
    /// page rather than opening another — it is the same artwork either way, and the mockup
    /// above is the point of the change.
    @ViewBuilder private var alsoLike: some View {
        let others = PrintProduct.offered.filter { isMedal || $0 != product }
        VStack(alignment: .leading, spacing: 12) {
            Text("The same piece, finished differently")
                .font(.system(.headline, design: .rounded))
            ForEach(others) { other in
                shelfCard(name: other.name, tagline: other.tagline, symbol: other.symbol,
                          price: other.entryPrice) {
                    isMedal = false
                    product = other
                }
            }
            if !isMedal && MedalFrameCatalog.isAvailable {
                shelfCard(name: "Medal Frame",
                          tagline: "Your medal behind its aperture, this piece printed beside it.",
                          symbol: "medal", price: MedalFrameCatalog.price) {
                    isMedal = true
                }
            }
        }
    }

    private func shelfCard(name: String, tagline: String, symbol: String, price: String,
                           select: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { select() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent.opacity(0.10), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(price)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
