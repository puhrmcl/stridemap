import SwiftUI

/// One Year Book page, composed at `BookCatalog.pageSize` (A4 landscape) and rendered by
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

    var body: some View {
        Group {
            switch spec {
            case .cover(let year):        coverPage(year)
            case .title(let year):        titlePage(year)
            case .yearStats(let year):    yearStatsPage(year)
            case .month(let monthStart):  monthPage(monthStart)
            case .race(let index):        racePage(index)
            case .closing(let year):      closingPage(year)
            case .blank:                  ground
            case .backCover(let year):    backCoverPage(year)
            }
        }
        .frame(width: BookCatalog.pageSize.width, height: BookCatalog.pageSize.height)
        .background(ground)
        .environment(\.colorScheme, .light)
    }

    // MARK: Cover

    private func coverPage(_ year: Int) -> some View {
        ZStack {
            ground
            // The year's longest mapped route as the cover art — the person's own line.
            if let hero = plan.runs.filter({ $0.coordinates.count > 1 }).max(by: { $0.distance < $1.distance }) {
                RouteShape(coordinates: hero.coordinates)
                    .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .padding(180)
            }
            VStack {
                Text("A YEAR IN MOTION")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(10)
                    .foregroundStyle(subtle)
                    .padding(.top, margin + 8)
                Spacer()
                VStack(spacing: 6) {
                    Text(String(year))
                        .font(.system(size: 120, weight: .regular, design: .serif))
                        .tracking(6)
                        .foregroundStyle(ink)
                    Text(totalDistanceLine.uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(subtle)
                }
                .padding(.bottom, margin + 8)
            }
        }
    }

    // MARK: Title

    private func titlePage(_ year: Int) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Text("THE YEAR BOOK")
                .font(.system(size: 17, weight: .semibold)).tracking(8)
                .foregroundStyle(subtle)
            Text(String(year))
                .font(.system(size: 92, weight: .regular, design: .serif)).tracking(4)
                .foregroundStyle(ink)
            if let first = plan.runs.first, let last = plan.runs.last {
                Text("\(Format.date(first.startDate))  —  \(Format.date(last.startDate))".uppercased())
                    .font(.system(size: 15, weight: .semibold)).tracking(4)
                    .foregroundStyle(subtle)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(margin)
    }

    // MARK: Year statistics — the complication wall

    private func yearStatsPage(_ year: Int) -> some View {
        let stats = RunStatistics(plan.runs)
        let states = Set(plan.runs.compactMap { PlaceNames.canonicalState($0.state) }.filter { !$0.isEmpty })
        let cities = Set(plan.runs.compactMap { run -> String? in
            guard let city = run.city, !city.isEmpty else { return nil }
            return "\(city)|\(PlaceNames.canonicalState(run.state) ?? "")"
        })
        let races = plan.runs.filter(\.isRace).count

        return VStack(spacing: 40) {
            pageHeader("THE YEAR", subtitle: String(year))
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
                bigStat("\(cities.count) · \(states.count)", "CITIES · STATES")
            }
            Spacer(minLength: 0)
        }
        .padding(margin)
    }

    // MARK: Month page — the month's line-work, every route as a small etching

    private func monthPage(_ monthStart: Date) -> some View {
        let runs = plan.monthRuns(monthStart)
        let stats = RunStatistics(runs)
        let mapped = runs.filter { $0.coordinates.count > 1 }
        let cells = Array(mapped.prefix(8))

        return VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthName(monthStart))
                    .font(.system(size: 54, weight: .regular, design: .serif)).tracking(2)
                    .foregroundStyle(ink)
                Spacer()
                Text("\(stats.totalRuns) \(stats.totalRuns == 1 ? "ACTIVITY" : "ACTIVITIES")  ·  \(Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))) \(UnitSystem.current.label.uppercased())")
                    .font(.system(size: 16, weight: .semibold)).tracking(3)
                    .foregroundStyle(subtle)
            }
            Rectangle().fill(subtle.opacity(0.35)).frame(height: 1.5)

            if cells.isEmpty {
                Spacer()
                Text("INDOOR MILES — NO LINES TO DRAW, STILL COUNTED ABOVE")
                    .font(.system(size: 14, weight: .semibold)).tracking(3)
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
                    .font(.system(size: 11.5, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(StatMetric.distance.value(for: run) ?? "")  ·  \(shortDate(run.startDate))".uppercased())
                    .font(.system(size: 10.5, weight: .medium)).tracking(1.2)
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
                        .font(.system(size: 14, weight: .semibold)).tracking(6)
                        .foregroundStyle(accent)
                    Text(run.name.uppercased())
                        .font(.system(size: 40, weight: .regular, design: .serif)).tracking(2)
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(raceMetaLine(run).uppercased())
                        .font(.system(size: 14, weight: .semibold)).tracking(3)
                        .foregroundStyle(subtle)

                    if let time = StatMetric.time.value(for: run) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(time)
                                .font(.system(size: 66, weight: .bold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("TIME")
                                .font(.system(size: 13, weight: .semibold)).tracking(5)
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
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(metric.label)
                    .font(.system(size: 10.5, weight: .semibold)).tracking(2)
                    .foregroundStyle(subtle)
            }
        }
    }

    // MARK: Closing + back cover

    private func closingPage(_ year: Int) -> some View {
        let stats = RunStatistics(plan.runs)
        return VStack(spacing: 20) {
            Spacer()
            Text("EVERY LINE ABOVE WAS RUN, NOT DRAWN.")
                .font(.system(size: 16, weight: .semibold)).tracking(4)
                .foregroundStyle(subtle)
                .multilineTextAlignment(.center)
            Text("\(String(year)) · \(Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))) \(UnitSystem.current.label.uppercased())")
                .font(.system(size: 26, weight: .regular, design: .serif)).tracking(3)
                .foregroundStyle(ink)
            Spacer()
            Text("MADE WITH ETCH")
                .font(.system(size: 11, weight: .semibold)).tracking(4)
                .foregroundStyle(subtle.opacity(0.7))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(margin)
    }

    private func backCoverPage(_ year: Int) -> some View {
        ZStack {
            ground
            Text(String(year))
                .font(.system(size: 20, weight: .regular, design: .serif)).tracking(8)
                .foregroundStyle(subtle)
        }
    }

    // MARK: Shared pieces

    private func pageHeader(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold)).tracking(7)
                .foregroundStyle(subtle)
            Text(subtitle)
                .font(.system(size: 56, weight: .regular, design: .serif)).tracking(3)
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity)
    }

    private func bigStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 13, weight: .semibold)).tracking(3)
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

    private func monthName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
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
