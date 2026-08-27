import SwiftUI
import SwiftData

/// What Etch Studio sells, as a customer would name it. The storefront leads with these four
/// objects rather than with the user's activity list: a shop shows products, and the activity
/// is a *choice made inside* buying one — the order Tesla uses, and the reason their
/// configurator is ten taps rather than seventy.
enum StudioProduct: String, CaseIterable, Identifiable {
    case mapPoster, galleryPoster, photoWall, medalFrame, yearBook, wallArt
    var id: String { rawValue }

    /// The products the storefront currently offers. The medal frame is built but withheld until
    /// its SKU is confirmed against the live catalog — the range PDF names the prefix
    /// (MEDAL-FRA-CLA) and the geometry, not the orderable code, and this shop has never listed
    /// something it can't actually make.
    static var offered: [StudioProduct] {
        allCases.filter { product in
            switch product {
            case .medalFrame: return MedalFrameCatalog.isAvailable
            case .photoWall:  return MultiPhotoFrameCatalog.isAvailable
            default:          return true
            }
        }
    }

    var name: String {
        switch self {
        case .mapPoster:     return "Map Poster"
        case .galleryPoster: return "Gallery Poster"
        case .photoWall:     return "Photo Wall"
        case .medalFrame:    return "Medal Frame"
        case .yearBook:      return "Year Book"
        case .wallArt:       return "Wall Art"
        }
    }

    /// One line, in the brand's voice — what the object *is*, never a spec.
    var line: String {
        switch self {
        case .mapPoster:     return "One route, over real geography."
        case .galleryPoster: return "Photos, map and elevation, composed."
        case .photoWall:     return "Twenty runs, one frame."
        case .medalFrame:    return "The medal, and the day you earned it."
        case .yearBook:      return "A year of it, bound."
        case .wallArt:       return "Everything you've run, as one object."
        }
    }

    var priceLine: String {
        switch self {
        case .yearBook:
            return BookCatalog.price
        case .photoWall:
            return MultiPhotoFrameCatalog.price
        case .medalFrame:
            return MedalFrameCatalog.price
        default:
            let from = PrintProduct.print.sizes.first?.price ?? "$59"
            return "From \(from)"
        }
    }

    /// Whether choosing this product asks which activity it's made from.
    var needsSubject: Bool {
        self == .mapPoster || self == .galleryPoster || self == .medalFrame
    }

    /// Every tile is the same square, whatever shape the object inside it is.
    ///
    /// Letting each tile take its product's aspect put the grid on two baselines — a landscape
    /// book came out short beside a tall poster, and the captions beneath them started at
    /// different heights and ran into the next row. Sizing the tile to the *shelf* instead of to
    /// the object, and fitting the artwork inside it on a mat, means a portrait poster, a
    /// landscape book and a deep frame all sit on one line. It is also how a shop photographs a
    /// mixed range: identical frames, different things inside them.
    static let tileAspect: CGFloat = 1.0

    /// Shown until this product's own preview has rendered.
    var placeholderSymbol: String {
        switch self {
        case .yearBook:   return "book.pages"
        case .photoWall:  return "square.grid.3x3"
        case .medalFrame: return "medal"
        default:          return "photo.artframe"
        }
    }

    var family: PosterFamily { self == .galleryPoster ? .gallery : .map }
}

/// The medal display frame: a classic frame with a double mount whose pre-cut aperture holds the
/// medals, and a printed panel beside them carrying the race.
///
/// Verified against the live catalog: "Classic Medal Display Frame, LPP, 30x40 / 12x16"" — one
/// size, printed on 240gsm lustre photo paper, snow-white top mount over a black or navy bottom
/// mount, eight frame colours, Perspex glaze, made in the UK.
///
/// Its print area is **2397 × 3000**, which is neither the 2:3 every other poster uses nor the
/// clean 2400 × 3000 the range sheet's "8x10 inch" implies. Three pixels of difference is enough
/// to matter on a mount with a pre-cut aperture, so the artwork is composed to the number the
/// API gives rather than to the one the brochure rounds to.
enum MedalFrameCatalog {

    /// The orderable code, taken verbatim from the product page's own HTML.
    ///
    /// `MOUNT` sits in the middle of it, which is why twenty-four suffixes guessed off the
    /// range sheet's `MEDAL-FRA-CLA` prefix all 404'd. Guessing a SKU from a prefix has now
    /// failed twice; reading the product page has worked twice.
    static let sku = "MEDAL-FRA-CLA-MOUNT-30X40"

    /// The storefront lists this product only once its landed cost is known and a retail rung is
    /// set — the frame is £70 wholesale before UK shipping, the dearest thing in the range, so a
    /// guessed price would be a guess at a loss. Setting `prices.medalFrameCents` in the served
    /// configuration turns it on, with no build.
    static var isAvailable: Bool { EtchConfig.current.prices.medalFrameCents != nil }

    /// The aperture the artwork is composed for, exactly as the catalog reports it.
    static let printPixelSize = CGSize(width: 2397, height: 3000)
    static var aspect: CGFloat { printPixelSize.width / printPixelSize.height }

    /// Quoted live to a US address: **items $95.12 + shipping $55.78 = $150.90 landed.**
    ///
    /// That shipping figure is the problem, not the frame. It is 37% of the landed cost, because
    /// this is the one product in the range made only in the UK — every other item has a US or EU
    /// line. At the range's usual 55% margin the rung would be about $335, roughly three Year
    /// Books, which is a different shop from the one the rest of the catalogue describes.
    ///
    /// So no price is set here. `prices.medalFrameCents` stays nil and the product stays unlisted
    /// until that is a deliberate decision rather than a default.
    static var price: String {
        guard let cents = EtchConfig.current.prices.medalFrameCents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// Frame colour — the `color` attribute, in the exact strings the catalog accepts.
    static let frameColours = ["black", "brown", "dark grey", "gold",
                               "light grey", "natural", "silver", "white"]

    /// Bottom mount under the snow-white top — the `mountColor` attribute. Capitalised, unlike
    /// `color`, which is the catalog's inconsistency and not ours to tidy: a quote is rejected
    /// without both attributes, and rejected again if either is spelled the other way.
    static let mountColours = ["Black", "Navy"]
}

/// The Photo Wall's object: a classic frame whose mount is cut with one aperture per photo.
///
/// From Prodigi's range sheet: 9 to 60 images, each printed at **60×60mm with a 20mm border**
/// between apertures, on enhanced matte art paper behind Perspex in a satin-laminated classic
/// frame. Frame sizes 12×12" to 24×36", eight frame colours, mounted or unmounted. Made in the
/// UK, EU *and US* — unlike the medal frame, so a US buyer isn't paying transatlantic shipping.
enum MultiPhotoFrameCatalog {

    /// Verified SKUs. Two families, and the difference matters: `MPF` is **No Mount / No Mat**,
    /// so the whole print area is one image and any grid is ours to draw; `MPFM` is
    /// **Mounted / Matted** with a 2.4mm snow-white mount, which is the version whose windows are
    /// physically cut — the one Prodigi's own artwork templates are drawn for.
    static let skuPrefix = "GLOBAL-MPF"
    static let mountedSKUPrefix = "GLOBAL-MPFM"

    /// The three grids Prodigi's artwork templates lay out, each now tied to the SKU whose print
    /// area matches it to the millimetre. The templates are drawn landscape while the catalog
    /// reports portrait print areas, so the same SKU turned on its side.
    struct Layout {
        let name: String
        let columns: Int
        let rows: Int
        /// Glaze size in millimetres, landscape — the frame's own size, not counting moulding.
        let widthMM: CGFloat
        let heightMM: CGFloat
        /// Unmounted SKU. The mounted variant swaps MPF for MPFM.
        let sku: String
        var mountedSKU: String { sku.replacingOccurrences(of: "GLOBAL-MPF-", with: "GLOBAL-MPFM-") }
        var capacity: Int { columns * rows }
    }

    /// Sizes confirmed against the live catalog: 20X30's print area is 5905×8858px, exactly
    /// 500×750mm, which is the L template turned upright; 24X36's is 7086×10629, exactly
    /// 600×900mm, the XL template. 16X24 follows the same pattern at 400×600mm.
    static let layouts = [
        Layout(name: "M",  columns: 6,  rows: 4, widthMM: 600, heightMM: 400, sku: "GLOBAL-MPF-16X24"),
        Layout(name: "L",  columns: 8,  rows: 5, widthMM: 750, heightMM: 500, sku: "GLOBAL-MPF-20X30"),
        Layout(name: "XL", columns: 10, rows: 6, widthMM: 900, heightMM: 600, sku: "GLOBAL-MPF-24X36")
    ]

    /// The grid a given count fills exactly, when there is one. A wall that matches its frame's
    /// arrangement is a preview of the object; one that doesn't is a picture of something else.
    static func exactLayout(forPhotos count: Int) -> Layout? {
        layouts.first { $0.capacity == count }
    }

    /// Forty: the L frame, 8×5, filled to the corner. The frame accepts nine to sixty, but a
    /// count that leaves a ragged last row makes a worse object than one that doesn't.
    static let defaultPhotos = 40
    static let minPhotos = 9
    static let maxPhotos = 60

    /// Each aperture, in millimetres, and the mount border between them.
    static let cellMM: CGFloat = 60
    static let borderMM: CGFloat = 20

    /// One cell at 300 DPI: 60mm ≈ 2.362 inches, so 709px square.
    static var cellPixels: CGFloat { (cellMM / 25.4) * 300 }

    /// The full print area for a layout, from its glaze size at 300 DPI — the number an order
    /// has to supply, and nowhere near the 1000px the shared image renders at. L is 8858×5905
    /// landscape; XL is 10629×7086.
    static func printPixelSize(for layout: Layout) -> CGSize {
        CGSize(width: (layout.widthMM / 25.4) * 300, height: (layout.heightMM / 25.4) * 300)
    }

    static var isAvailable: Bool { EtchConfig.current.prices.photoWallCents != nil }

    static var price: String {
        guard let cents = EtchConfig.current.prices.photoWallCents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static let frameColours = ["black", "brown", "dark grey", "gold",
                               "light grey", "natural", "silver", "white"]

    /// The mounted variant offers exactly one mount colour, whatever the range sheet's
    /// "Snow white, Black, Off-white" suggests — the catalog reports `mountColor: ["Snow white"]`.
    static let mountColours = ["Snow white"]
}

/// A poster *finish* rather than a product: the same fine-art print, shipped with a solid wood
/// magnetic hanger instead of a frame. Cheapest finish in the range (£7 wholesale and up), made
/// in the UK, US and EU, offered from 6×8" up to A0.
///
/// One geometry consequence the print engine has to respect: **the wooden strips cover up to
/// 15mm of the print at the top and bottom**. Anything inside that band — a title, a date line —
/// is hidden by the hanger, so a hung edition needs deeper top and bottom margins than a framed
/// one, not the same ones.
enum PosterHangerCatalog {

    static let skuPrefix = "POSTER-HANGER"

    /// Codes read off the product page and confirmed live. The shape is
    /// `POSTER-HANGER-<hanger cm>-<print size>-<orientation>`, so the hanger's own width is part
    /// of the code rather than an attribute — a 24×36" portrait print takes the 60cm hanger.
    ///
    /// The one that matters most: **`POSTER-HANGER-60-24X36-PORT` has a 7200 × 10800 print
    /// area — identical to `GLOBAL-HGE-24X36` and `GLOBAL-CFP-24X36`.** The hanger is a drop-in
    /// finish for artwork the Studio already composes, on the same EMA 200gsm stock as the
    /// framed line. No new geometry, no new render.
    static let confirmed = [
        "POSTER-HANGER-20-6X8-PORT":     CGSize(width: 1800, height: 2400),
        "POSTER-HANGER-30-12X12-SQUARE": CGSize(width: 3600, height: 3600),
        "POSTER-HANGER-30-A3-PORT":      CGSize(width: 3507, height: 4960),
        "POSTER-HANGER-60-24X36-PORT":   CGSize(width: 7200, height: 10800),
        "POSTER-HANGER-80-24X32-LAND":   CGSize(width: 9600, height: 7200)
    ]

    /// The size the poster line already renders, so the first finish to offer.
    static let sku24x36 = "POSTER-HANGER-60-24X36-PORT"

    /// How much of the print each wooden strip hides, top and bottom.
    static let hangerCoverMM: CGFloat = 15

    /// The same at 300 DPI, which is what the composition has to keep clear. On a 24×36" print
    /// that is 177px of the 10800 at each end — small in proportion, and exactly where the
    /// poster puts its title and date line, so a hung edition cannot reuse the framed margins.
    static var hangerCoverPixels: CGFloat { (hangerCoverMM / 25.4) * 300 }

    /// The `color` attribute's accepted values. The range sheet says "natural oak"; the catalog
    /// takes plain `natural`, and a quote is rejected on the sheet's wording.
    static let hangerColours = ["black", "natural", "white"]

    /// The 12×18" and 16×24" hangers were not on the product page, so the finish is offered at
    /// 24×36" only until they are confirmed the same way.
    static var isAvailable: Bool { false }
}

/// Chooses the activity a poster is made from — reached *after* picking a product, which is
/// why it can afford to be a proper picker with the standouts first: Milestones, Races,
/// Favorites, then everything recent. This replaces four near-identical shelves that used to
/// sit on the storefront pretending to be merchandise.
struct ActivityPickerSheet: View {
    let runs: [Run]
    let scope: ActivityScope
    let onPick: (Run) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var mapped: [Run] { runs.scoped(to: scope).filter(\.hasRoute) }
    private var stats: RunStatistics { RunStatistics(runs.scoped(to: scope)) }

    private var filtered: [Run] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return mapped }
        return mapped.filter { RunSearch.matches($0, query: trimmed) }
    }

    /// The standouts, each with the label that earns its place.
    private var milestones: [(Run, String)] {
        var out: [(Run, String)] = []
        if let r = stats.longestRun, r.hasRoute { out.append((r, "Furthest")) }
        if scope.usesPace, let r = stats.fastestRun, r.hasRoute { out.append((r, "Fastest")) }
        if let r = stats.highestClimb, r.hasRoute { out.append((r, "Highest")) }
        var seen = Set<UUID>()
        return out.filter { seen.insert($0.0.id).inserted }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if query.isEmpty {
                        if !milestones.isEmpty {
                            section("Milestones") {
                                grid(milestones.map { ($0.0, $0.1) })
                            }
                        }
                        let races = mapped.filter(\.isRace)
                        if !races.isEmpty {
                            section("Races") { grid(races.prefix(12).map { ($0, nil) }) }
                        }
                        let favorites = mapped.filter(\.isFavorite)
                        if !favorites.isEmpty {
                            section("Favorites") { grid(favorites.prefix(12).map { ($0, nil) }) }
                        }
                        section("Recent") { grid(mapped.prefix(30).map { ($0, nil) }) }
                    } else {
                        section("Results") { grid(filtered.prefix(40).map { ($0, nil) }) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $query, prompt: "Search your activities")
            .navigationTitle("Choose an activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func grid<S: Sequence>(_ items: S) -> some View where S.Element == (Run, String?) {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(items), id: \.0.id) { run, caption in
                Button {
                    onPick(run)
                    dismiss()
                } label: {
                    RunMonthTile(run: run, corner: 14)
                        .frame(height: 190)
                        .overlay(alignment: .topLeading) {
                            if let caption {
                                Text(caption.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .tracking(1)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Theme.accent, in: .capsule)
                                    .padding(9)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
