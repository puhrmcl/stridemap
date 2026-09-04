import Foundation
import MapKit

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
    /// The achievements spread — what stood out, phrased by the StoryEngine.
    case marks
    /// THE MAP — the year's geography: states tinted by mileage, cities dotted, races starred.
    case map
    /// A month, or a whole year when the subject spans too many months to give each one a page.
    case chapter(start: Date)
    /// The pictures side of a chapter's two-page spread — the same month's photographs,
    /// facing its routes and numbers. Exists only when the chapter's activities carry photos.
    case chapterPhotos(start: Date)
    case race(runIndex: Int)
    /// The span-wide photo gallery — "IN PICTURES", near the back with the review.
    case gallery
    /// THE NUMBERS — the derived-insight ledger (time in motion, active days, biggest week…).
    case numbers
    /// "YOUR YEAR, ETCHED." — the emotional summary near the back.
    case review
    /// THE YEARS — every year on record as a ledger row, the book's own year marked. The
    /// first of the portfolio pages: the book ends by placing its span in a life.
    case years
    /// RACE HISTORY — the lifetime résumé of start lines, newest first.
    case raceHistory
    /// THE ATLAS — everywhere, ever: country outlines with a pin for every city in the
    /// whole history, and the lifetime line of numbers beneath.
    case atlas
    /// THE CITIES — the atlas's pins as a ledger: every city ever, counted and measured.
    case cities
    /// One page of the complete activity index; `offset` is the first entry it lists. This is
    /// what lets month pages breathe: nothing is ever dropped from the book, it moves here.
    case index(offset: Int)
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
    /// Which sport the book sees — everything, or one discipline.
    let lens: BookLens
    /// The subject's activities through the lens, ascending by date.
    let runs: [Run]
    /// The person's whole history, unfiltered — what the portfolio pages (the years, the race
    /// résumé, the atlas) read, and what makes "first ever" claims honest.
    let history: [Run]
    /// The reader's choices: which photos are in, which leads the cover, which cover style.
    let curation: BookCuration
    let pages: [BookPageSpec]
    let chapterSpan: ChapterSpan
    /// What the history *means* — marks, peaks, streaks, firsts — computed once here so every
    /// page reads the same story instead of re-deriving its own.
    let story: BookStory

    var pageCount: Int { pages.count }

    /// The production identity: subject + lens. "2026" and "2026, just the rides" are two
    /// different books and must reproduce as such.
    var slug: String { subject.slug + lens.slugSuffix }

    /// The cover's eyebrow: the lens speaks for a year it narrows; otherwise the subject does.
    var coverEyebrow: String {
        (subject.kind == .year ? lens.yearEyebrow : nil) ?? subject.eyebrow
    }

    /// How many activities one index page lists (3 columns × 14 rows).
    static let indexEntriesPerPage = 42

    /// The slice of activities one index page lists.
    func indexEntries(from offset: Int) -> ArraySlice<Run> {
        let end = min(offset + Self.indexEntriesPerPage, runs.count)
        guard offset < end else { return [] }
        return runs[offset..<end]
    }

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

    /// Builds the plan — the book's arc:
    /// cover → title → stats → the marks → chapters (races as set pieces) → review →
    /// the complete index → closing → back cover. The closing stays the last words, after the
    /// emotional summary and the record, which is where a final statement belongs.
    static func make(subject: BookSubject, lens: BookLens = .everything,
                     runs: [Run], curation: BookCuration = BookCuration()) -> BookPlan {
        let calendar = Calendar.current
        let selected = runs.filter { subject.matches($0) && lens.matches($0) }
            .sorted { $0.startDate < $1.startDate }
        let story = StoryEngine.story(selected: selected, history: runs)

        let months = Set(selected.map { ChapterSpan.month.start(of: $0.startDate, calendar) })
        let span: ChapterSpan = months.count <= chapterBudget ? .month : .year

        var pages: [BookPageSpec] = [.cover, .title, .stats]

        // The marks page earns its place; two cards on a spread designed for six reads thin.
        if story.marks.count >= 3 { pages.append(.marks) }

        // THE MAP follows the marks — where the year went, right after what stood out. Only when
        // the history actually touched a mappable US state; an international or treadmill year
        // simply doesn't get the page rather than getting an empty one.
        let boundaryNames = Set(USStateBoundaries.shared.boundaries.map(\.name))
        let touchedStates = selected.compactMap { PlaceNames.canonicalState($0.state) }
        if touchedStates.contains(where: boundaryNames.contains) { pages.append(.map) }

        let byChapter = Dictionary(grouping: selected) { span.start(of: $0.startDate, calendar) }
        var racesUsed = 0
        for start in byChapter.keys.sorted() {
            pages.append(.chapter(start: start))
            let chapterRuns = byChapter[start] ?? []
            // A chapter whose activities carry photographs becomes a two-page spread: the
            // routes and numbers on one page, the pictures facing them on the next. A photo
            // the reader excluded doesn't hold a page open.
            if chapterRuns.contains(where: { run in
                run.photoReferences.contains(where: curation.includes)
            }) {
                pages.append(.chapterPhotos(start: start))
            }
            let chapterRaces = chapterRuns.filter(\.isRace)
            for race in chapterRaces where racesUsed < raceBudget {
                if let index = selected.firstIndex(where: { $0.id == race.id }) {
                    pages.append(.race(runIndex: index))
                    racesUsed += 1
                }
            }
        }

        // The span in pictures — one editorial gallery when there's enough material for one.
        let includedCount = selected.reduce(0) {
            $0 + $1.photoReferences.filter(curation.includes).count
        } + curation.extraPhotoIDs.count
        if includedCount >= 3 {
            pages.append(.gallery)
        }

        // The ledger of derived insight, then the emotional summary it sets up.
        pages.append(.numbers)
        pages.append(.review)

        // The portfolio — the book closes by placing its span inside a life. Every year on
        // record, the lifetime of start lines, and everywhere ever. Each earns its page:
        // one year of history has no ledger to print, one race no résumé, one city no atlas.
        let historyYears = Set(runs.map { calendar.component(.year, from: $0.startDate) })
        if historyYears.count >= 2 { pages.append(.years) }
        if runs.filter(\.isRace).count >= 2 { pages.append(.raceHistory) }
        let historyCities = Set(runs.compactMap { run -> String? in
            guard let city = run.city, !city.isEmpty else { return nil }
            return "\(city)|\(PlaceNames.canonicalState(run.state) ?? "")"
        })
        if historyCities.count >= 2 { pages.append(.atlas) }
        // The pins as a ledger — worth a page once there's an actual list to set.
        if historyCities.count >= 4 { pages.append(.cities) }

        // The complete record: every activity, honestly, however many pages that takes. This is
        // what frees the month pages from having to show everything.
        var offset = 0
        while offset < selected.count {
            pages.append(.index(offset: offset))
            offset += indexEntriesPerPage
        }

        pages.append(.closing)

        // The reader's hidden pages come out before the padding math, so the book stays an
        // even, minimum-length object whatever was removed.
        pages.removeAll { spec in
            hideKey(for: spec, runs: selected).map(curation.hiddenPages.contains) ?? false
        }

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

        return BookPlan(subject: subject, lens: lens, runs: selected, history: runs,
                        curation: curation, pages: pages, chapterSpan: span, story: story)
    }

    /// A stable identity for pages the reader may hide — stable across replans, lens
    /// switches and photo changes, so a hidden month stays hidden. Nil marks a structural
    /// page (cover, title, the index, the closing, the blanks) that cannot be hidden:
    /// a book without its own cover or its honest record isn't a smaller book, it's a
    /// broken one.
    static func hideKey(for spec: BookPageSpec, runs: [Run]) -> String? {
        switch spec {
        case .stats:                     return "stats"
        case .marks:                     return "marks"
        case .map:                       return "map"
        case .chapter(let start):        return "chapter:\(Int(start.timeIntervalSince1970))"
        case .chapterPhotos(let start):  return "chapterPhotos:\(Int(start.timeIntervalSince1970))"
        case .race(let index):
            guard runs.indices.contains(index) else { return nil }
            return "race:\(runs[index].id.uuidString)"
        case .gallery:                   return "gallery"
        case .numbers:                   return "numbers"
        case .review:                    return "review"
        case .years:                     return "years"
        case .raceHistory:               return "raceHistory"
        case .atlas:                     return "atlas"
        case .cities:                    return "cities"
        case .cover, .title, .index, .closing, .blank, .backCover:
            return nil
        }
    }

    /// The hide-key for one of this plan's own pages.
    func hideKey(at index: Int) -> String? {
        guard pages.indices.contains(index) else { return nil }
        return Self.hideKey(for: pages[index], runs: runs)
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
