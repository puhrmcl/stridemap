import Foundation

/// One page of the Year Book, in PDF order: the first spec becomes the front cover, the last
/// the back cover (per the layflat print guide), everything between is interior content.
enum BookPageSpec {
    case cover(year: Int)
    case title(year: Int)
    case yearStats(year: Int)
    case month(monthStart: Date)
    case race(runIndex: Int)
    case closing(year: Int)
    case blank
    case backCover(year: Int)
}

/// The Year Book's plan: which pages exist and in what order, derived from one year of
/// activities. Pure derivation — rendering happens in `BookRenderer`, and the plan carries the
/// year's runs so every page spec can resolve its content from one source.
struct BookPlan {
    let year: Int
    /// The year's activities, ascending by date.
    let runs: [Run]
    let pages: [BookPageSpec]

    var pageCount: Int { pages.count }

    /// Builds the plan: cover → title → year stats → a page per active month, each month's
    /// race pages following it → closing → back cover; padded with blanks to Prodigi's even-count
    /// and minimum-pages rules, and race pages capped so the book stays within the envelope.
    static func make(year: Int, runs: [Run]) -> BookPlan {
        let calendar = Calendar.current
        let yearRuns = runs
            .filter { calendar.component(.year, from: $0.startDate) == year }
            .sorted { $0.startDate < $1.startDate }

        var pages: [BookPageSpec] = [.cover(year: year), .title(year: year), .yearStats(year: year)]

        // Months that actually have activity, in order.
        let byMonth = Dictionary(grouping: yearRuns) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.startDate))!
        }
        // Race pages are the book's set pieces; cap them so a heavy race year stays inside the
        // page envelope (cover+title+stats+12 months+closing+back ≈ 17 fixed pages).
        let raceBudget = 24
        var racesUsed = 0
        for monthStart in byMonth.keys.sorted() {
            pages.append(.month(monthStart: monthStart))
            let monthRaces = (byMonth[monthStart] ?? []).filter(\.isRace)
            for race in monthRaces where racesUsed < raceBudget {
                if let index = yearRuns.firstIndex(where: { $0.id == race.id }) {
                    pages.append(.race(runIndex: index))
                    racesUsed += 1
                }
            }
        }

        pages.append(.closing(year: year))

        // Pad to the minimum interior size, then to an even total, with quiet blanks before the
        // back cover.
        while pages.count + 1 < BookCatalog.minPages { pages.append(.blank) }
        if (pages.count + 1) % 2 != 0 { pages.append(.blank) }
        pages.append(.backCover(year: year))

        return BookPlan(year: year, runs: yearRuns, pages: pages)
    }

    /// The run a race page shows.
    func run(at index: Int) -> Run? {
        runs.indices.contains(index) ? runs[index] : nil
    }

    /// A month page's activities.
    func monthRuns(_ monthStart: Date) -> [Run] {
        let calendar = Calendar.current
        return runs.filter {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.startDate)) == monthStart
        }
    }
}
