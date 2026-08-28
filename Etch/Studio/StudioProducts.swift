import SwiftUI
import SwiftData
import UIKit

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
        case .wallArt:       return "Anthology"
        }
    }

    /// One line, in the brand's voice — what the object *is*, never a spec.
    var line: String {
        switch self {
        case .mapPoster:     return "One route, over real geography."
        case .galleryPoster: return "Photos, map and elevation, composed."
        case .photoWall:     return "Forty days, one frame."
        case .medalFrame:    return "The medal, and the day you earned it."
        case .yearBook:      return "A year of it, bound."
        case .wallArt:       return "Everything you've done, as one object."
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
    /// **Set at $249**, deliberately below that. It earns 39.4% gross, 36.4% after payment fees —
    /// $90.58 a frame — against the 45–62% the rest of the range makes. The trade was made with
    /// the numbers in view: a medal frame is bought once, for a race someone trained a year for,
    /// and pricing it like three Year Books loses the sale rather than the margin. It is the
    /// thinnest rung in the catalogue and the first one a shipping change should be re-checked
    /// against; `prices.medalFrameCents` moves it from the served document without a build.
    static var price: String {
        guard let cents = EtchConfig.current.prices.medalFrameCents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// The product's URL handle in Shopify, whose variant carries the retail price at checkout.
    static let shopifyHandle = "medal-frame"

    /// Frame colour — the `color` attribute, in the exact strings the catalog accepts.
    static let frameColours = ["black", "brown", "dark grey", "gold",
                               "light grey", "natural", "silver", "white"]

    /// Bottom mount under the snow-white top — the `mountColor` attribute. Capitalised, unlike
    /// `color`, which is the catalog's inconsistency and not ours to tidy: a quote is rejected
    /// without both attributes, and rejected again if either is spelled the other way.
    static let mountColours = ["Black", "Navy"]
}

/// The Photo Wall's object: a contact sheet, printed as one image, in a classic frame.
///
/// The catalog corrected two things this was built on, and both mattered.
///
/// **The frame has no mount.** `GLOBAL-MPF-*` reports `mount: ["No mount / No Mat"]` — the whole
/// print area is a single continuous image. The mounted line (`GLOBAL-MPFM-*`), whose windows are
/// physically cut, exists only at 12X18, 16X16 and 24X24; there is no `MPFM-20X30`, so the
/// `mountedSKU` this used to synthesise by swapping `MPF` for `MPFM` named a product that does not
/// exist. Guessing a SKU from a pattern has now failed four times out of four here.
///
/// That is good news for the design: the grid, the gutters and the margins are all ours to draw,
/// and nothing has to line up with a physical aperture. It does mean the mockup must not draw a
/// cut mount with a bevel — that would promise an object nobody will receive.
///
/// **The frames are portrait, not landscape.** 20X30's print area is 5905 × 8858 — 500 × 750mm
/// upright. A forty-photo wall laid out eight columns wide was a landscape arrangement bound for
/// a portrait sheet, which the lab cannot rotate. Five across and eight down is the same forty
/// photographs in the shape the paper actually is.
///
/// Made in the UK, EU *and US*, so a US buyer isn't paying transatlantic shipping — unlike the
/// medal frame, and the reason this is the better product to lead with.
enum MultiPhotoFrameCatalog {

    static let skuPrefix = "GLOBAL-MPF"

    /// One frame size and the grid Etch prints into it.
    ///
    /// `printPixels` is quoted verbatim from the live catalog rather than derived from the stated
    /// centimetres — the medal frame taught us those disagree, and by enough to matter.
    struct Size {
        let name: String
        let sku: String
        /// Exactly as the catalog reports it.
        let printPixels: CGSize
        let columns: Int
        let rows: Int
        var capacity: Int { columns * rows }

        /// `GLOBAL-MPF-20X30` → `20 × 30″`.
        var label: String {
            sku.replacingOccurrences(of: "GLOBAL-MPF-", with: "")
               .replacingOccurrences(of: "X", with: " × ") + "″"
        }

        /// How square each photograph comes out. Cells are near-square by construction, never
        /// exactly so on every size: five columns and eight rows on a 2:3 sheet gives a cell of
        /// 1.07:1, which no eye reads as a rectangle.
        var cellAspect: CGFloat {
            (printPixels.width / CGFloat(columns)) / (printPixels.height / CGFloat(rows))
        }
    }

    /// The three sizes confirmed against the live catalog, each with a grid chosen for its shape.
    ///
    /// 12X12 is square, so 4×4 gives exactly square cells. 24X36 is 2:3, and 6×9 is 2:3, so its
    /// cells are exactly square too. 20X30 takes 5×8 — 40 photographs, the wall's default, at a
    /// cell 7% off square, which is the price of the count and cheap at that.
    static let sizes = [
        Size(name: "Square", sku: "GLOBAL-MPF-12X12",
             printPixels: CGSize(width: 3543, height: 3543), columns: 4, rows: 4),
        Size(name: "Standard", sku: "GLOBAL-MPF-20X30",
             printPixels: CGSize(width: 5905, height: 8858), columns: 5, rows: 8),
        Size(name: "Large", sku: "GLOBAL-MPF-24X36",
             printPixels: CGSize(width: 7086, height: 10629), columns: 6, rows: 9)
    ]

    /// The size a count fills exactly, when one does.
    static func exactSize(forPhotos count: Int) -> Size? {
        sizes.first { $0.capacity == count }
    }

    /// The size a count would actually be made in: the one it fills exactly, else the smallest
    /// that holds it, else the largest there is.
    static func size(forPhotos count: Int) -> Size {
        exactSize(forPhotos: count)
            ?? sizes.first { $0.capacity >= count }
            ?? sizes[sizes.count - 1]
    }

    /// The line the wall shows, so choosing a count is choosing an object rather than a screenshot.
    static func fitDescription(forPhotos count: Int) -> String {
        let size = size(forPhotos: count)
        let spare = size.capacity - count
        if spare <= 0 { return "Fills the \(size.label) frame — \(size.columns) × \(size.rows)." }
        return "\(size.label) frame · room for \(spare) more."
    }

    /// Forty: five across, eight down, filling the 20 × 30″ sheet to its corners.
    static let defaultPhotos = 40
    static let minPhotos = 9
    /// The largest grid any confirmed size takes — 6 × 9 on the 24 × 36″.
    static var maxPhotos: Int { sizes.map(\.capacity).max() ?? 54 }

    /// The gutter between photographs, as a fraction of the shorter cell edge. Ours to choose,
    /// now that no physical mount dictates it.
    static let gutterFraction: CGFloat = 0.06

    static var isAvailable: Bool { EtchConfig.current.prices.photoWallCents != nil }

    static var price: String {
        guard let cents = EtchConfig.current.prices.photoWallCents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static let frameColours = ["black", "brown", "dark grey", "gold",
                               "light grey", "natural", "silver", "white"]

    /// The Shopify product handle the wall's variants live under. Must match the store's product
    /// page exactly, the same join as `PrintProduct.shopifyHandle`.
    static let shopifyHandle = "photo-wall"
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

    /// The confirmed 2:3 portrait hangers, as the sizes the print catalogue speaks in. Only one
    /// so far: the 12×18" and 16×24" hangers weren't on the product page and have to be read off
    /// it the same way the others were before they can be listed.
    static let portraitSizes: [(width: Int, height: Int, sku: String)] = [
        (24, 36, sku24x36)
    ]

    /// Whether the finish can be offered at all — true once at least one confirmed size renders.
    ///
    /// This was false while the only confirmed portrait hanger was 24×36", needing a 10,800px
    /// long edge against a 6,000px single-bitmap ceiling: the cheapest finish in the range gated
    /// behind the same wall as the most expensive print. The banded writer took the wall down,
    /// so the gate now answers yes on the size that was already confirmed. It is still a real
    /// question — a future size could outrun the renderer — so it is still asked.
    static var isAvailable: Bool {
        portraitSizes.contains { size in
            let geometry = PrintGeometry(trimWidth: Double(size.width),
                                         trimHeight: Double(size.height))
            return geometry.isAcceptable(longEdgePixels: max(geometry.trimPixels.width,
                                                             geometry.trimPixels.height))
        }
    }

    /// Lays a rendered artwork onto the full sheet with the covered bands kept clear.
    ///
    /// The wooden strips hide 15mm at each end, so a hung print needs those bands to hold nothing
    /// but paper. Rather than reflow the composition for one finish — a second layout to design,
    /// proof and maintain — the artwork is placed inside the band-free box at its own proportions
    /// and the sheet around it is filled with the piece's own ground colour. What the wood covers
    /// is then ground, which is what it covers on any hung print.
    ///
    /// The leftover appears as a narrow margin at the sides (about 0.3″ on a 24×36), because a 2:3
    /// artwork fitted into a slightly squarer box is limited by height. That margin is real and
    /// visible, which is the point: the mockup draws it too.
    static func composite(artwork: UIImage, sheetPixels: CGSize, ground: UIColor) -> UIImage? {
        guard sheetPixels.width > 1, sheetPixels.height > 1 else { return nil }
        // `hangerCoverPixels` is quoted at 300 DPI and the sheet is rendered at 300 DPI, so it
        // applies directly. Clamped so a small sheet can never be reserved away to nothing.
        let band = min(hangerCoverPixels, sheetPixels.height * 0.1)

        let box = CGSize(width: sheetPixels.width, height: sheetPixels.height - band * 2)
        let art = artwork.size
        guard art.width > 0, art.height > 0, box.height > 0 else { return nil }
        let fit = min(box.width / art.width, box.height / art.height)
        let drawn = CGSize(width: art.width * fit, height: art.height * fit)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: sheetPixels, format: format).image { context in
            ground.setFill()
            context.fill(CGRect(origin: .zero, size: sheetPixels))
            artwork.draw(in: CGRect(
                x: (sheetPixels.width - drawn.width) / 2,
                y: (sheetPixels.height - drawn.height) / 2,
                width: drawn.width, height: drawn.height
            ))
        }
    }
}

/// Chooses the activity a poster is made from — reached *after* picking a product, which is
/// why it can afford to be a proper picker with the standouts first: Milestones, Races,
/// Favorites, then everything recent. This replaces four near-identical shelves that used to
/// sit on the storefront pretending to be merchandise.
struct ActivityPickerSheet: View {

    /// How the picker is organised.
    ///
    /// `curated` answers "make me something good": milestones first, then races, favourites, and
    /// the last thirty runs. `timeline` answers a different question — "the one from that Tuesday
    /// in March" — and for that a ranked shelf is useless. It shows everything, month by month,
    /// newest first, with nothing left out.
    enum Mode { case curated, timeline }

    let runs: [Run]
    let scope: ActivityScope
    var mode: Mode = .curated
    let onPick: (Run) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Narrows the timeline the way the map and the Anthology narrow themselves — the browse is
    /// the whole history, and a whole history needs a way to be less than whole.
    enum PickerFilter: Hashable {
        case all, races, favorites
        case year(Int)
        case type(ActivityScope)
    }
    @State private var filter: PickerFilter = .all

    private var mapped: [Run] {
        let base = runs.scoped(to: scope).filter(\.hasRoute)
        switch filter {
        case .all:            return base
        case .races:          return base.filter(\.isRace)
        case .favorites:      return base.filter(\.isFavorite)
        case .year(let y):    return base.filter { Calendar.current.component(.year, from: $0.startDate) == y }
        case .type(let t):    return base.scoped(to: t)
        }
    }
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

    /// Every mapped run grouped by the month it happened in, newest month first.
    private var months: [(label: String, runs: [Run])] {
        let calendar = Calendar.current
        let sorted = mapped.sorted { $0.startDate > $1.startDate }
        var order: [String] = []
        var buckets: [String: [Run]] = [:]
        for run in sorted {
            // The year is always spelled out except for the current one, where it is noise.
            let label = calendar.isDate(run.startDate, equalTo: .now, toGranularity: .year)
                ? run.startDate.formatted(.dateTime.month(.wide))
                : run.startDate.formatted(.dateTime.month(.wide).year())
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(run)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if mode == .timeline && query.isEmpty {
                        ForEach(months, id: \.label) { month in
                            section(month.label) { grid(month.runs.map { ($0, nil) }) }
                        }
                    } else if query.isEmpty {
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
            .navigationTitle(mode == .timeline ? "Your timeline" : "Choose an activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                if mode == .timeline {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu }
                }
            }
        }
    }

    /// Only options at least one activity answers to are offered, so a choice can never empty
    /// the sheet — the same rule the Anthology's filter follows.
    private var filterMenu: some View {
        let base = runs.scoped(to: scope).filter(\.hasRoute)
        let years = Set(base.map { Calendar.current.component(.year, from: $0.startDate) }).sorted(by: >)
        let types = [ActivityScope.runs, .hikes, .rides, .walks]
            .filter { scope == .all && ActivitySettings.isVisible($0) && !base.scoped(to: $0).isEmpty }
        return Menu {
            Button { filter = .all } label: {
                Label("Everything", systemImage: filter == .all ? "checkmark" : "square.grid.2x2")
            }
            if base.contains(where: \.isRace) {
                Button { filter = .races } label: {
                    Label("Races", systemImage: filter == .races ? "checkmark" : "flag.checkered")
                }
            }
            if base.contains(where: \.isFavorite) {
                Button { filter = .favorites } label: {
                    Label("Favorites", systemImage: filter == .favorites ? "checkmark" : "star")
                }
            }
            if years.count > 1 {
                Menu("Year") {
                    ForEach(years, id: \.self) { year in
                        Button(String(year)) { filter = .year(year) }
                    }
                }
            }
            if !types.isEmpty {
                Menu("Activity") {
                    ForEach(types) { type in
                        Button(type.label) { filter = .type(type) }
                    }
                }
            }
        } label: {
            Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle"
                                             : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter the timeline")
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
