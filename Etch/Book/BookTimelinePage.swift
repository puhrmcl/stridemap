import SwiftUI

/// THE SPAN — the whole book on one axis.
///
/// Every activity is a stroke rising from a horizontal rule, its height the distance covered;
/// races stand in accent. Photographs are pinned above, evenly spaced so they never collide, each
/// dropping a leader line to the true date it belongs to. The marks the story engine found are
/// called out beneath.
///
/// This is the page the book never had: a reader could previously see each month in isolation and
/// the totals at the back, but nothing ever showed the *shape* of the span — where the weight of
/// the year actually sat.
extension BookPageView {

    var timelinePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                kicker("The span")
                HStack(alignment: .firstTextBaseline) {
                    headline(plan.subject.kind == .year ? "A YEAR IN MOTION" : "THE WHOLE SPAN",
                             size: 40)
                        .tracking(3)
                    Spacer(minLength: 16)
                    Text(timelineRangeLine.uppercased())
                        .font(.etch(size: 12, weight: .semibold)).tracking(3)
                        .foregroundStyle(subtle)
                }
                Rectangle().fill(subtle.opacity(0.35)).frame(height: 1.5)
            }

            GeometryReader { geometry in
                timelineChart(in: geometry.size)
            }
            .padding(.top, 26)

            if !plan.story.marks.isEmpty {
                timelineMarks
                    .padding(.top, 18)
            }

            folio(pageNumber)
                .padding(.top, 16)
        }
        .padding(margin)
    }

    private var timelineRangeLine: String {
        guard let first = plan.runs.first?.startDate,
              let last = plan.runs.last?.startDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = plan.chapterSpan == .year ? "MMM yyyy" : "d MMM"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    // MARK: The chart

    private func timelineChart(in size: CGSize) -> some View {
        let runs = plan.runs
        let chipHeight: CGFloat = 88
        let leaderZone: CGFloat = 34
        let axisY = size.height - 26
        let strokeTop = chipHeight + leaderZone
        let maxStroke = max(24, axisY - strokeTop)

        let start = runs.first?.startDate.timeIntervalSince1970 ?? 0
        let end = runs.last?.startDate.timeIntervalSince1970 ?? 1
        let span = max(1, end - start)
        let maxDistance = max(1, runs.map(\.distance).max() ?? 1)

        func x(for date: Date) -> CGFloat {
            let fraction = (date.timeIntervalSince1970 - start) / span
            return CGFloat(min(1, max(0, fraction))) * size.width
        }

        let chips = Array(photos.prefix(5))

        return ZStack(alignment: .topLeading) {

            // Leaders first, so the activity strokes draw over them rather than under: an
            // annotation that crosses in front of the data reads as part of the chart.
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, _ in
                let slot = chips.count == 1
                    ? size.width / 2
                    : size.width * (CGFloat(index) + 0.5) / CGFloat(chips.count)
                let target = chipDates.indices.contains(index) ? x(for: chipDates[index]) : slot
                // Staggered elbows. At one shared height the five horizontal runs joined up into
                // a continuous rule across the page that read as an axis the chart does not have.
                let fraction = 0.26 + 0.13 * Double(index % 4)
                TimelineLeader(from: CGPoint(x: slot, y: chipHeight),
                               to: CGPoint(x: target, y: axisY),
                               elbowFraction: fraction)
                    .stroke(ink.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }

            // Every activity, as a stroke scaled by distance.
            ForEach(runs, id: \.id) { run in
                let height = max(3, CGFloat(run.distance / maxDistance) * maxStroke)
                Rectangle()
                    .fill(run.isRace ? accent : ink.opacity(0.45))
                    .frame(width: run.isRace ? 2.6 : 1.7, height: height)
                    .position(x: x(for: run.startDate), y: axisY - height / 2)
            }

            // The axis itself.
            Rectangle()
                .fill(ink.opacity(0.5))
                .frame(width: size.width, height: 1.2)
                .position(x: size.width / 2, y: axisY)

            // Month ticks and labels.
            ForEach(timelineTicks, id: \.self) { tick in
                VStack(spacing: 5) {
                    Rectangle().fill(ink.opacity(0.35)).frame(width: 1, height: 6)
                    Text(tickLabel(tick).uppercased())
                        .font(.etch(size: 8.5, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(subtle.opacity(0.85))
                        .fixedSize()
                }
                .position(x: x(for: tick), y: axisY + 16)
            }

            // Photographs, evenly spaced so they cannot collide.
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                let slot = chips.count == 1
                    ? size.width / 2
                    : size.width * (CGFloat(index) + 0.5) / CGFloat(chips.count)
                bleedPhoto(chip.image)
                    .frame(width: chipHeight * 1.28, height: chipHeight)
                    .position(x: slot, y: chipHeight / 2)
            }
        }
    }

    /// The dates the pinned photographs actually belong to, in the same order as `photos`.
    private var chipDates: [Date] {
        let carriers = plan.runs.filter { run in
            run.photoReferences.contains(where: plan.curation.includes)
        }
        guard !carriers.isEmpty else { return [] }
        let wanted = min(5, photos.count)
        guard wanted > 0 else { return [] }
        // The renderer picks evenly across time; mirror that spacing so each chip's leader lands
        // on the activity it came from rather than on an unrelated date.
        let step = Double(carriers.count) / Double(wanted)
        return (0..<wanted).map {
            carriers[min(carriers.count - 1, Int(Double($0) * step))].startDate
        }
    }

    /// Where to tick the axis: each month for a year, each year for a long collection. Capped so
    /// a decade-long collection does not set twelve labels on top of each other.
    private var timelineTicks: [Date] {
        guard let first = plan.runs.first?.startDate,
              let last = plan.runs.last?.startDate else { return [] }
        let calendar = Calendar.current
        let unit: Calendar.Component = plan.chapterSpan == .year ? .year : .month
        let components: Set<Calendar.Component> = unit == .year ? [.year] : [.year, .month]
        var ticks: [Date] = []
        var cursor = calendar.date(from: calendar.dateComponents(components, from: first)) ?? first
        while cursor <= last && ticks.count < 14 {
            if cursor >= first { ticks.append(cursor) }
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }

    private func tickLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = plan.chapterSpan == .year ? "yyyy" : "MMM"
        return formatter.string(from: date)
    }

    // MARK: The marks, called out under the axis

    private var timelineMarks: some View {
        HStack(alignment: .top, spacing: 26) {
            ForEach(Array(plan.story.marks.prefix(4).enumerated()), id: \.element.id) { index, mark in
                if index > 0 {
                    Rectangle().fill(ink.opacity(0.14)).frame(width: 1, height: 42)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(mark.value)
                        .font(.etchSerif(size: 22, weight: .regular))
                        .foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(mark.title)
                        .font(.etch(size: 8.5, weight: .semibold)).tracking(2.2)
                        .foregroundStyle(accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(mark.detail)
                        .font(.etch(size: 9.5, weight: .medium))
                        .foregroundStyle(subtle)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The dashed leader from a pinned photograph down to its date on the axis: straight down, one
/// elbow, then across. A diagonal would read as a data line; an elbow reads as an annotation.
struct TimelineLeader: Shape {
    let from: CGPoint
    let to: CGPoint
    /// How far down the drop the horizontal run sits. Staggered by the caller so several
    /// leaders never merge into one continuous rule across the page.
    var elbowFraction: Double = 0.45

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let elbow = from.y + (to.y - from.y) * elbowFraction
        path.move(to: from)
        path.addLine(to: CGPoint(x: from.x, y: elbow))
        path.addLine(to: CGPoint(x: to.x, y: elbow))
        path.addLine(to: to)
        return path
    }
}
