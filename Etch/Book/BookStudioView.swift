import SwiftUI
import SwiftData
import ShopifyCheckoutSheetKit

/// The book editor — a whole subject composed into Prodigi's layflat A4-landscape book. This
/// surface previews every page (cover → chapters → races → back cover), exports a print-ready
/// proof PDF, and orders the book.
///
/// It serves both book products. The Year Book binds a calendar year; a Collection binds a state,
/// a city, the runs someone starred, or every race they've run. Same object, same SKU, same
/// production file — the only difference is which question the subject picker asks, which is why
/// this is one screen and not two.
///
/// The one thing that differs from every other product in the range: the asset is a multi-page PDF
/// rather than a PNG sheet, which is why the upload carries its own content type.
struct BookStudioView: View {
    /// Which book this is. Chooses the title, and what the subject dropdown offers.
    var kind: BookSubject.Kind = .year

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate) private var allRuns: [Run]

    /// Nil until the reader picks one; `resolvedSubject` supplies the default until they do.
    @State private var subject: BookSubject?
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

    /// Everything this history can be bound as, under this product.
    private var subjects: [BookSubject] { BookSubject.offered(kind, in: allRuns) }

    /// What the book is about right now: the chosen subject, or — before anything is chosen, and
    /// while the history is still arriving — the first one offered. Resolving the seed here rather
    /// than assigning it in `onAppear` is what keeps the previews from rendering twice: the pager
    /// is keyed on this one value, and it only changes when the book actually does.
    private var resolvedSubject: BookSubject {
        subject ?? subjects.first ?? .year(Calendar.current.component(.year, from: .now))
    }

    private var plan: BookPlan { BookPlan.make(subject: resolvedSubject, runs: allRuns) }

    private var title: String { kind == .year ? "Year Book" : "Collections" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if subjects.isEmpty {
                    emptyState
                } else {
                    subjectPicker
                    pager
                    footer
                }
            }
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
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
            .task(id: resolvedSubject) { await renderPreviews() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            kind == .year ? "No years to bind yet" : "No collections yet",
            systemImage: kind == .year ? "book.closed" : "books.vertical",
            description: Text(kind == .year
                ? "A Year Book needs at least \(BookSubject.minimumActivities) activities in one year."
                : "A Collection needs at least \(BookSubject.minimumActivities) activities in one state, one city, your favorites, or your races.")
        )
    }

    /// The subject dropdown.
    ///
    /// This was a segmented control, which is the wrong control for the job twice over: a segment
    /// gets an equal share of the bar whatever it holds, so five years came out as five columns
    /// too narrow for four digits and every one of them rendered as "…" — the years genuinely were
    /// not showing. And a Collection's options are a nested list (Favorites, Races, then states,
    /// then cities), which a segmented control cannot express at all. A menu sizes to its label,
    /// nests, and grows with the history.
    private var subjectPicker: some View {
        Menu {
            switch kind {
            case .year:
                ForEach(subjects) { option in subjectButton(option) }
            case .collection:
                // The two that need no place data sit at the top level; places nest, because a
                // long history carries dozens and a flat menu of them is an index, not a choice.
                ForEach(subjects.filter { !$0.isPlace }) { subjectButton($0) }
                let states = subjects.filter(\.isState)
                if !states.isEmpty {
                    Menu("State") { ForEach(states) { subjectButton($0) } }
                }
                let cities = subjects.filter(\.isCity)
                if !cities.isEmpty {
                    Menu("City") { ForEach(cities) { subjectButton($0) } }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(resolvedSubject.menuLabel)
                    .font(.etch(.headline))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .disabled(isExporting || orderPhase != nil)
        .accessibilityLabel(kind == .year ? "Choose a year" : "Choose a collection")
    }

    private func subjectButton(_ option: BookSubject) -> some View {
        Button {
            subject = option
        } label: {
            if option == resolvedSubject {
                Label(option.menuLabel, systemImage: "checkmark")
            } else {
                Text(option.menuLabel)
            }
        }
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
            Text("Page \(currentPage + 1) of \(plan.pageCount)  ·  \(resolvedSubject.productName)  ·  \(BookCatalog.price)")
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
                // is reused rather than rendered twice — `exportPDF` writes one file per subject
                // and returns that same path either way.
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
                    creationID: "book-\(plan.subject.slug)-\(plan.pageCount)p",
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
