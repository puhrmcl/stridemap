import SwiftUI
import SwiftData
import ShopifyCheckoutSheetKit

/// The Year Book — a whole year of activity composed into Prodigi's layflat A4-landscape book.
/// This surface previews every page (cover → months → races → back cover), exports a print-ready
/// proof PDF, and orders the book.
///
/// Ordering was the missing half. The SKU was verified, the price was set and served, and
/// `BookRenderer.exportPDF` already produced the exact file the lab prints — the book was simply
/// never connected to a cart, so the storefront listed a $119 product that could be admired and
/// not bought. The same gap the Photo Wall had, closed the same way.
///
/// The one thing that differs from every other product: the asset is a multi-page PDF rather than
/// a PNG sheet, which is why the upload carries its own content type.
struct YearBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate) private var allRuns: [Run]

    @State private var year: Int = Calendar.current.component(.year, from: .now)
    @State private var didSeedYear = false
    /// Rendered page previews, by page index, for the current plan.
    @State private var previews: [Int: UIImage] = [:]
    @State private var currentPage = 0

    @State private var isExporting = false
    @State private var exportProgress: (Int, Int) = (0, 0)
    @State private var proofURL: URL?

    /// Non-nil while the render → upload → cart pipeline runs; drives the button's narration.
    @State private var orderPhase: PrintOrderService.Phase?
    @State private var orderError: String?
    @State private var checkoutURL: URL?

    private var canOrder: Bool {
        PrintOrderService.isConfigured && EtchConfig.current.ordering.enabled && !plan.runs.isEmpty
    }

    private var years: [Int] {
        Array(Set(allRuns.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private var plan: BookPlan { BookPlan.make(year: year, runs: allRuns) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if years.isEmpty {
                    ContentUnavailableView("No activities yet",
                                           systemImage: "book.closed",
                                           description: Text("The Year Book composes itself from a year of activities."))
                } else {
                    yearPicker
                    pager
                    footer
                }
            }
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Year Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .sheet(item: Binding(
                get: { checkoutURL.map { BookCheckoutTarget(url: $0) } },
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
                    .interactiveDismissDisabled()  // mid-payment swipe-away protection
            }
            .alert("Couldn't start the order", isPresented: Binding(
                get: { orderError != nil }, set: { if !$0 { orderError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: { Text(orderError ?? "") }
            .task(id: year) { await renderPreviews() }
            .onAppear {
                // Open on the most recent year that has activity.
                if !didSeedYear, let latest = years.first {
                    didSeedYear = true
                    year = latest
                }
            }
        }
    }

    private var yearPicker: some View {
        Picker("Year", selection: $year) {
            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .disabled(isExporting)
    }

    /// The book as a swipeable pager — each card is one page at the true A4-landscape aspect.
    private var pager: some View {
        TabView(selection: $currentPage) {
            ForEach(plan.pages.indices, id: \.self) { index in
                Group {
                    if let image = previews[index] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.Palette.bone)
                            .aspectRatio(BookCatalog.pageSize.width / BookCatalog.pageSize.height,
                                         contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                .padding(.horizontal, 22)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("Page \(currentPage + 1) of \(plan.pageCount)  ·  \(BookCatalog.name)  ·  \(BookCatalog.price)")
                .font(.etch(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)

            // The proof is secondary once the book can be bought. Two filled accent capsules
            // stacked would have given a check step and a commitment the same weight, and the
            // one that costs $119 should not be the second of two identical buttons.
            orderButton

            if let proofURL {
                ShareLink(item: proofURL) {
                    Label("Share Proof PDF", systemImage: "square.and.arrow.up")
                        .modifier(BookSecondaryButton(prominent: !canOrder))
                }
            } else {
                Button { export() } label: {
                    Group {
                        if isExporting {
                            HStack(spacing: 10) {
                                ProgressView().tint(canOrder ? Theme.accent : .white)
                                Text("Rendering page \(exportProgress.0) of \(exportProgress.1)…")
                            }
                        } else {
                            Label("Export Proof PDF", systemImage: "doc.richtext")
                        }
                    }
                    .modifier(BookSecondaryButton(prominent: !canOrder))
                }
                .buttonStyle(.plain)
                .disabled(isExporting || plan.runs.isEmpty)
            }

            Text(canOrder
                 ? "\(BookCatalog.material) Printed to order and shipped to your door."
                 : "\(BookCatalog.material) The proof PDF is print-exact.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    /// Preview pages render sequentially at a light scale; the pager fills in as they land.
    private func renderPreviews() async {
        previews = [:]
        currentPage = 0
        proofURL = nil
        let plan = plan
        for index in plan.pages.indices {
            if Task.isCancelled { return }
            if let image = await BookRenderer.pageImage(plan: plan, page: index, scale: 0.45) {
                previews[index] = image
            }
        }
    }

    /// Buying the book. Sits below the proof export, because a proof is a thing you check and an
    /// order is a thing you commit to, and the page should not invite the second before the first.
    @ViewBuilder private var orderButton: some View {
        if canOrder {
            Button(action: order) {
                Group {
                    if let orderPhase {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(orderPhase.label)
                        }
                    } else {
                        Label("Order the book · \(BookCatalog.price)", systemImage: "bag")
                    }
                }
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(orderPhase != nil || isExporting)
        }
    }

    private func order() {
        guard orderPhase == nil else { return }
        let plan = plan
        Task {
            do {
                // The proof and the production file are the same document, so an exported proof
                // is reused rather than rendered twice — `exportPDF` writes one file per year and
                // returns that same path either way.
                orderPhase = .rendering
                var fileURL = proofURL
                if fileURL == nil || !FileManager.default.fileExists(atPath: fileURL!.path) {
                    fileURL = await BookRenderer.exportPDF(plan: plan) { done, total in
                        exportProgress = (done, total)
                    }
                }
                guard let fileURL else {
                    orderPhase = nil
                    orderError = "The book couldn't be rendered. Try again."
                    return
                }

                // Stable across reorders on purpose: the creation id is what lets a second copy
                // of the 2026 book be reproduced rather than re-imagined. The asset id beneath it
                // is fresh every time, so nothing frozen is ever overwritten.
                let cart = try await PrintOrderService.checkout(
                    fileAt: fileURL,
                    pixels: BookCatalog.pagePixelSize,
                    creationID: "yearbook-\(plan.year)-\(plan.pageCount)p",
                    shopifySKU: BookCatalog.prodigiSKU,
                    prodigiSKU: BookCatalog.prodigiSKU,
                    productHandle: BookCatalog.shopifyHandle,
                    finishAttribute: "",
                    contentType: BookCatalog.contentType,
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

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        let plan = plan
        Task {
            let url = await BookRenderer.exportPDF(plan: plan) { done, total in
                exportProgress = (done, total)
            }
            isExporting = false
            proofURL = url
        }
    }
}

/// The checkout URL as an `Identifiable` sheet item. Deliberately file-local: `PhotoWallView`
/// has its own, and a shared one would be a type in the global namespace for two call sites.
private struct BookCheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The proof button's look. Filled while the book cannot be ordered — it is then the only action
/// on the page and should carry weight — and tinted once the order button exists above it.
private struct BookSecondaryButton: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .font(.etch(.subheadline, weight: .semibold))
            .foregroundStyle(prominent ? .white : Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(prominent ? AnyShapeStyle(Theme.accent)
                                  : AnyShapeStyle(Theme.accent.opacity(0.12)),
                        in: .capsule)
    }
}
