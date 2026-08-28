import SwiftUI
import SwiftData
import ShopifyCheckoutSheetKit

/// The medal display frame: the medal itself behind a pre-cut aperture, with a printed panel of
/// the race beside it.
///
/// This product could not simply reuse the print sheet, for two reasons that are both physical.
///
/// **Its aperture is not 2:3.** The catalog reports a print area of 2397 × 3000 — 7.99 × 10.00″ at
/// 300 DPI — which is neither the 2:3 every other poster in the range uses nor the clean
/// 2400 × 3000 the range sheet's "8×10 inch" implies. Three pixels is enough to matter when the
/// artwork has to register against a window someone else cut, so the composition is built to the
/// number the API gives rather than the one the brochure rounds to.
///
/// **It takes two colours, not one.** Prodigi wants `color` for the moulding *and* `mountColor`
/// for the board the medal hangs against, and rejects a quote if either is missing. Every other
/// product in the range has one finish, which is why `PrintOrderService` carried one attribute
/// until this screen needed a second.
struct MedalFrameView: View {
    let run: Run

    @Environment(\.dismiss) private var dismiss
    /// Kept posters, newest edit first — the panel adopts this run's latest one automatically.
    @Query(sort: \SavedPoster.updatedAt, order: .reverse) private var savedPosters: [SavedPoster]
    /// Presents the full Studio editor on the panel's recipe.
    @State private var customizing = false

    @State private var frameColour = "black"
    @State private var mountColour = "Black"

    @State private var panel: UIImage?
    @State private var orderPhase: PrintOrderService.Phase?
    @State private var orderError: String?
    @State private var checkoutURL: URL?

    /// 2397 × 3000 at 300 DPI, stated as inches because that is what `PrintGeometry` takes and
    /// what the trim actually is.
    private var geometry: PrintGeometry {
        PrintGeometry(trimWidth: 7.99, trimHeight: 10.0)
    }

    private var canOrder: Bool {
        MedalFrameCatalog.isAvailable
            && PrintOrderService.isConfigured
            && EtchConfig.current.ordering.enabled
    }

    /// The panel's composition: the run's most recently edited kept poster when one exists,
    /// else the default recipe.
    ///
    /// This is what makes the panel customizable without this screen growing an editor: the
    /// Customize button opens the real Studio editor — every edition, layout, title and data
    /// control it already has — and whatever is kept there becomes the panel, here and in the
    /// order. One editor in the app, not a second smaller one to maintain beside it.
    private var savedRecipe: SavedPoster? {
        savedPosters.first { $0.runID == run.id }
    }
    private var panelConfig: PosterConfig {
        savedRecipe.map { PosterConfig(poster: $0) } ?? PosterConfig.makeDefault(for: run)
    }
    /// Re-render trigger: a different poster, or a newer edit of the same one.
    private var recipeKey: String {
        savedRecipe.map { "\($0.id)-\($0.updatedAt.timeIntervalSinceReferenceDate)" } ?? "default"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    mockup
                    Button { customizing = true } label: {
                        Label(savedRecipe == nil ? "Customize the print" : "Edit the print",
                              systemImage: "slider.horizontal.3")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Theme.accent.opacity(0.10), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    colourPicker("Frame", options: MedalFrameCatalog.frameColours,
                                 selection: $frameColour, hex: mouldingHex)
                    colourPicker("Mount", options: MedalFrameCatalog.mountColours,
                                 selection: $mountColour, hex: mountHex)
                    orderPanel
                }
                .padding(20)
            }
            .background(Theme.Palette.bone.opacity(0.35).ignoresSafeArea())
            .navigationTitle("Medal Frame")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task(id: recipeKey) { await renderPanel() }
            .sheet(isPresented: $customizing, onDismiss: { panel = nil }) {
                StudioView(run: run, poster: savedRecipe)
            }
            .sheet(item: Binding(
                get: { checkoutURL.map { MedalCheckoutTarget(url: $0) } },
                set: { if $0 == nil { checkoutURL = nil } }
            )) { target in
                CheckoutSheet(checkout: target.url)
                    .title("Checkout")
                    .colorScheme(.automatic)
                    .tintColor(UIColor(Theme.accent))
                    .onCancel { checkoutURL = nil }
                    .onComplete { _ in checkoutURL = nil; dismiss() }
                    .onFail { error in
                        checkoutURL = nil
                        orderError = error.localizedDescription
                    }
                    .interactiveDismissDisabled()
            }
            .alert("Couldn't start the order", isPresented: Binding(
                get: { orderError != nil }, set: { if !$0 { orderError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: { Text(orderError ?? "") }
        }
    }

    // MARK: The object

    /// The frame as it arrives: moulding, snow-white top mount, the medal's aperture on the left,
    /// the printed panel on the right.
    ///
    /// The aperture is drawn as an empty well rather than with a stock medal in it. What hangs
    /// there is the buyer's own, and a mockup that supplies one would be showing them something
    /// they are not being sent.
    private var mockup: some View {
        MedalFrameMockup(panel: panel, frameColour: frameColour, mountColour: mountColour)
            .overlay {
                // The panel is still composing: say so over the stock rather than leaving a
                // blank rectangle that looks like the finished product.
                if panel == nil { ProgressView() }
            }
            .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .animation(.easeInOut(duration: 0.2), value: frameColour)
            .animation(.easeInOut(duration: 0.2), value: mountColour)
    }

    private func colourPicker(_ label: String, options: [String],
                              selection: Binding<String>,
                              hex: @escaping (String) -> String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label).font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text("—").foregroundStyle(.tertiary)
                Text(selection.wrappedValue.capitalized)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }
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

    // MARK: Order

    private var orderPanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MedalFrameCatalog.price)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                    Text("30 × 40cm · 240gsm lustre · Perspex glaze")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if canOrder {
                Button(action: order) {
                    Group {
                        if let orderPhase {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text(orderPhase.label)
                            }
                        } else {
                            Label("Order · \(MedalFrameCatalog.price)", systemImage: "bag")
                        }
                    }
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(orderPhase != nil || panel == nil)

                Text("Made in the UK and shipped to your door. Your medal is yours to fit — the frame arrives ready for it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 6) {
                    Label(EtchConfig.current.ordering.closedTitle, systemImage: "clock")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(EtchConfig.current.ordering.closedDetail)
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private func order() {
        guard orderPhase == nil else { return }
        Task {
            do {
                orderPhase = .rendering
                var request = panelConfig.request(for: run)
                request.printAspect = geometry.aspect
                request.outputSize = .poster

                let fileURL = try await StudioRenderer.printFile(for: request, geometry: geometry)
                defer { try? FileManager.default.removeItem(at: fileURL) }

                let cart = try await PrintOrderService.checkout(
                    fileAt: fileURL,
                    pixels: geometry.trimPixels,
                    creationID: "medal-\(run.id.uuidString)",
                    shopifySKU: MedalFrameCatalog.sku,
                    prodigiSKU: MedalFrameCatalog.sku,
                    productHandle: MedalFrameCatalog.shopifyHandle,
                    finishAttribute: frameColour,
                    mountAttribute: mountColour,
                    onPhase: { orderPhase = $0 }
                )
                orderPhase = nil
                checkoutURL = cart.checkoutURL
            } catch {
                orderPhase = nil
                orderError = error.localizedDescription
            }
        }
    }

    private func renderPanel() async {
        var request = panelConfig.request(for: run)
        request.printAspect = geometry.aspect
        panel = await StudioRenderer.image(for: request, scale: 0.4)
    }

    // MARK: Colour tables

    /// Mockup colours live in the catalog now, shared with the print shop's format picker.
    private func mouldingHex(_ name: String) -> String { MedalFrameCatalog.mouldingHex(name) }
    private func mountHex(_ name: String) -> String { MedalFrameCatalog.mountHex(name) }
}

private struct MedalCheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
