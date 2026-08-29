import Foundation

/// One book page, in PDF order: the first spec becomes the front cover, the last the back cover
/// (per the layflat print guide), everything between is interior content.
///
/// None of these carry the year any more. A page that prints "2025" in a Year in Review prints
/// "Colorado" on a Collection, and the thing it prints is the plan's `subject` — so the spec says
/// *which page this is* and the plan says *what the book is about*.
enum BookPageSpec {
    case cover
    case title
    case stats
    /// A month, or a whole year when the subject spans too many months to give each one a page.
    case chapter(start: Date)
    case race(runIndex: Int)
    case closing
    case blank
    case backCover
}

/// A book's plan: which pages exist and in what order, derived from a subject and a history.
/// Pure derivation — rendering happens in `BookRenderer`, and the plan carries the selected runs
/// so every page spec can resolve its content from one source.
struct BookPlan {

    /// How the interior is divided. A year's twelve months each earn a page; a collection can span
    /// a decade, and 120 month pages would blow straight through the lab's 122-page ceiling, so a
    /// long collection is chaptered by year instead.
    enum ChapterSpan {
        case month, year

        func start(of date: Date, _ calendar: Calendar) -> Date {
            let components: Set<Calendar.Component> = self == .month ? [.year, .month] : [.year]
            return calendar.date(from: calendar.dateComponents(components, from: date)) ?? date
        }
    }

    let subject: BookSubject
    /// The subject's activities, ascending by date.
    let runs: [Run]
    let pages: [BookPageSpec]
    let chapterSpan: ChapterSpan

    var pageCount: Int { pages.count }

    /// Whether a chapter heading has to name its year. Within one calendar year "MARCH" is
    /// unambiguous; across a collection spanning several it is not.
    var chapterNamesYear: Bool {
        chapterSpan == .year || subject.kind == .collection
    }

    /// Race pages are the book's set pieces; capped so a heavy race history stays inside the page
    /// envelope. A Races collection is *all* races, which is exactly the case this protects.
    private static let raceBudget = 24
    /// The most chapters that can each take their own page before the book switches to years.
    private static let chapterBudget = 60

    /// Builds the plan: cover → title → stats → a page per active chapter, each chapter's race
    /// pages following it → closing → back cover; padded with blanks to Prodigi's even-count and
    /// minimum-pages rules, and trimmed to its maximum.
    static func make(subject: BookSubject, runs: [Run]) -> BookPlan {
        let calendar = Calendar.current
        let selected = runs.filter(subject.matches).sorted { $0.startDate < $1.startDate }

        let months = Set(selected.map { ChapterSpan.month.start(of: $0.startDate, calendar) })
        let span: ChapterSpan = months.count <= chapterBudget ? .month : .year

        var pages: [BookPageSpec] = [.cover, .title, .stats]

        let byChapter = Dictionary(grouping: selected) { span.start(of: $0.startDate, calendar) }
        var racesUsed = 0
        for start in byChapter.keys.sorted() {
            pages.append(.chapter(start: start))
            let chapterRaces = (byChapter[start] ?? []).filter(\.isRace)
            for race in chapterRaces where racesUsed < raceBudget {
                if let index = selected.firstIndex(where: { $0.id == race.id }) {
                    pages.append(.race(runIndex: index))
                    racesUsed += 1
                }
            }
        }

        pages.append(.closing)

        // Pad to the minimum interior size, then to an even total, with quiet blanks before the
        // back cover.
        while pages.count + 1 < BookCatalog.minPages { pages.append(.blank) }
        if (pages.count + 1) % 2 != 0 { pages.append(.blank) }

        // A last, defensive trim. The budgets above should already hold the book inside the
        // envelope; if a history ever finds a shape they don't, the lab rejects the file rather
        // than printing a short book, so the ceiling is enforced here too.
        if pages.count + 1 > BookCatalog.maxPages {
            pages = Array(pages.prefix(BookCatalog.maxPages - 1))
            if (pages.count + 1) % 2 != 0 { pages.removeLast() }
        }
        pages.append(.backCover)

        return BookPlan(subject: subject, runs: selected, pages: pages, chapterSpan: span)
    }

    /// The run a race page shows.
    func run(at index: Int) -> Run? {
        runs.indices.contains(index) ? runs[index] : nil
    }

    /// A chapter page's activities.
    func chapterRuns(_ start: Date) -> [Run] {
        let calendar = Calendar.current
        return runs.filter { chapterSpan.start(of: $0.startDate, calendar) == start }
    }
}
