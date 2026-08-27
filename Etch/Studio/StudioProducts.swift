import SwiftUI
import SwiftData

/// What Etch Studio sells, as a customer would name it. The storefront leads with these four
/// objects rather than with the user's activity list: a shop shows products, and the activity
/// is a *choice made inside* buying one — the order Tesla uses, and the reason their
/// configurator is ten taps rather than seventy.
enum StudioProduct: String, CaseIterable, Identifiable {
    case mapPoster, galleryPoster, medalFrame, yearBook, wallArt
    var id: String { rawValue }

    /// The products the storefront currently offers. The medal frame is built but withheld until
    /// its SKU is confirmed against the live catalog — the range PDF names the prefix
    /// (MEDAL-FRA-CLA) and the geometry, not the orderable code, and this shop has never listed
    /// something it can't actually make.
    static var offered: [StudioProduct] {
        allCases.filter { $0 != .medalFrame || MedalFrameCatalog.isAvailable }
    }

    var name: String {
        switch self {
        case .mapPoster:     return "Map Poster"
        case .galleryPoster: return "Gallery Poster"
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
        case .medalFrame:    return "The medal, and the day you earned it."
        case .yearBook:      return "A year of it, bound."
        case .wallArt:       return "Everything you've run, as one object."
        }
    }

    var priceLine: String {
        switch self {
        case .yearBook:
            return BookCatalog.price
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

    /// Wholesale is £70 before shipping from the UK, which is the highest landed cost in the
    /// range — the retail rung is set once a real quote lands, not from the range sheet.
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
