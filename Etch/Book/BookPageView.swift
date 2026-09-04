import SwiftUI

/// One book page, composed at `BookCatalog.pageSize` (A4 landscape) and rendered by
/// `BookRenderer`. The book speaks the poster language — bone ground, ink serif mastheads, wide
/// tracking, the route as vector art — and stays print-clean: no Apple map tiles (books are
/// printed merchandise), only self-rendered linework.
struct BookPageView: View {
    let plan: BookPlan
    let spec: BookPageSpec
    /// A race page's cover photo, loaded by the renderer; nil composes the page photo-free.
    var photo: UIImage? = nil
    /// The photographs a picture page shows (chapter spreads, the gallery), loaded by the
    /// renderer with their captions already phrased.
    var photos: [BookPagePhoto] = []

    // Internal, not private: the page families live across files now (BookStoryPages holds the
    // marks/review/index/quiet pages) and all of them speak this one vocabulary.
    let ground = Theme.Palette.bone
    let ink = Theme.Palette.ink
    var subtle: Color { ink.opacity(0.55) }
    let accent = Theme.Palette.blue

    /// Design margin: the print guide's safety margin plus breathing room.
    let margin: CGFloat = 76

    /// What this book is about — the year, the state, the city, the shelf of races.
    private var subject: BookSubject { plan.subject }

    var body: some View {
        Group {
            switch spec {
            case .cover:                    coverPage
            case .title:                    titlePage
            case .stats:                    statsPage
            case .marks:                    marksPage
            case .map:                      mapPage
            case .chapter(let start):       chapterPage(start)
            case .chapterPhotos(let start): chapterPhotosPage(start, photos: photos)
            case .race(let index):          racePage(index)
            case .gallery:                  galleryPage
            case .numbers:                  numbersPage
            case .review:                   reviewPage
            case .years:                    yearsPage
            case .raceHistory:              raceHistoryPage
            case .atlas:                    atlasPage
            case .cities:                   citiesPage
            case .index(let offset):        indexPage(offset: offset)
            case .closing:                  closingPage
            case .blank:                    ground
            case .backCover:                backCoverPage
            }
        }
        .frame(width: BookCatalog.pageSize.width, height: BookCatalog.pageSize.height)
        .background(ground)
        .environment(\.colorScheme, .light)
    }

    // MARK: Cover — the statement piece

    /// Bone type on the cover's own ink. The bone-paper cover read as an interior page promoted
    /// to the front; a coffee-table object needs a cover that is unmistakably a *cover*. So:
    /// the deep ink ground, the person's own line drawn in bone light across its middle, the
    /// year set enormous in the serif, and one measured line of what the year held. The route
    /// still keeps its own band — stacked, never layered over the type — the same rule the
    /// poster fit engine enforces.
    /// Three treatments, one architecture. The eyebrow, the art band, and the type block keep
    /// their stations across all of them — what changes is what fills the band: the year's
    /// longest line (route), a photograph under an ink scrim (photo), or every route of the
    /// span as a wall of small bone lines (grid). Art and type still never overlap.
    @ViewBuilder private var coverPage: some View {
        switch plan.curation.coverStyle {
        case .photo where photo != nil: photoCoverPage
        case .grid:                     coverScaffold { coverGridBand }
        default:                        coverScaffold { coverRouteBand }
        }
    }

    /// The shared cover skeleton: accent rule + eyebrow, the art band, the title block, ETCH.
    private func coverScaffold<Band: View>(@ViewBuilder band: () -> Band) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Rectangle().fill(accent.opacity(0.85)).frame(width: 54, height: 2)
                Text(plan.coverEyebrow)
                    .font(.etch(size: 21, weight: .semibold))
                    .tracking(11)
                    .foregroundStyle(accent)
            }
            .padding(.top, margin + 12)

            band()
                .frame(maxHeight: .infinity)

            coverTitleBlock

            Text("ETCH")
                .font(.etch(size: 12, weight: .semibold))
                .tracking(9)
                .foregroundStyle(accent.opacity(0.9))
                .padding(.top, 34)
                .padding(.bottom, margin - 10)
        }
        .frame(maxWidth: .infinity)
        .background(ink)
    }

    private var coverTitleBlock: some View {
        VStack(spacing: 14) {
            // A year is four digits and always fits; a place name is not. The size is chosen
            // by length and the scale factor catches anything longer still.
            Text(subject.title.uppercased())
                .font(.etchSerif(size: subject.coverTitleSize * 1.12, weight: .regular))
                .tracking(8)
                .foregroundStyle(ground)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Rectangle().fill(ground.opacity(0.35)).frame(width: 54, height: 1.5)
            Text(totalDistanceLine.uppercased())
                .font(.etch(size: 16, weight: .semibold))
                .tracking(7)
                .foregroundStyle(ground.opacity(0.65))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The year's longest mapped route, drawn in bone — a single line of light on the ink.
    /// Filtered by `hasRoute` (a string check), not by decoding every polyline in the span —
    /// a state collection can hold a thousand runs, and only the hero's line gets decoded.
    private var coverRouteBand: some View {
        Group {
            if let hero = plan.runs.filter(\.hasRoute)
                .max(by: { $0.distance < $1.distance }) {
                RouteShape(coordinates: hero.coordinates)
                    .stroke(ground.opacity(0.92),
                            style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, 170)
        .padding(.vertical, 30)
    }

    /// Every mapped route of the span, small, in bone — the anthology as a cover. Capped at
    /// what stays legible; the longest lines get the wall when there are more.
    ///
    /// Not a LazyVGrid: grid cells demand their aspect-ratio height, and forty-eight of them
    /// asked for more page than exists — the whole cover overflowed and the trim-safety
    /// paddings (and the ETCH foot) were what got clipped. These rows are flexible instead:
    /// they share whatever height the band actually has, and `RouteShape` aspect-fits each
    /// line inside its cell, so nothing can push the type toward the edges.
    private var coverGridBand: some View {
        let mapped = plan.runs.filter(\.hasRoute)
            .sorted { $0.distance > $1.distance }
        let cells = Array(mapped.prefix(48))
        let columns = cells.count <= 12 ? 4 : cells.count <= 24 ? 6 : 8
        let rows = stride(from: 0, to: cells.count, by: columns).map {
            Array(cells[$0..<min($0 + columns, cells.count)])
        }
        return VStack(spacing: 22) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 24) {
                    ForEach(row, id: \.id) { run in
                        RouteShape(coordinates: run.coordinates)
                            .stroke(ground.opacity(0.82),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                       lineJoin: .round))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 120)
        .padding(.vertical, 30)
    }

    /// The photograph cover: full-bleed image, an ink scrim rising from the foot so the type
    /// block keeps its contrast, the same eyebrow and title stations as every other cover.
    private var photoCoverPage: some View {
        ZStack {
            ink
            if let photo {
                Color.clear.overlay(
                    Image(uiImage: photo).resizable().scaledToFill()
                )
                .clipped()
                // Ink at both ends: the eyebrow at the head and the title block at the foot
                // both sit on darkness, whatever the photograph holds.
                LinearGradient(
                    stops: [.init(color: ink.opacity(0.75), location: 0),
                            .init(color: ink.opacity(0.05), location: 0.3),
                            .init(color: ink.opacity(0.1), location: 0.55),
                            .init(color: ink.opacity(0.9), location: 1)],
                    startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: 0) {
                VStack(spacing: 16) {
                    Rectangle().fill(accent.opacity(0.9)).frame(width: 54, height: 2)
                    Text(plan.coverEyebrow)
                        .font(.etch(size: 21, weight: .semibold))
                        .tracking(11)
                        .foregroundStyle(ground.opacity(0.95))
                }
                .padding(.top, margin + 12)
                Spacer()
                coverTitleBlock
                Text("ETCH")
                    .font(.etch(size: 12, weight: .semibold))
                    .tracking(9)
                    .foregroundStyle(accent.opacity(0.9))
                    .padding(.top, 34)
                    .padding(.bottom, margin - 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Title

    private var titlePage: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(subject.masthead)
                .font(.etch(size: 17, weight: .semibold)).tracking(8)
                .foregroundStyle(subtle)
            Text(subject.title.uppercased())
                .font(.etchSerif(size: subject.coverTitleSize * 0.77, weight: .regular)).tracking(4)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            if let first = plan.runs.first, let last = plan.runs.last {
                Text("\(Format.date(first.startDate))  —  \(Format.date(last.startDate))".uppercased())
                    .font(.etch(size: 15, weight: .semibold)).tracking(4)
                    .foregroundStyle(subtle)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(margin)
    }

    // MARK: Statistics — the complication wall

    private var statsPage: some View {
        let stats = RunStatistics(plan.runs)
        let states = Set(plan.runs.compactMap { PlaceNames.canonicalState($0.state) }.filter { !$0.isEmpty })
        let cities = Set(plan.runs.compactMap { run -> String? in
            guard let city = run.city, !city.isEmpty else { return nil }
            return "\(city)|\(PlaceNames.canonicalState(run.state) ?? "")"
        })
        let races = plan.runs.filter(\.isRace).count

        // A book *about* a place has already answered "where"; counting one city and one state on
        // its own statistics page is a complication reporting a constant. It answers "when"
        // instead — how many years of someone's history happened there.
        let years = Set(plan.runs.map { Calendar.current.component(.year, from: $0.startDate) })
        let placeStat: (String, String) = subject.isPlace
            ? (years.count.formatted(), years.count == 1 ? "YEAR" : "YEARS")
            : ("\(cities.count) · \(states.count)", "CITIES · STATES")

        return VStack(spacing: 40) {
            pageHeader(subject.kind == .year ? "THE YEAR" : "THE COLLECTION",
                       subtitle: subject.title.uppercased())
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                bigStat(stats.totalRuns.formatted(), plan.lens.countLabel ?? "ACTIVITIES")
                statDivider
                bigStat(Format.distanceValue(stats.totalDistanceMeters)
                    .formatted(.number.precision(.fractionLength(0))), UnitSystem.current.label.uppercased())
                statDivider
                bigStat(durationText(stats.totalMovingTime), "MOVING TIME")
            }
            HStack(spacing: 0) {
                bigStat(Format.elevation(stats.totalElevationMeters), "CLIMBED")
                statDivider
                bigStat(races.formatted(), races == 1 ? "RACE" : "RACES")
                statDivider
                bigStat(placeStat.0, placeStat.1)
            }
            Spacer(minLength: 0)
        }
        .padding(margin)
    }

    // MARK: Chapter page — profiled by content, led by a marquee

    /// The month's shared masthead: name on the left, its totals on the right, a hairline under.
    func chapterHeader(_ start: Date, stats: RunStatistics) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .firstTextBaseline) {
                Text(chapterName(start))
                    .font(.etchSerif(size: 54, weight: .regular)).tracking(2)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("\(stats.totalRuns) \(stats.totalRuns == 1 ? "ACTIVITY" : "ACTIVITIES")  ·  \(Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))) \(UnitSystem.current.label.uppercased())")
                    .font(.etch(size: 16, weight: .semibold)).tracking(3)
                    .foregroundStyle(subtle)
            }
            Rectangle().fill(subtle.opacity(0.35)).frame(height: 1.5)
        }
    }

    /// Dispatches by what the month actually held: a handful of activities takes the quiet
    /// treatment; a full month takes the grid, led by its marquee. The content chooses.
    @ViewBuilder private func chapterPage(_ start: Date) -> some View {
        let runs = plan.chapterRuns(start)
        switch BookStory.chapterProfile(for: runs) {
        case .quiet:    quietChapterPage(start, runs: runs)
        case .standard: standardChapterPage(start, runs: runs)
        }
    }

    /// The grid month. Not the old uniform eight: the month's marquee activity — its race, its
    /// mark-holder, or simply its longest — takes a double-width cell, because a marathon and a
    /// recovery jog were never equals. And nothing vanishes any more: what the page can't hold
    /// is counted and pointed at the index.
    private func standardChapterPage(_ start: Date, runs: [Run]) -> some View {
        let stats = RunStatistics(runs)
        let mapped = runs.filter { $0.coordinates.count > 1 }
        let marquee = plan.story.marquee(in: mapped)
        let supporting = mapped.filter { $0.id != marquee?.id }
        let cells = Array(supporting.prefix(6))
        let unshown = runs.count - cells.count - (marquee == nil ? 0 : 1)

        return VStack(alignment: .leading, spacing: 30) {
            chapterHeader(start, stats: stats)

            if marquee == nil && cells.isEmpty {
                Spacer()
                Text("INDOOR MILES — NO LINES TO DRAW, STILL COUNTED ABOVE")
                    .font(.etch(size: 14, weight: .semibold)).tracking(3)
                    .foregroundStyle(subtle)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 26) {
                    if let marquee {
                        marqueeCell(marquee)
                            .frame(maxWidth: .infinity)
                    }
                    let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 26),
                                             count: marquee == nil ? 4 : 3)
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(cells, id: \.id) { run in
                            routeCell(run)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
                if unshown > 0 {
                    Text("+ \(unshown) MORE — IN THE RECORD, AT THE BACK")
                        .font(.etch(size: 11.5, weight: .semibold)).tracking(2.5)
                        .foregroundStyle(subtle)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(margin)
    }

    /// The month's lead activity at editorial size: the route in accent, name, and its own line
    /// of numbers — a small poster inside the page.
    private func marqueeCell(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RouteShape(coordinates: run.coordinates)
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 3) {
                if run.isRace {
                    Text("RACE DAY")
                        .font(.etch(size: 10.5, weight: .semibold)).tracking(3)
                        .foregroundStyle(accent)
                }
                Text(run.name.uppercased())
                    .font(.etch(size: 15, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(marqueeStatLine(run).uppercased())
                    .font(.etch(size: 11.5, weight: .medium)).tracking(1.2)
                    .foregroundStyle(subtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func marqueeStatLine(_ run: Run) -> String {
        [StatMetric.distance.value(for: run),
         StatMetric.time.value(for: run),
         shortDate(run.startDate)]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    private func routeCell(_ run: Run) -> some View {
        VStack(spacing: 10) {
            RouteShape(coordinates: run.coordinates)
                .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(height: 150)
                .padding(.horizontal, 6)
            VStack(spacing: 2) {
                Text(run.name.uppercased())
                    .font(.etch(size: 11.5, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(StatMetric.distance.value(for: run) ?? "")  ·  \(shortDate(run.startDate))".uppercased())
                    .font(.etch(size: 10.5, weight: .medium)).tracking(1.2)
                    .foregroundStyle(subtle)
            }
        }
    }

    // MARK: Race page — the set piece

    @ViewBuilder private func racePage(_ index: Int) -> some View {
        if let run = plan.run(at: index) {
            HStack(spacing: 44) {
                // Left: the route (or photo when the run carries one) as the art panel.
                ZStack {
                    ink.opacity(0.035)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else if run.coordinates.count > 1 {
                        RouteShape(coordinates: run.coordinates)
                            .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .padding(46)
                    }
                }
                .frame(width: 470)
                .clipped()

                // Right: the record.
                VStack(alignment: .leading, spacing: 20) {
                    Text("RACE DAY")
                        .font(.etch(size: 14, weight: .semibold)).tracking(6)
                        .foregroundStyle(accent)
                    Text(run.name.uppercased())
                        .font(.etchSerif(size: 40, weight: .regular)).tracking(2)
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(raceMetaLine(run).uppercased())
                        .font(.etch(size: 14, weight: .semibold)).tracking(3)
                        .foregroundStyle(subtle)

                    if let time = StatMetric.time.value(for: run) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(time)
                                .font(.etch(size: 66, weight: .bold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("TIME")
                                .font(.etch(size: 13, weight: .semibold)).tracking(5)
                                .foregroundStyle(accent)
                        }
                        .padding(.top, 6)
                    }

                    HStack(spacing: 28) {
                        raceStat(.distance, run)
                        raceStat(.pace, run)
                        raceStat(.elevationGain, run)
                        if !run.finishPlace.isEmpty { raceStat(.finish, run) }
                    }
                    .padding(.top, 2)

                    if run.elevationSeries.count > 1 {
                        ZStack {
                            ElevationProfileShape(samples: run.elevationSeries)
                                .fill(LinearGradient(colors: [subtle.opacity(0.32), subtle.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom))
                            ElevationLineShape(samples: run.elevationSeries)
                                .stroke(subtle.opacity(0.85),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                        .frame(height: 90)
                        .padding(.top, 8)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(margin)
        } else {
            ground
        }
    }

    @ViewBuilder private func raceStat(_ metric: StatMetric, _ run: Run) -> some View {
        if let value = metric.value(for: run) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.etch(size: 22, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(metric.label)
                    .font(.etch(size: 10.5, weight: .semibold)).tracking(2)
                    .foregroundStyle(subtle)
            }
        }
    }

    // MARK: Closing + back cover

    private var closingPage: some View {
        let stats = RunStatistics(plan.runs)
        return VStack(spacing: 20) {
            Spacer()
            Text("EVERY LINE ABOVE WAS RUN, NOT DRAWN.")
                .font(.etch(size: 16, weight: .semibold)).tracking(4)
                .foregroundStyle(subtle)
                .multilineTextAlignment(.center)
            Text("\(subject.title.uppercased()) · \(Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))) \(UnitSystem.current.label.uppercased())")
                .font(.etchSerif(size: 26, weight: .regular)).tracking(3)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Text("MADE WITH ETCH")
                .font(.etch(size: 11, weight: .semibold)).tracking(4)
                .foregroundStyle(subtle.opacity(0.7))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(margin)
    }

    /// The back matches the front's ink, so the closed object reads as one piece on the table.
    private var backCoverPage: some View {
        ZStack {
            ink
            VStack(spacing: 18) {
                Text(subject.title.uppercased())
                    .font(.etchSerif(size: 22, weight: .regular)).tracking(9)
                    .foregroundStyle(ground.opacity(0.8))
                Text("MADE WITH ETCH")
                    .font(.etch(size: 10.5, weight: .semibold)).tracking(5)
                    .foregroundStyle(accent.opacity(0.75))
            }
        }
    }

    // MARK: Shared pieces

    func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.etch(size: 15, weight: .semibold)).tracking(7)
                .foregroundStyle(subtle)
            Text(subtitle)
                .font(.etchSerif(size: 56, weight: .regular)).tracking(3)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.etch(size: 52, weight: .bold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.etch(size: 13, weight: .semibold)).tracking(3)
                .foregroundStyle(subtle)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(subtle.opacity(0.3)).frame(width: 1, height: 64)
    }

    private var totalDistanceLine: String {
        let stats = RunStatistics(plan.runs)
        let miles = Format.distanceValue(stats.totalDistanceMeters)
            .formatted(.number.precision(.fractionLength(0)))
        let noun = plan.lens.countLabel?.lowercased() ?? "activities"
        return "\(stats.totalRuns) \(noun) · \(miles) \(UnitSystem.current.label)"
    }

    private func raceMetaLine(_ run: Run) -> String {
        var parts: [String] = []
        let place = [run.city, PlaceNames.canonicalState(run.state)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        parts.append(Format.date(run.startDate))
        return parts.joined(separator: "  ·  ")
    }

    /// A chapter's heading. Inside one year "MARCH" is unambiguous; a collection spanning several
    /// needs the year, and a collection long enough to be chaptered by year is only the year.
    /// Internal: the chapter's pictures page (BookPhotoPages) names the month the same way.
    func chapterName(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch plan.chapterSpan {
        case .year:  formatter.dateFormat = "yyyy"
        case .month: formatter.dateFormat = plan.chapterNamesYear ? "MMMM yyyy" : "MMMM"
        }
        return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
