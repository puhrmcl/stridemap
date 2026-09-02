import SwiftUI
import PhotosUI
import ShopifyCheckoutSheetKit

struct PhotoWallView: View {
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel

    @State private var filter: Filter = .all
    @State private var didSeedFromAppFilter = false
    @State private var sort: SortOrder = .newest
    @State private var count = MultiPhotoFrameCatalog.defaultPhotos
    @State private var excludedIDs: Set<UUID> = []
    @State private var randomOrder: [UUID] = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var posterImage: UIImage?
    @State private var screenshotRunIDs: Set<UUID> = []
    @State private var addedPhotos: [AddedPhoto] = []
    @State private var picking: [PhotosPickerItem] = []
    @State private var isImporting = false

    struct AddedPhoto: Identifiable, Equatable {
        let id = UUID()
        let image: UIImage
        static func == (a: AddedPhoto, b: AddedPhoto) -> Bool { a.id == b.id }
    }

    enum WallCell: Identifiable, Equatable {
        case run(Run)
        case added(AddedPhoto)
        var id: UUID {
            switch self {
            case .run(let run):     return run.id
            case .added(let photo): return photo.id
            }
        }
    }

    @State private var orderPhase: PrintOrderService.Phase?
    @State private var orderError: String?
    @State private var checkoutURL: URL?
    @State private var isAddingToBag = false
    @State private var addedToBag = false
    /// The rendered-and-uploaded cart behind the wallet buttons; dropped whenever the wall's
    /// contents change, because the uploaded file no longer matches what's on screen.
    @State private var preparedCart: ShopifyStorefront.Cart?
    /// The customer has inspected the wall's poster full screen and approved it. Ordering stays
    /// locked until then; any change to the wall's contents revokes it.
    @State private var proofApproved = false
    @State private var showingProof = false
    private let maxPhotos = MultiPhotoFrameCatalog.maxPhotos

    /// The frame colour the order ships in — chosen on the page, worn by the mockup, carried on
    /// the order line. The catalog always offered eight finishes; the page used to hardcode the
    /// first.
    @State private var wallFrame = MultiPhotoFrameCatalog.frameColours.first ?? "black"

    /// Whether the product-details panel is open. Starts open, like the Print Shop's.
    @State private var specsExpanded = true

    enum Filter: Hashable {
        case all
        case year(Int)
        case state(String)
        case place(String)
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case location = "By Location"
        case random = "Shuffled"
        var id: String { rawValue }
    }

    private var photoRuns: [Run] {
        runs.filter { !$0.photoReferences.isEmpty && !screenshotRunIDs.contains($0.id) }
    }

    private var filtered: [Run] {
        switch filter {
        case .all: return photoRuns
        case .year(let y):
            let cal = Calendar.current
            return photoRuns.filter { cal.component(.year, from: $0.startDate) == y }
        case .state(let s):
            return photoRuns.filter {
                PlaceNames.canonicalState($0.state) == PlaceNames.canonicalState(s)
            }
        case .place(let name):
            let places = RunStatistics(photoRuns).travelPlaces
            guard let place = places.first(where: { cityLabel($0) == name }) else { return photoRuns }
            let ids = Set(place.runs.map(\.id))
            return photoRuns.filter { ids.contains($0.id) }
        }
    }

    private var ordered: [Run] {
        switch sort {
        case .newest: return filtered.sorted { $0.startDate > $1.startDate }
        case .oldest: return filtered.sorted { $0.startDate < $1.startDate }
        case .location:
            return filtered.sorted {
                let a = $0.placeLabel.isEmpty ? "~" : $0.placeLabel
                let b = $1.placeLabel.isEmpty ? "~" : $1.placeLabel
                return a == b ? $0.startDate > $1.startDate : a < b
            }
        case .random:
            let rank = Dictionary(uniqueKeysWithValues: randomOrder.enumerated().map { ($1, $0) })
            return filtered.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        }
    }

    private var pool: [Run] { ordered.filter { !excludedIDs.contains($0.id) } }
    private var cellPool: [WallCell] {
        pool.map(WallCell.run) + addedPhotos.filter { !excludedIDs.contains($0.id) }.map(WallCell.added)
    }
    private var shownCells: [WallCell] { Array(cellPool.prefix(count)) }
    private var shown: [Run] {
        shownCells.compactMap { if case .run(let r) = $0 { return r } else { return nil } }
    }
    private var maxCount: Int { max(1, min(cellPool.count, maxPhotos)) }

    private func cityLabel(_ place: RunStatistics.TravelPlace) -> String {
        let parts = place.label.components(separatedBy: ", ")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ", ") : place.label
    }

    private func seedFromAppFilter() {
        guard !didSeedFromAppFilter else { return }
        didSeedFromAppFilter = true
        let active = appModel.filter
        if let city = active.city, !city.isEmpty {
            let place = RunStatistics(photoRuns).travelPlaces
                .first { $0.runs.contains { $0.city == city } }
            if let place { filter = .place(cityLabel(place)) }
        } else if let state = active.state, !state.isEmpty {
            let hasPhotos = photoRuns.contains {
                PlaceNames.canonicalState($0.state) == PlaceNames.canonicalState(state)
            }
            if hasPhotos { filter = .state(state) }
        }
    }

    private var filterLabel: String {
        switch filter {
        case .all:             return "All Photos"
        case .year(let y):     return String(y)
        case .state(let s):    return s
        case .place(let name): return name
        }
    }

    private var columnCount: Int {
        let n = max(shownCells.count, 1)
        if let size = MultiPhotoFrameCatalog.exactSize(forPhotos: n) { return size.columns }
        return min(6, max(1, Int(ceil(Double(n).squareRoot()))))
    }

    private var renderKey: String {
        "\(shownCells.map { $0.id.uuidString }.joined())-\(columnCount)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if cellPool.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on the wall yet", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Add photos to your activities — or choose any pictures from your library — and they'll gather here as a wall.")
                    } actions: {
                        addPhotosButton
                    }
                } else {
                    // The product-page shape the Print Shop set: what it is and costs, the
                    // object on a wall, its options, then the order — not a screenful of
                    // thumbnails with a price at the bottom.
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 26) {
                                titleBlock.id("top")
                                mockup
                                framePicker.id("frame")
                                wallControls.id("photos")
                                orderPanel.id("order")
                                specs.id("details")
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
                }
            }
            .navigationTitle("Photo Wall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let posterImage {
                        ShareLink(
                            item: Image(uiImage: posterImage),
                            preview: SharePreview(filterLabel, image: Image(uiImage: posterImage))
                        ) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .sheet(item: Binding(
                get: { checkoutURL.map { CheckoutTarget(url: $0) } },
                set: { if $0 == nil { checkoutURL = nil } }
            )) { target in
                CheckoutSheet(checkout: target.url)
                    .title("Checkout")
                    .colorScheme(.automatic)
                    .tintColor(UIColor(Theme.accent))
                    .onCancel { checkoutURL = nil }
                    .onComplete { event in
                        let size = MultiPhotoFrameCatalog.size(forPhotos: shownCells.count)
                        CheckoutCompletion.record(
                            event,
                            productName: "Photo Wall",
                            sizeLabel: "\(size.label) · \(shownCells.count) photos",
                            sku: size.sku
                        )
                        checkoutURL = nil
                        dismiss()
                    }
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
            .onChange(of: filter) { excludedIDs = []; clampCount() }
            // A different frame is a different order line; the photos are unchanged, so the
            // approved proof stands.
            .onChange(of: wallFrame) { preparedCart = nil }
            .onAppear {
                seedFromAppFilter()
                clampCount()
            }
            .task { detectScreenshots() }
            .task(id: renderKey) { await loadAndRender() }
            .fullScreenCover(isPresented: $showingProof) {
                ProofApprovalView(image: posterImage) { proofApproved = true }
            }
            .addedToBagToast($addedToBag)
        }
    }

    // MARK: The title block — the configured product, named and priced, above the image.

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo Wall")
                .font(.etch(.title2, weight: .bold))
            Text(configurationLine)
                .font(.etch(.subheadline))
                .foregroundStyle(.secondary)
            Text(MultiPhotoFrameCatalog.price)
                .font(.etch(.title3, weight: .semibold))
                .monospacedDigit()
            DeliveryNote()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: shownCells.count)
    }

    /// "20 × 30″ · 40 photos · Black frame" — every choice the order carries, in one line.
    private var configurationLine: String {
        let size = MultiPhotoFrameCatalog.size(forPhotos: shownCells.count)
        return "\(size.label) · \(shownCells.count) photos · \(wallFrame.capitalized) frame"
    }

    // MARK: The object

    /// The wall as the piece it ships as: the photo grid behind the multi-aperture frame's
    /// moulding, mounted, hung on the mockup wall. Cells stay tappable — tap to swap one out.
    private var mockup: some View {
        ZStack {
            MockupWall()
            FramedPrintMockup(
                moulding: Color(hex: MedalFrameCatalog.mouldingHex(wallFrame)) ?? .black,
                hasGrain: wallFrame.contains("natural") || wallFrame.contains("brown"),
                mouldingWidth: 10
            ) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: columnCount),
                    spacing: 3
                ) {
                    ForEach(shownCells) { item in
                        cell(item)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { remove(item) } }
                    }
                }
                .padding(8)
                .background(Theme.Artwork.mountBoard)
            }
            .padding(28)
        }
        .clipShape(.rect(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.2), value: wallFrame)
    }

    // MARK: Frame finish

    private var framePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Frame").font(.etch(.subheadline, weight: .semibold))
                Text("—").foregroundStyle(.tertiary)
                Text(wallFrame.capitalized)
                    .font(.etch(.subheadline))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MultiPhotoFrameCatalog.frameColours, id: \.self) { option in
                        Button { wallFrame = option } label: {
                            Circle()
                                .fill(Color(hex: MedalFrameCatalog.mouldingHex(option)) ?? .gray)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                                .padding(3)
                                .overlay {
                                    Circle().strokeBorder(
                                        wallFrame == option ? Theme.accent : .clear, lineWidth: 2
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

    // MARK: Product details

    private var specs: some View {
        VStack(spacing: 0) {
            DisclosureGroup(isExpanded: $specsExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    specRow("Overview", "Your photographs, one to an aperture, in a single framed piece. Printed and framed to order.")
                    specRow("Materials", "Wood frame in eight finishes · white mount · your photos printed to each aperture")
                    specRow("In the box", "One assembled frame with every photograph mounted — ready to hang.")
                    specRow("Print", {
                        let size = MultiPhotoFrameCatalog.size(forPhotos: shownCells.count)
                        return "\(size.label) · \(size.columns) × \(size.rows) grid · \(Int(size.printPixels.width)) × \(Int(size.printPixels.height)) px at 300 DPI"
                    }())
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Product details")
                    .font(.etch(.headline))
            }
            .tint(.primary)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private func specRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.etch(.subheadline, weight: .semibold))
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ item: WallCell) -> some View {
        Rectangle()
            .fill(Theme.Palette.stone)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = photo(for: item) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(.rect(cornerRadius: 3))
            .contentShape(.rect)
    }

    private func photo(for item: WallCell) -> UIImage? {
        switch item {
        case .run(let run):     return images[run.id]
        case .added(let photo): return photo.image
        }
    }

    private func remove(_ item: WallCell) {
        excludedIDs.insert(item.id)
        clampCount()
    }

    @MainActor
    private func detectScreenshots() {
        let candidates = runs.filter { !$0.photoReferences.isEmpty }
        let coverByRun = candidates.compactMap { run in run.photoReferences.first.map { (run.id, $0) } }
        let shots = PhotoLibrary.screenshotIdentifiers(among: coverByRun.map(\.1))
        guard !shots.isEmpty else { return }
        screenshotRunIDs = Set(coverByRun.filter { shots.contains($0.1) }.map(\.0))
    }

    /// Choosing what hangs in the frame: filter, order, count.
    private var wallControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                filterMenu
                sortMenu
                shuffleButton
            }
            addPhotosButton
            HStack(spacing: 16) {
                Stepper("Photos: \(shownCells.count)", value: $count, in: 1...maxCount)
                    .font(.etch(.subheadline, weight: .medium))
            }
            Text(MultiPhotoFrameCatalog.fitDescription(forPhotos: shownCells.count))
                .font(.etch(.caption, weight: .medium))
                .foregroundStyle(Theme.accent)
            if !excludedIDs.isEmpty {
                Button {
                    withAnimation { excludedIDs.removeAll() }
                } label: {
                    Label("Restore removed (\(excludedIDs.count))", systemImage: "arrow.uturn.backward")
                        .font(.etch(.footnote, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            Text("Tap a photo in the frame to swap it out.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private var orderPanel: some View {
        VStack(spacing: 12) {
            orderButton
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private var canOrder: Bool {
        MultiPhotoFrameCatalog.isAvailable
            && PrintOrderService.isConfigured
            && EtchConfig.current.ordering.enabled
    }

    @ViewBuilder private var orderButton: some View {
        if !shownCells.isEmpty, !canOrder {
            VStack(spacing: 6) {
                Label(EtchConfig.current.ordering.closedTitle, systemImage: "clock")
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(EtchConfig.current.ordering.closedDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 14))
        }
        if canOrder, !shownCells.isEmpty {
            // The proof first: the wall's own poster render, full screen, approved before
            // either order path unlocks.
            ProofGateButton(approved: proofApproved,
                            action: { showingProof = true },
                            viewAgain: { showingProof = true })
            if let preparedCart, ApplePayConfig.isConfigured {
                PreparedWalletPanel(
                    cart: preparedCart,
                    onComplete: { event in
                        let size = MultiPhotoFrameCatalog.size(forPhotos: shownCells.count)
                        CheckoutCompletion.record(
                            event, productName: "Photo Wall",
                            sizeLabel: "\(size.label) · \(shownCells.count) photos",
                            sku: size.sku
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
                                    ? "Continue · \(MultiPhotoFrameCatalog.price)"
                                    : "Order framed · \(MultiPhotoFrameCatalog.price)",
                                  systemImage: "bag")
                        }
                    }
                    .font(.etch(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(proofApproved ? 1 : 0.35),
                                in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(orderPhase != nil || !proofApproved)
            }
            AddToBagButton(isWorking: isAddingToBag,
                           isDisabled: orderPhase != nil || !proofApproved) {
                order(.bag)
            }
            Text("Secure checkout with Apple Pay or card. Framed to order and shipped to your door.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func order(_ destination: StudioOrderDestination) {
        guard orderPhase == nil, !isAddingToBag, proofApproved else { return }
        let size = MultiPhotoFrameCatalog.size(forPhotos: shownCells.count)
        let items = shownCells
        if destination == .bag { isAddingToBag = true }
        Task {
            defer { isAddingToBag = false }
            do {
                orderPhase = .rendering
                let cellPixels = size.printPixels.width / CGFloat(size.columns)
                var prints: [UIImage] = []
                for item in items {
                    switch item {
                    case .run(let run):
                        guard let reference = run.photoReferences.first else { continue }
                        if let image = await PhotoLibrary.image(
                            for: reference,
                            targetSize: CGSize(width: cellPixels, height: cellPixels)
                        ) { prints.append(image) }
                    case .added(let photo):
                        prints.append(photo.image)
                    }
                }
                guard !prints.isEmpty else {
                    orderPhase = nil
                    orderError = "Those photos couldn't be loaded at print size."
                    return
                }
                let fileURL = try await PhotoWallRenderer.printFile(photos: prints, size: size)
                defer { try? FileManager.default.removeItem(at: fileURL) }
                let creationID = "photowall-\(size.sku)-\(items.count)-\(UUID().uuidString)"
                let frame = wallFrame
                switch destination {
                case .checkout:
                    let cart = try await PrintOrderService.checkout(
                        fileAt: fileURL,
                        pixels: size.printPixels,
                        creationID: creationID,
                        shopifySKU: size.sku,
                        prodigiSKU: size.sku,
                        productHandle: MultiPhotoFrameCatalog.shopifyHandle,
                        finishAttribute: frame,
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
                        pixels: size.printPixels,
                        creationID: creationID,
                        shopifySKU: size.sku,
                        prodigiSKU: size.sku,
                        productHandle: MultiPhotoFrameCatalog.shopifyHandle,
                        finishAttribute: frame,
                        title: "Photo Wall",
                        detail: "\(size.label) · \(items.count) photos · \(frame.capitalized) frame",
                        priceCents: MultiPhotoFrameCatalog.priceCents,
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

    private var filterMenu: some View {
        let stats = RunStatistics(photoRuns)
        let years = stats.years
        let grouped = Dictionary(grouping: photoRuns.filter { !($0.state ?? "").isEmpty },
                                 by: { PlaceNames.canonicalState($0.state) ?? "" })
        let states = grouped.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        let places = stats.travelPlaces
        return Menu {
            Button { filter = .all } label: {
                Label("All Photos", systemImage: filter == .all ? "checkmark" : "square.grid.2x2")
            }
            if !years.isEmpty {
                Menu("Year") {
                    ForEach(years, id: \.self) { year in
                        Button(String(year)) { filter = .year(year) }
                    }
                }
            }
            if !states.isEmpty {
                Menu("State") {
                    ForEach(states, id: \.name) { state in
                        Button("\(state.name)  ·  \(state.count)") { filter = .state(state.name) }
                    }
                }
            }
            if !places.isEmpty {
                Menu("Location") {
                    ForEach(places) { place in
                        Button("\(cityLabel(place))  ·  \(place.runs.count)") {
                            filter = .place(cityLabel(place))
                        }
                    }
                }
            }
        } label: {
            menuChip(icon: "line.3.horizontal.decrease", text: filterLabel)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach([SortOrder.newest, .oldest, .location]) { option in
                Button(option.rawValue) { sort = option }
            }
        } label: {
            menuChip(icon: "arrow.up.arrow.down", text: sort == .random ? "Shuffled" : sort.rawValue)
        }
    }

    private var shuffleButton: some View {
        Button { shuffle() } label: {
            menuChip(icon: "shuffle", text: "Shuffle")
        }
        .buttonStyle(.plain)
    }

    private func menuChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.etch(.subheadline, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.1), in: .capsule)
    }

    private var addPhotosButton: some View {
        PhotosPicker(
            selection: $picking,
            maxSelectionCount: maxPhotos,
            matching: .images,
            photoLibrary: .shared()
        ) {
            Label(isImporting ? "Adding…" : "Add photos", systemImage: "photo.badge.plus")
                .font(.etch(.subheadline, weight: .medium))
        }
        .buttonStyle(.etchSecondary)
        .disabled(isImporting)
        .onChange(of: picking) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
    }

    @MainActor
    private func importPicked(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false; picking = [] }
        var loaded: [AddedPhoto] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            loaded.append(AddedPhoto(image: image))
        }
        guard !loaded.isEmpty else { return }
        withAnimation(Theme.gentle) {
            addedPhotos.append(contentsOf: loaded)
            count = min(maxPhotos, count + loaded.count)
        }
    }

    private func shuffle() {
        randomOrder = filtered.map(\.id).shuffled()
        sort = .random
    }

    private func clampCount() {
        count = min(count, maxCount)
        if count < 1 { count = 1 }
    }

    private let posterWidth: CGFloat = 1000
    private let posterPadding: CGFloat = 28
    private let posterSpacing: CGFloat = 4

    private var posterCell: CGFloat {
        let cols = CGFloat(columnCount)
        return (posterWidth - posterPadding * 2 - posterSpacing * (cols - 1)) / cols
    }

    private var posterHeight: CGFloat {
        let rows = Int(ceil(Double(shownCells.count) / Double(columnCount)))
        return posterPadding * 2 + CGFloat(rows) * posterCell + CGFloat(max(0, rows - 1)) * posterSpacing
    }

    private var posterContent: some View {
        let cols = columnCount
        let rows = shownCells.chunked(into: cols)
        return VStack(spacing: posterSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: posterSpacing) {
                    ForEach(row) { item in
                        exportCell(item)
                    }
                    if row.count < cols {
                        ForEach(0..<(cols - row.count), id: \.self) { _ in
                            Color.clear.frame(width: posterCell, height: posterCell)
                        }
                    }
                }
            }
        }
        .padding(posterPadding)
        .frame(width: posterWidth, height: posterHeight)
        .background(Theme.Palette.bone)
    }

    private func exportCell(_ item: WallCell) -> some View {
        Group {
            if let image = photo(for: item) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.Palette.stone)
            }
        }
        .frame(width: posterCell, height: posterCell)
        .clipped()
        .clipShape(.rect(cornerRadius: 3))
    }

    @MainActor
    private func loadAndRender() async {
        // The wall changed under any prepared cart or approved proof — neither covers it now.
        preparedCart = nil
        proofApproved = false
        for run in shown {
            guard images[run.id] == nil, let id = run.photoReferences.first else { continue }
            if let img = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 600, height: 600)) {
                images[run.id] = img
            }
        }
        guard !shownCells.isEmpty else { posterImage = nil; return }
        let renderer = ImageRenderer(content: posterContent)
        renderer.scale = 3
        posterImage = renderer.uiImage
    }
}

private struct CheckoutTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
