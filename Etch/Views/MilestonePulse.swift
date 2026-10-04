import SwiftUI
import Charts

/// THE PULSE — the Milestones page's interactive centrepiece.
///
/// One chart, twelve states: four metrics against three spans, switched live. The year view is
/// the one that earns the section — this year's cumulative curve against last year's on a shared
/// day-of-year axis, so the reader is not looking at a total but at a race they are either winning
/// or losing, and can say which by October rather than only on 31 December.
///
/// Dragging anywhere on the chart scrubs: the readout above becomes that day's running total and
/// the gap to the same day last year. Letting go returns it to the headline figure.
struct MilestonePulse: View {
    let runs: [Run]
    let scope: ActivityScope

    @State private var metric: MilestoneMetric = .distance
    @State private var range: MilestoneRange = .year
    /// The scrubbed day-of-year, while a finger is down.
    @State private var scrubDay: Int?
    /// The scrubbed bucket label, for the month and year views.
    @State private var scrubBucket: String?

    private var series: [MilestoneInsights.Series] {
        MilestoneInsights.race(runs, metric: metric)
    }

    private var buckets: [MilestoneInsights.Bucket] {
        switch range {
        case .year:   return []
        case .months: return MilestoneInsights.months(runs, metric: metric)
        case .all:    return MilestoneInsights.years(runs, metric: metric)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            readout
            chart
                .frame(height: 220)
                .animation(.easeInOut(duration: 0.35), value: metric)
                .animation(.easeInOut(duration: 0.35), value: range)
            rangeControl
        }
        .padding(18)
        .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.accent.opacity(0.14), lineWidth: 1)
        }
    }

    // MARK: Header and metric control

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The pulse")
                .font(.etch(.title2, weight: .bold))
            // A segmented control rather than a menu: the whole point of this section is that
            // switching metric is cheap enough to do idly, and a menu makes it a decision.
            Picker("Metric", selection: $metric) {
                ForEach(MilestoneMetric.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: metric)
        }
    }

    private var rangeControl: some View {
        HStack(spacing: 8) {
            ForEach(MilestoneRange.allCases) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        range = r
                        scrubDay = nil
                        scrubBucket = nil
                    }
                } label: {
                    Text(r.label)
                        .font(.etch(.footnote, weight: .semibold))
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(range == r ? Theme.accent : Color.clear, in: .capsule)
                        .foregroundStyle(range == r ? .white : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: .capsule)
        .sensoryFeedback(.selection, trigger: range)
    }

    // MARK: The readout

    /// The big number. It is the headline total until a finger lands on the chart, and that day's
    /// running total while one is down — so the chart answers "how much, by when" without ever
    /// opening a second screen.
    private var readout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(readoutValue)
                .font(.etch(size: 34, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: readoutValue)
            Text(readoutCaption)
                .font(.etch(.footnote))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readoutValue: String {
        switch range {
        case .year:
            guard let current = series.first else { return metric.format(0) }
            if let day = scrubDay { return metric.format(current.value(onOrBefore: day)) }
            return metric.format(current.total)
        case .months, .all:
            if let label = scrubBucket, let hit = buckets.first(where: { $0.label == label }) {
                return metric.format(hit.value)
            }
            return metric.format(buckets.reduce(0) { $0 + $1.value })
        }
    }

    private var readoutCaption: String {
        switch range {
        case .year:
            if let day = scrubDay {
                return "\(dayLabel(day)) · \(scrubComparison(day))"
            }
            guard let pace = MilestoneInsights.pacing(series) else {
                return "\(scopeNoun) this year so far."
            }
            let ahead = pace.delta >= 0
            let size = metric.format(abs(pace.delta))
            if abs(pace.delta) < 0.0001 { return "Exactly level with last year on this day." }
            return ahead
                ? "\(size) ahead of where you were this day last year."
                : "\(size) behind where you were this day last year."
        case .months:
            if let label = scrubBucket, let hit = buckets.first(where: { $0.label == label }) {
                return "\(label) · \(hit.count) \(hit.count == 1 ? "activity" : "activities")"
            }
            return "Across the last twelve months."
        case .all:
            if let label = scrubBucket, let hit = buckets.first(where: { $0.label == label }) {
                return "\(label) · \(hit.count) \(hit.count == 1 ? "activity" : "activities")"
            }
            return "Everything on record."
        }
    }

    private var scopeNoun: String {
        scope == .all ? "Everything" : scope.label
    }

    private func scrubComparison(_ day: Int) -> String {
        guard series.count == 2 else { return "this year" }
        let delta = series[0].value(onOrBefore: day) - series[1].value(onOrBefore: day)
        if abs(delta) < 0.0001 { return "level with last year" }
        return delta > 0 ? "\(metric.format(delta)) up on last year"
                         : "\(metric.format(abs(delta))) down on last year"
    }

    private func dayLabel(_ day: Int) -> String {
        var components = DateComponents()
        components.year = Calendar.current.component(.year, from: .now)
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return "Day \(day)" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: The chart

    @ViewBuilder private var chart: some View {
        switch range {
        case .year:   raceChart
        case .months, .all: bucketChart
        }
    }

    /// Two cumulative curves on a shared day-of-year axis. Last year is a flat grey line behind;
    /// this year is the accent, filled, in front. The fill is what makes the gap between them
    /// legible at a glance rather than a thing you have to measure with your eye.
    private var raceChart: some View {
        Chart {
            if series.count == 2 {
                ForEach(series[1].points) { point in
                    LineMark(x: .value("Day", point.day),
                             y: .value(metric.label, point.value),
                             series: .value("Year", series[1].label))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
            }
            if let current = series.first {
                ForEach(current.points) { point in
                    AreaMark(x: .value("Day", point.day),
                             y: .value(metric.label, point.value))
                        .foregroundStyle(
                            .linearGradient(colors: [Theme.accent.opacity(0.35),
                                                     Theme.accent.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                ForEach(current.points) { point in
                    LineMark(x: .value("Day", point.day),
                             y: .value(metric.label, point.value),
                             series: .value("Year", current.label))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if let day = scrubDay, let current = series.first {
                RuleMark(x: .value("Day", day))
                    .foregroundStyle(Theme.accent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Day", day),
                          y: .value(metric.label, current.value(onOrBefore: day)))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(90)
            }
        }
        .chartXScale(domain: 1...366)
        .chartXAxis {
            AxisMarks(values: [1, 60, 121, 182, 244, 305]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text(monthTick(day)).font(.etch(.caption2))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(metric.axisLabel(raw)).font(.etch(.caption2))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let frame = proxy.plotFrame else { return }
                                let x = drag.location.x - geometry[frame].origin.x
                                if let day: Int = proxy.value(atX: x) {
                                    scrubDay = min(366, max(1, day))
                                }
                            }
                            .onEnded { _ in scrubDay = nil }
                    )
            }
        }
        .overlay(alignment: .topTrailing) { yearKey }
    }

    private var yearKey: some View {
        HStack(spacing: 10) {
            if series.count == 2 {
                key(series[1].label, color: .secondary.opacity(0.55))
            }
            if let current = series.first {
                key(current.label, color: Theme.accent)
            }
        }
        .padding(.trailing, 4)
    }

    private func key(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(label).font(.etch(.caption2, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    /// Months or years as bars. The current one is the accent so "where am I now" never needs
    /// counting from the right-hand edge.
    private var bucketChart: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Period", bucket.label),
                    y: .value(metric.label, bucket.value))
                .foregroundStyle(bucket.isCurrent ? Theme.accent
                                                  : Theme.accent.opacity(0.28))
                .cornerRadius(5)
                .opacity(scrubBucket == nil || scrubBucket == bucket.label ? 1 : 0.4)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label).font(.etch(.caption2))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(metric.axisLabel(raw)).font(.etch(.caption2))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                guard let frame = proxy.plotFrame else { return }
                                let x = drag.location.x - geometry[frame].origin.x
                                scrubBucket = proxy.value(atX: x, as: String.self)
                            }
                            .onEnded { _ in scrubBucket = nil }
                    )
            }
        }
    }

    /// The first day of each labelled month, so the axis reads Jan/Mar/May/… rather than 1/60/121.
    private func monthTick(_ day: Int) -> String {
        switch day {
        case 1:   return "Jan"
        case 60:  return "Mar"
        case 121: return "May"
        case 182: return "Jul"
        case 244: return "Sep"
        case 305: return "Nov"
        default:  return ""
        }
    }
}
