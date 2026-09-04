import SwiftUI
import SwiftData
import ShopifyCheckoutSheetKit

/// The book editor — a whole subject composed into Prodigi's layflat A4-landscape book. This
/// surface previews every page (cover → chapters → races → back cover), exports a print-ready
/// proof PDF, and orders the book.
///
/// It serves both book products. Year in Review binds a calendar year; a Collection binds a state,
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
    /// Which sport the book sees. Falls back to everything when the chosen subject can't
    /// support the chosen lens (a year with no rides offers no Rides book).
    @State private var lens: BookLens = .everything
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
    /// The rendered-and-uploaded cart behind the wallet buttons; dropped when the subject
    /// changes, because the uploaded book no longer matches the pages on screen.
    @State private var preparedCart: ShopifyStorefront.Cart?
    /// The customer has paged through the book and approved it. Ordering stays locked until
    /// then; choosing a different subject revokes it.
    @State private var proofApproved = false
    @State private var showApproveDialog = false
    /// Non-nil while a bag add is in flight, and the confirmation that follows it.
    @State private var isAddingToBag = false
    @State private var addedToBag = false

    /// The reader's photo and cover choices for this book, loaded per plan identity.
    @State private var curation = BookCuration()
    /// Bumped by Republish (and cover changes) — part of the render key, so the pages rebuild.
    @State private var curationVersion = 0
    @State private var showPhotoSheet = false
    @State private var showPagesSheet = false

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

    /// The lenses this subject's history supports; only years narrow by sport.
    private var offeredLenses: [BookLens] {
        guard kind == .year else { return [.everything] }
        return BookLens.offered(in: allRuns.filter(resolvedSubject.matches))
    }

    private var resolvedLens: BookLens {
        offeredLenses.contains(lens) ? lens : .everything
    }

    /// The plan the whole surface reads. `BookPlan.make` runs the story engine over the
    /// entire history — real work, not a getter — and this view reads `plan` everywhere,
    /// including once per page child inside the pager's TabView. As a plain computed
    /// property that meant a hundred-page Collections book recomputed the full plan a
    /// hundred-plus times on the main thread at open: seconds of freeze, then the watchdog.
    /// The render task builds it once per render key and caches it here; the computed path
    /// below is only the fallback for the first body evaluation before that task lands.
    @State private var builtPlan: BookPlan?

    private var plan: BookPlan {
        builtPlan ?? BookPlan.make(subject: resolvedSubject, lens: resolvedLens, runs: allRuns,
                                   curation: curation)
    }

    /// What the pager re-renders on: the subject AND the lens are both the book's identity.
    private var planKey: String { resolvedSubject.slug + resolvedLens.slugSuffix }

    /// The full render key: the book's identity plus the curation revision, so Republish
    /// rebuilds the pages without changing which book this is.
    private var renderKey: String { "\(planKey)#\(curationVersion)" }

    private var title: String { kind == .year ? "Year in Review" : "Collections" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if subjects.isEmpty {
                    emptyState
                } else {
                    HStack(spacing: 10) {
                        subjectPicker
                        if offeredLenses.count > 1 { lensPicker }
                        coverPicker
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPagesSheet = true } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .disabled(subjects.isEmpty || isExporting || orderPhase != nil)
                    .accessibilityLabel("Show or hide the book's pages")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPhotoSheet = true } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .disabled(subjects.isEmpty || isExporting || orderPhase != nil)
                    .accessibilityLabel("Choose the book's photos")
                }
            }
            .sheet(isPresented: $showPhotoSheet) {
                BookPhotoSheet(plan: plan, curation: $curation) {
                    curationVersion += 1
                }
            }
            .sheet(isPresented: $showPagesSheet) {
                // The complete table of contents — hidden pages included, so each can come
                // back individually. Built without the hiding applied, once, on open.
                BookPagesSheet(fullPlan: {
                    var complete = curation
                    complete.hiddenPages = []
                    return BookPlan.make(subject: resolvedSubject, lens: resolvedLens,
                                         runs: allRuns, curation: complete)
                }(), curation: $curation) {
                    curationVersion += 1
                }
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
                    .onComplete { event in
                        CheckoutCompletion.record(
                            event,
                            productName: plan.subject.productName,
                            sizeLabel: "\(bookLabel(plan)) · \(plan.pageCount) pages",
                            sku: BookCatalog.prodigiSKU
                        )
                        checkoutURL = nil
                        dismiss()
                    }
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
            .task(id: renderKey) { await renderPreviews() }
            // A sync landing new activities mid-session would leave the cached plan stale;
            // bumping the version refires the render task, which rebuilds and re-caches.
            .onChange(of: allRuns.count) { curationVersion += 1 }
            .addedToBagToast($addedToBag)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            kind == .year ? "No years to bind yet" : "No collections yet",
            systemImage: kind == .year ? "book.closed" : "books.vertical",
            description: Text(kind == .year
                ? "A Year in Review needs at least \(BookSubject.minimumActivities) activities in one year."
                : "A Collection needs at least \(BookSubject.minimumActivities) activities in one state, one city, your favorites, or your races.")
        )
    }

    private var subjectPicker: some View {
        Menu {
            switch kind {
            case .year:
                ForEach(subjects) { option in subjectButton(option) }
            case .collection:
                // Four parallel dropdowns — the collection axes read as siblings. Races holds
                // the whole shelf and each recurring event; Favorites is one entry today but
                // keeps its station so the menu's shape doesn't change as the history grows.
                let races = subjects.filter { $0 == .races || $0.isRaceEvent }
                if !races.isEmpty {
                    Menu("Races") {
                        if subjects.contains(.races) {
                            subjectButton(.races)
                        }
                        let events = subjects.filter(\.isRaceEvent)
                        if !events.isEmpty {
                            Divider()
                            ForEach(events) { subjectButton($0) }
                        }
                    }
                }
                if subjects.contains(.favorites) {
                    Menu("Favorites") { subjectButton(.favorites) }
                }
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

    /// Everything / Runs / Rides / Hikes — the same year through a different lens. Only offered
    /// when the history actually gives a choice.
    private var lensPicker: some View {
        Menu {
            ForEach(offeredLenses) { option in
                Button {
                    lens = option
                } label: {
                    if option == resolvedLens {
                        Label(option.menuLabel, systemImage: "checkmark")
                    } else {
                        Text(option.menuLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(resolvedLens.menuLabel)
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
        .accessibilityLabel("Choose which activities the book includes")
    }

    /// Which treatment the cover wears — the featured route, a photograph, or the grid of
    /// every line. A compact chip: the covers differ in kind, not in degree, so a menu of
    /// three names says more than three thumbnails would at this size.
    private var coverPicker: some View {
        let plan = self.plan
        let hasPhotos = plan.runs.contains { !$0.photoReferences.isEmpty }
            || !curation.extraPhotoIDs.isEmpty
        return Menu {
            ForEach(BookCuration.CoverStyle.allCases) { style in
                Button {
                    curation.coverStyle = style
                    curation.save(slug: plan.slug)
                    curationVersion += 1
                } label: {
                    if style == curation.coverStyle {
                        Label(style.label, systemImage: "checkmark")
                    } else {
                        Text(style.label)
                    }
                }
                .disabled(style == .photo && !hasPhotos)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.closed")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .disabled(isExporting || orderPhase != nil)
        .accessibilityLabel("Choose the cover style, currently \(curation.coverStyle.label)")
    }

    /// The book as a receipt names it: the subject, and the lens when it narrows.
    private func bookLabel(_ plan: BookPlan) -> String {
        plan.lens == .everything
            ? plan.subject.menuLabel
            : "\(plan.subject.menuLabel) · \(plan.lens.menuLabel)"
    }

    private var pager: some View {
        // One plan for every page child. The `.page` TabView builds all of its children
        // up front, and each child's context menu asks for its hide-key — through the
        // computed property that was a full plan derivation before the render task caches
        // it. Capturing the value once here is what keeps the first body evaluation of a
        // hundred-page book from doing a hundred story-engine passes.
        let plan = self.plan
        return TabView(selection: $currentPage) {
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
                .contextMenu {
                    // A page the reader would rather not bind: touch and hold, take it out.
                    // Structural pages (cover, title, the record, the closing) offer nothing.
                    if let key = plan.hideKey(at: index) {
                        Button(role: .destructive) {
                            curation.hiddenPages.insert(key)
                            curation.save(slug: plan.slug)
                            curationVersion += 1
                        } label: {
                            Label("Hide this page from the book", systemImage: "eye.slash")
                        }
                    }
                }
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

            // Hidden pages don't render, so the way back is here — one honest count and
            // one action, not a management screen.
            if !curation.hiddenPages.isEmpty {
                Button {
                    curation.hiddenPages.removeAll()
                    curation.save(slug: plan.slug)
                    curationVersion += 1
                } label: {
                    Label("Restore \(curation.hiddenPages.count) hidden page\(curation.hiddenPages.count == 1 ? "" : "s")",
                          systemImage: "eye")
                        .font(.etch(.footnote, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }

            // The pages above are the proof — the gate asks the customer to say they've read
            // them before either order path unlocks. The dialog makes it an acknowledgment
            // rather than a tap on the way past.
            if canOrder {
                ProofGateButton(approved: proofApproved,
                                title: "Approve proof",
                                action: { showApproveDialog = true })
                    .confirmationDialog("Approve this proof?",
                                        isPresented: $showApproveDialog,
                                        titleVisibility: .visible) {
                        Button("Everything looks right — approve") { proofApproved = true }
                        Button("Keep checking", role: .cancel) {}
                    } message: {
                        Text("Swipe through every page first. What you approve is exactly what gets bound and shipped.")
                    }
            }

            orderButton

            if canOrder {
                AddToBagButton(isWorking: isAddingToBag,
                               isDisabled: orderPhase != nil || isExporting || !proofApproved) {
                    order(.bag)
                }
            }

            if let proofURL {
                ShareLink(item: proofURL) {
                    Label("Download Proof PDF", systemImage: "arrow.down.doc")
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

    private func renderPreviews() async {
        previews = [:]
        currentPage = 0
        proofURL = nil
        preparedCart = nil
        proofApproved = false

        // The stored curation for THIS book — loaded before the plan is captured, so a
        // subject switch brings that book's own choices with it. Republish saves first,
        // so reloading here never loses anything.
        curation = BookCuration.load(slug: planKey)
        // CI's screenshot rig can ask for a cover treatment by name; inert otherwise.
        switch ProcessInfo.processInfo.environment["ETCH_PREVIEW_SCROLL"] {
        case "cover-grid":  curation.coverStyle = .grid
        case "cover-photo": curation.coverStyle = .photo
        default: break
        }
        // Build ONCE per render key and cache — every `plan` read below and in the body
        // (the pager's hundred page children included) now costs a dictionary lookup, not
        // a story-engine pass over the whole history.
        let plan = BookPlan.make(subject: resolvedSubject, lens: resolvedLens, runs: allRuns,
                                 curation: curation)
        builtPlan = plan

        // CI's screenshot rig can name a page family (yearbook@review, yearbook@marks, …); the
        // pager jumps there and that page renders first, so the shot never races the other
        // thirty renders. Inert without the environment variable, like the rest of the harness.
        var order = Array(plan.pages.indices)
        if let anchored = previewAnchorIndex(in: plan) {
            currentPage = anchored
            order.removeAll { $0 == anchored }
            order.insert(anchored, at: 0)
        }

        for index in order {
            if Task.isCancelled { return }
            if let image = await BookRenderer.pageImage(plan: plan, page: index, scale: 0.45) {
                previews[index] = image
            }
        }
    }

    /// The first page matching the harness anchor, when one is set.
    private func previewAnchorIndex(in plan: BookPlan) -> Int? {
        guard let anchor = ProcessInfo.processInfo.environment["ETCH_PREVIEW_SCROLL"],
              !anchor.isEmpty else { return nil }
        return plan.pages.firstIndex { spec in
            switch (anchor, spec) {
            case ("marks", .marks), ("map", .map), ("review", .review), ("closing", .closing),
                 ("stats", .stats), ("race", .race(_)), ("index", .index(_)),
                 ("month", .chapter(_)), ("photos", .chapterPhotos(_)),
                 ("gallery", .gallery), ("numbers", .numbers),
                 ("years", .years), ("resume", .raceHistory), ("atlas", .atlas),
                 ("cities", .cities), ("cover-grid", .cover), ("cover-photo", .cover):
                return true
            case ("quiet", .chapter(let start)):
                return BookStory.chapterProfile(for: plan.chapterRuns(start)) == .quiet
            default: return false
            }
        }
    }

    @ViewBuilder private var orderButton: some View {
        if canOrder {
            DeliveryNote()
            if let preparedCart, ApplePayConfig.isConfigured {
                PreparedWalletPanel(
                    cart: preparedCart,
                    onComplete: { event in
                        CheckoutCompletion.record(
                            event,
                            productName: plan.subject.productName,
                            sizeLabel: "\(bookLabel(plan)) · \(plan.pageCount) pages",
                            sku: BookCatalog.prodigiSKU
                        )
                        dismiss()
                    },
                    onFail: { orderError = $0 },
                    openHosted: { checkoutURL = preparedCart.checkoutURL }
                )
            } else {
                Button { order(.checkout) } label: {
                    Group {
                        if let orderPhase {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text(orderPhase.label)
                            }
                        } else {
                            Label(ApplePayConfig.isConfigured
                                    ? "Continue · \(BookCatalog.price)"
                                    : "Order the book · \(BookCatalog.price)",
                                  systemImage: "bag")
                        }
                    }
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent.opacity(proofApproved ? 1 : 0.35), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(orderPhase != nil || isExporting || !proofApproved)
            }
        }
    }

    private func order(_ destination: StudioOrderDestination) {
        guard orderPhase == nil, !isAddingToBag, proofApproved else { return }
        let plan = plan
        if destination == .bag { isAddingToBag = true }
        Task {
            defer { isAddingToBag = false }
            do {
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

                let creationID = "book-\(plan.slug)-\(plan.pageCount)p"
                switch destination {
                case .checkout:
                    let cart = try await PrintOrderService.checkout(
                        fileAt: fileURL,
                        pixels: BookCatalog.pagePixelSize,
                        creationID: creationID,
                        shopifySKU: BookCatalog.prodigiSKU,
                        prodigiSKU: BookCatalog.prodigiSKU,
                        productHandle: BookCatalog.shopifyHandle,
                        finishAttribute: "",
                        contentType: BookCatalog.contentType,
                        onPhase: { orderPhase = $0 }
                    )
                    orderPhase = nil
                    // Wallets configured: the prepared cart surfaces Apple Pay in place of the
                    // order button. Otherwise the hosted checkout opens directly, as before.
                    preparedCart = cart
                    if !ApplePayConfig.isConfigured { checkoutURL = cart.checkoutURL }
                case .bag:
                    try await PrintOrderService.addToBag(
                        fileAt: fileURL,
                        pixels: BookCatalog.pagePixelSize,
                        creationID: creationID,
                        shopifySKU: BookCatalog.prodigiSKU,
                        prodigiSKU: BookCatalog.prodigiSKU,
                        productHandle: BookCatalog.shopifyHandle,
                        finishAttribute: "",
                        contentType: BookCatalog.contentType,
                        title: plan.subject.productName,
                        detail: "\(bookLabel(plan)) · \(plan.pageCount) pages",
                        priceCents: BookCatalog.priceCents,
                        onPhase: { orderPhase = $0 }
                    )
                    orderPhase = nil
                    addedToBag = true
                }
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

private struct BookCheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

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
