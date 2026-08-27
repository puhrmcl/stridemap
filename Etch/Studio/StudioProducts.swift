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
/// Confirmed from Prodigi's range sheet: one size, 30x40cm (12x16") overall, with an 8x10"
/// Giclée print area on lustre paper — **4:5, not the 2:3 every other poster uses**, so the
/// artwork is composed for this frame rather than cropped into it. Snow-white top mount over a
/// black or navy bottom mount, eight frame colours, Perspex glaze, 300 DPI, made in the UK.
enum MedalFrameCatalog {

    /// The range sheet names this prefix; the orderable code adds a suffix that the live catalog
    /// has to confirm. Until `sku` is non-nil the product stays out of the storefront.
    static let skuPrefix = "MEDAL-FRA-CLA"

    /// Set once a probe resolves the full code. Nil means "not orderable yet", which is what
    /// keeps the tile hidden rather than showing a product that can't be bought.
    static let sku: String? = nil

    static var isAvailable: Bool { sku != nil }

    /// 8x10 inches at 300 DPI — the aperture the artwork is composed for.
    static let printPixelSize = CGSize(width: 2400, height: 3000)
    static let aspect: CGFloat = 0.8

    /// Wholesale is £70 before shipping from the UK, which is the highest landed cost in the
    /// range — the retail rung is set once a real quote lands, not from the range sheet.
    static var price: String {
        guard let cents = EtchConfig.current.prices.medalFrameCents else { return "—" }
        return (Double(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// The frame colours the range sheet lists, in its order.
    static let frameColours = ["Black", "White", "Natural", "Antique Silver",
                               "Brown", "Antique Gold", "Dark Grey", "Light Grey"]

    /// The bottom mount, under the snow-white top mount.
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
