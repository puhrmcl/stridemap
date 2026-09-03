import SwiftUI

/// The story pages — the marks spread, the review, the activity index, and the quiet chapter.
/// Split from `BookPageView` so each page family has a home; the dispatcher stays in the main
/// file and the visual vocabulary (margins, inks, headers) is shared through the same struct.
extension BookPageView {

    // MARK: The Marks — what stood out

    /// Up to six achievement cards on a 3×2 grid: the big value, its label, the line beneath.
    /// Complication language, editorial weight — the year's superlatives get the page the old
    /// book never gave them.
    var marksPage: some View {
        let marks = plan.story.marks
        let columns = [GridItem](repeating: GridItem(.flexible(), spacing: 34), count: 3)

        return VStack(spacing: 44) {
            pageHeader("WHAT STOOD OUT", subtitle: "THE MARKS")
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 52) {
                ForEach(marks) { mark in
                    VStack(spacing: 8) {
                        Text(mark.value)
                            .font(.etch(size: 44, weight: .bold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(mark.title)
                            .font(.etch(size: 13, weight: .semibold)).tracking(3)
                            .foregroundStyle(accent)
                        Text(mark.detail.uppercased())
                            .font(.etch(size: 11, weight: .medium)).tracking(1.2)
                            .foregroundStyle(subtle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(margin)
    }

    // MARK: The review — "YOUR YEAR, ETCHED."

    var reviewPage: some View {
        let stats = RunStatistics(plan.runs)
        let miles = Format.distanceValue(stats.totalDistanceMeters)
            .formatted(.number.precision(.fractionLength(0)))
        let states = stats.states
        let cities = stats.cities

        return VStack(spacing: 0) {
            Text(plan.subject.kind == .year ? "YOUR YEAR, ETCHED." : "EVERY MILE, ETCHED.")
                .font(.etch(size: 16, weight: .semibold)).tracking(7)
                .foregroundStyle(subtle)
                .padding(.bottom, 26)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(miles)
                    .font(.etchSerif(size: 130, weight: .regular))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(UnitSystem.current.label.uppercased())
                    .font(.etch(size: 22, weight: .semibold)).tracking(6)
                    .foregroundStyle(accent)
            }
            .padding(.bottom, 34)

            Rectangle().fill(subtle.opacity(0.3)).frame(height: 1.5)
                .padding(.bottom, 26)

            // The highlights: the top marks as a two-column ledger.
            let highlights = Array(plan.story.marks.prefix(4))
            if !highlights.isEmpty {
                LazyVGrid(columns: [GridItem](repeating: GridItem(.flexible(), spacing: 40),
                                              count: 2),
                          alignment: .leading, spacing: 16) {
                    ForEach(highlights) { mark in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(mark.title)
                                .font(.etch(size: 12, weight: .semibold)).tracking(2)
                                .foregroundStyle(subtle)
                                .frame(width: 172, alignment: .leading)
                            Text(mark.value)
                                .font(.etch(size: 17, weight: .bold))
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
                .padding(.bottom, 26)
            }

            Spacer(minLength: 0)

            // Where the year happened — one quiet line, not a gazetteer.
            if !cities.isEmpty || !states.isEmpty {
                VStack(spacing: 8) {
                    Text(placesLine(cities: cities.count, states: states.count))
                        .font(.etch(size: 14, weight: .semibold)).tracking(3)
                        .foregroundStyle(subtle)
                    if !plan.story.newStates.isEmpty {
                        Text("FIRST MILES IN \(plan.story.newStates.prefix(4).joined(separator: " · ").uppercased())")
                            .font(.etch(size: 12, weight: .semibold)).tracking(2)
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(margin)
    }

    private func placesLine(cities: Int, states: Int) -> String {
        var parts: [String] = []
        if cities > 0 { parts.append("\(cities) \(cities == 1 ? "CITY" : "CITIES")") }
        if states > 0 { parts.append("\(states) \(states == 1 ? "STATE" : "STATES")") }
        return parts.joined(separator: " ACROSS ")
    }

    // MARK: The index — the complete record

    /// Three columns of compact entries: date, name, distance. Every activity in the book is
    /// here, which is the honesty that lets month pages curate instead of cram. The header only
    /// tops the first page; continuation pages give the full height to the record.
    func indexPage(offset: Int) -> some View {
        let entries = Array(plan.indexEntries(from: offset))
        let perColumn = 14
        let columns = stride(from: 0, to: entries.count, by: perColumn).map {
            Array(entries[$0..<min($0 + perColumn, entries.count)])
        }

        return VStack(alignment: .leading, spacing: 26) {
            if offset == 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("The Record")
                        .font(.etchSerif(size: 44, weight: .regular)).tracking(2)
                        .foregroundStyle(ink)
                    Spacer()
                    Text("EVERY ACTIVITY · \(plan.runs.count)")
                        .font(.etch(size: 13, weight: .semibold)).tracking(3)
                        .foregroundStyle(subtle)
                }
                Rectangle().fill(subtle.opacity(0.35)).frame(height: 1.5)
            }
            HStack(alignment: .top, spacing: 38) {
                ForEach(0..<3, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 13) {
                        if column < columns.count {
                            ForEach(columns[column], id: \.id) { run in
                                indexRow(run)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(margin)
    }

    private func indexRow(_ run: Run) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(indexDate(run.startDate))
                .font(.etch(size: 10.5, weight: .semibold)).tracking(0.8)
                .foregroundStyle(subtle)
                .frame(width: 46, alignment: .leading)
            Text(run.name)
                .font(.etch(size: 11, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(StatMetric.distance.value(for: run) ?? "")
                .font(.etch(size: 10.5, weight: .medium))
                .foregroundStyle(subtle)
                .lineLimit(1)
        }
    }

    private func indexDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }

    // MARK: The quiet chapter

    /// A month of three activities set in the old eight-cell grid was mostly air pretending to
    /// be content. The quiet treatment gives the month's best line the left half of the page,
    /// drawn large, and lists the rest as a ledger — sparse content, treated as a choice.
    func quietChapterPage(_ start: Date, runs: [Run]) -> some View {
        let stats = RunStatistics(runs)
        let marquee = plan.story.marquee(in: runs.filter { $0.coordinates.count > 1 })

        return VStack(alignment: .leading, spacing: 30) {
            chapterHeader(start, stats: stats)

            HStack(alignment: .top, spacing: 54) {
                // The line of the month, drawn with room.
                ZStack {
                    if let marquee {
                        RouteShape(coordinates: marquee.coordinates)
                            .stroke(accent,
                                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round,
                                                       lineJoin: .round))
                            .padding(26)
                    } else {
                        Text("INDOOR MILES — COUNTED, NOT DRAWN")
                            .font(.etch(size: 12, weight: .semibold)).tracking(3)
                            .foregroundStyle(subtle)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // The ledger: everything the month held.
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(runs, id: \.id) { run in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(run.name.uppercased())
                                .font(.etch(size: 13, weight: .semibold)).tracking(1.5)
                                .foregroundStyle(marquee?.id == run.id ? accent : ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(indexDate(run.startDate))  ·  \(StatMetric.distance.value(for: run) ?? "")".uppercased())
                                .font(.etch(size: 11, weight: .medium)).tracking(1.2)
                                .foregroundStyle(subtle)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 330)
            }
        }
        .padding(margin)
    }
}
