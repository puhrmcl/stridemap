import Foundation
import CoreGraphics

/// What a book is *about*.
///
/// The book started as one product with one axis — a calendar year — and the year was baked into
/// every page spec as an `Int`. Collections need the same object bound around a different idea: a
/// state, a city, the runs someone starred, the days they pinned a number on. Rather than a second
/// renderer, the axis becomes a value: the plan filters by it, and every page that used to print a
/// year prints this instead.
enum BookSubject: Hashable, Identifiable {
    case year(Int)
    case state(String)
    /// The state is carried so two Springfields can't collapse into one book.
    case city(String, state: String)
    case favorites
    case races

    /// The two products these subjects are sold as. Same physical book, same SKU — a different
    /// question asked of the same history.
    enum Kind: String, Hashable { case year, collection }

    var kind: Kind {
        if case .year = self { return .year }
        return .collection
    }

    /// Stable across reorders, so a second copy of the same book is reproduced rather than
    /// re-imagined. Also the PDF's filename.
    var slug: String {
        switch self {
        case .year(let y):          return "year-\(y)"
        case .state(let s):         return "state-\(Self.slugify(s))"
        case .city(let c, let s):   return "city-\(Self.slugify(c))-\(Self.slugify(s))"
        case .favorites:            return "favorites"
        case .races:                return "races"
        }
    }

    var id: String { slug }

    /// The word on the cover.
    var title: String {
        switch self {
        case .year(let y):        return String(y)
        case .state(let s):       return s
        case .city(let c, _):     return c
        case .favorites:          return "Favorites"
        case .races:              return "Races"
        }
    }

    /// How the subject reads in the picker, where two cities can otherwise look identical.
    var menuLabel: String {
        if case .city(let c, let s) = self, !s.isEmpty { return "\(c), \(s)" }
        return title
    }

    /// The cover's eyebrow — what kind of year, or what kind of collection, this is.
    var eyebrow: String {
        switch self {
        case .year:       return "A YEAR IN MOTION"
        case .state:      return "EVERY MILE IN"
        case .city:       return "EVERY MILE IN"
        case .favorites:  return "THE ONES WORTH KEEPING"
        case .races:      return "EVERY START LINE"
        }
    }

    var isState: Bool { if case .state = self { return true }; return false }
    var isCity: Bool { if case .city = self { return true }; return false }

    /// Whether the book is *about* somewhere. A place book has already answered "where", which
    /// changes what its statistics page has left worth counting.
    var isPlace: Bool { isState || isCity }

    /// The line above the title page's masthead.
    var masthead: String { kind == .year ? "THE YEAR BOOK" : "A COLLECTION" }

    /// The product as the footer names it, and as it reads on a receipt.
    var productName: String { kind == .year ? BookCatalog.name : BookCatalog.collectionName }

    /// A long place name can't be set at the year's 120pt and still fit the sheet. The size is
    /// chosen by length and `minimumScaleFactor` catches whatever is longer still.
    var coverTitleSize: CGFloat {
        switch kind {
        case .year:       return 120
        case .collection: return title.count <= 8 ? 108 : 82
        }
    }

    /// Whether a run belongs in this book.
    func matches(_ run: Run) -> Bool {
        switch self {
        case .year(let y):
            return Calendar.current.component(.year, from: run.startDate) == y
        case .state(let s):
            return PlaceNames.canonicalState(run.state) == s
        case .city(let c, let s):
            return run.city == c && (PlaceNames.canonicalState(run.state) ?? "") == s
        case .favorites:
            return run.isFavorite
        case .races:
            return run.isRace
        }
    }

    private static func slugify(_ text: String) -> String {
        let allowed = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}

// MARK: - The lens — which sport the book sees

/// The second axis of a book: not *when* (the subject) but *what kind of motion*. A year of
/// everything is one book; the same year seen as only the rides is another. The lens filters,
/// renames the cover's eyebrow, and changes what the count complication counts — nothing else,
/// which is the point: one architecture, every sport.
enum BookLens: Hashable, Identifiable {
    case everything
    case sport(ActivityType)

    var id: String {
        if case .sport(let type) = self { return type.rawValue }
        return "everything"
    }

    /// Appended to the subject's slug so "2026" and "2026, just the rides" are two different
    /// production files that each reproduce exactly on a reorder.
    var slugSuffix: String {
        if case .sport(let type) = self { return "-\(type.rawValue)" }
        return ""
    }

    var menuLabel: String {
        switch self {
        case .everything: return "All Activity"
        case .sport(let type):
            switch type {
            case .run:  return "Runs"
            case .ride: return "Rides"
            case .hike: return "Hikes"
            case .walk: return "Walks"
            case .ski:  return "Ski Days"
            case .swim: return "Swims"
            case .row:  return "Rows"
            case .other: return "Other"
            }
        }
    }

    /// The year cover's eyebrow through this lens. Nil keeps the subject's own line.
    var yearEyebrow: String? {
        guard case .sport(let type) = self else { return nil }
        switch type {
        case .run:  return "A YEAR OF RUNNING"
        case .ride: return "A YEAR ON THE BIKE"
        case .hike: return "A YEAR ON THE TRAIL"
        case .walk: return "A YEAR ON FOOT"
        case .ski:  return "A YEAR ON SNOW"
        case .swim: return "A YEAR IN THE WATER"
        case .row:  return "A YEAR ON THE WATER"
        case .other: return nil
        }
    }

    /// What the count complication counts — "142 RUNS" reads better than "142 ACTIVITIES" when
    /// the whole book is runs. Nil for the everything lens, which really is activities.
    var countLabel: String? {
        guard case .sport = self else { return nil }
        return menuLabel.uppercased()
    }

    func matches(_ run: Run) -> Bool {
        guard case .sport(let type) = self else { return true }
        return run.activityType == type
    }

    /// The lenses this history supports: everything, plus each sport with enough activity to
    /// bind on its own — busiest first. A single-sport history offers no choice at all, which
    /// is why the picker only appears when there is one to make.
    static func offered(in runs: [Run]) -> [BookLens] {
        let bySport = Dictionary(grouping: runs, by: \.activityType)
        let sports = bySport
            .filter { $0.key != .other && $0.value.count >= BookSubject.minimumActivities }
            .sorted { $0.value.count > $1.value.count }
            .map { BookLens.sport($0.key) }
        // One qualifying sport that IS the whole history offers no real choice either.
        if sports.count == 1, bySport.count == 1 { return [.everything] }
        return sports.isEmpty ? [.everything] : [.everything] + sports
    }
}

// MARK: - What this history can actually be bound as

extension BookSubject {

    /// A book below this is mostly blank leaves at $119, which is not a product. The threshold
    /// keeps a subject out of the picker rather than letting someone buy a nearly empty book.
    static let minimumActivities = 12

    /// The years with enough activity to bind, most recent first.
    static func years(in runs: [Run]) -> [BookSubject] {
        let counts = runs.reduce(into: [Int: Int]()) { tally, run in
            tally[Calendar.current.component(.year, from: run.startDate), default: 0] += 1
        }
        return counts.filter { $0.value >= minimumActivities }
            .keys.sorted(by: >)
            .map { .year($0) }
    }

    /// The states with enough activity to bind, busiest first.
    static func states(in runs: [Run]) -> [BookSubject] {
        let counts = runs.reduce(into: [String: Int]()) { tally, run in
            guard let state = PlaceNames.canonicalState(run.state), !state.isEmpty else { return }
            tally[state, default: 0] += 1
        }
        return counts.filter { $0.value >= minimumActivities }
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { .state($0.key) }
    }

    /// The cities with enough activity to bind, busiest first. Capped, because a long history can
    /// carry a hundred of these and a menu is not an index.
    static func cities(in runs: [Run], limit: Int = 16) -> [BookSubject] {
        var counts: [String: (city: String, state: String, count: Int)] = [:]
        for run in runs {
            guard let city = run.city, !city.isEmpty else { continue }
            let state = PlaceNames.canonicalState(run.state) ?? ""
            let key = "\(city)|\(state)"
            let existing = counts[key]?.count ?? 0
            counts[key] = (city, state, existing + 1)
        }
        return counts.values
            .filter { $0.count >= minimumActivities }
            .sorted { ($0.count, $1.city) > ($1.count, $0.city) }
            .prefix(limit)
            .map { .city($0.city, state: $0.state) }
    }

    /// Every collection this history can be bound as, in the order the picker offers them: the
    /// two that need no place data first, then places by how much of the history happened there.
    static func collections(in runs: [Run]) -> [BookSubject] {
        var out: [BookSubject] = []
        if runs.filter(\.isFavorite).count >= minimumActivities { out.append(.favorites) }
        if runs.filter(\.isRace).count >= minimumActivities { out.append(.races) }
        out.append(contentsOf: states(in: runs))
        out.append(contentsOf: cities(in: runs))
        return out
    }

    /// The subjects offered for one product.
    static func offered(_ kind: Kind, in runs: [Run]) -> [BookSubject] {
        kind == .year ? years(in: runs) : collections(in: runs)
    }
}
