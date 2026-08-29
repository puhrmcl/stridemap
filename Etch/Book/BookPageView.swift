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

    private let ground = Theme.Palette.bone
    private let ink = Theme.Palette.ink
    private var subtle: Color { ink.opacity(0.55) }
    private let accent = Theme.Palette.blue

    /// Design margin: the print guide's safety margin plus breathing room.
    private let margin: CGFloat = 76

    /// What this book is about — the year, the state, the city, the shelf of races.
    private var subject: BookSubject { plan.subject }

    var body: some View {
        Group {
            switch spec {
            case .cover:                    coverPage
            case .title:                    titlePage
            case .stats:                    statsPage
            case .chapter(let start):       chapterPage(start)
            case .race(let index):          racePage(index)
            case .closing:                  closingPage
            case .blank:                    ground
            case .backCover:                backCoverPage
            }
        }
        .frame(width: BookCatalog.pageSize.width, height: BookCatalog.pageSize.height)
        .background(ground)
        .environment(\.colorScheme, .light)
    }

    // MARK: Cover

    /// The route sits in its own band between the eyebrow and the year block rather than behind
    /// them: stacked, not layered, so the line can never cross the type — the same rule the
    /// poster fit engine enforces.
    private var coverPage: some View {
        VStack(spacing: 0) {
            Text(subject.eyebrow)
                .font(.etch(size: 22, weight: .semibold))
                .tracking(10)
                .foregroundStyle(subtle)
                .padding(.top, margin + 8)

            // The year's longest mapped route as the cover art — the person's own line.
            Group {
                if let hero = plan.runs.filter({ $0.coordinates.count > 1 })
                    .max(by: { $0.distance < $1.distance }) {
                    RouteShape(coordinates: hero.coordinates)
                        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                } else {
                    Color.clear
                }
            }
            .padding(.horizontal, 150)
            .padding(.vertical, 34)
            .frame(maxHeight: .infinity)

            VStack(spacing: 6) {
                // A year is four digits and always fits; a place name is not. The size is chosen
                // by length and the scale factor catches anything longer still, so "SAN
                // FRANCISCO" sets on one line rather than running off the sheet.
                Text(subject.title.uppercased())
                    .font(.etchSerif(size: subject.coverTitleSize, weight: .regular))
                    .tracking(6)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(totalDistanceLine.uppercased())
                    .font(.etch(size: 18, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(subtle)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, margin + 8)
        }
        .frame(maxWidth: .infinity)
        .background(ground)
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
                bigStat(stats.totalRuns.formatted(), "ACTIVITIES")
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

    // MARK: Chapter page — the chapter's line-work, every route as a small etching

    private func chapterPage(_ start: Date) -> some View {
        let runs = plan.chapterRuns(start)
        let stats = RunStatistics(runs)
        let mapped = runs.filter { $0.coordinates.count > 1 }
        let cells = Array(mapped.prefix(8))

        return VStack(alignment: .leading, spacing: 30) {
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

            if cells.isEmpty {
                Spacer()
                Text("INDOOR MILES — NO LINES TO DRAW, STILL COUNTED ABOVE")
                    .font(.etch(size: 14, weight: .semibold)).tracking(3)
                    .foregroundStyle(subtle)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 26), count: 4)
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(cells, id: \.id) { run in
                        routeCell(run)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(margin)
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

    private var backCoverPage: some View {
        ZStack {
            ground
            Text(subject.title.uppercased())
                .font(.etchSerif(size: 20, weight: .regular)).tracking(8)
                .foregroundStyle(subtle)
        }
    }

    // MARK: Shared pieces

    private func pageHeader(_ title: String, subtitle: String) -> some View {
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
        return "\(stats.totalRuns) activities · \(miles) \(UnitSystem.current.label)"
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
    private func chapterName(_ date: Date) -> String {
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
