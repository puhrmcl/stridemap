import SwiftUI

/// RHYTHM — when the reader actually moves, as a polar week.
///
/// This is the section that tells someone something they do not already know. Totals and records
/// are facts they lived through; *"Sunday mornings are yours — 31% of everything you do"* is a
/// pattern that only exists once a few hundred activities are read at once, and nobody holds that
/// in their head.
///
/// Seven sectors for the days, four rings for the parts of a day, each cell's fill carrying its
/// share. A polar layout rather than a grid because a week is a cycle: Sunday sits next to Monday
/// here, which is where it actually is, and the eye reads the whole shape of a habit at once
/// instead of scanning a table.
struct MilestoneRhythm: View {
    let runs: [Run]

    @State private var selected: (weekday: Int, band: MilestoneInsights.Band)?

    private var rhythm: MilestoneInsights.Rhythm { MilestoneInsights.rhythm(runs) }

    var body: some View {
        let grid = rhythm
        return VStack(alignment: .leading, spacing: 14) {
            Text("Your rhythm")
                .font(.etch(.title2, weight: .bold))

            if grid.total == 0 {
                Text("Once there are a few activities on record, this is where the shape of your week shows up.")
                    .font(.etch(.subheadline)).foregroundStyle(.secondary)
            } else {
                if let headline = MilestoneInsights.rhythmHeadline(grid) {
                    Text(headline)
                        .font(.etch(.headline, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .center, spacing: 18) {
                    dial(grid)
                        .frame(width: 200, height: 200)
                    legend(grid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(detail(grid))
                    .font(.etch(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.2), value: detail(grid))
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
    }

    // MARK: The dial

    private func dial(_ grid: MilestoneInsights.Rhythm) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // The wheel stops short of the frame so the day initials have a ring of their own to
            // sit in. They were drawn over the sectors in white, which is unreadable against a
            // pale cell and barely better against a dark one — a label whose legibility depends
            // on how busy that day was is not a label.
            let outer = side / 2 * 0.82
            let labelRadius = side / 2 * 0.95
            // The hub is left empty: a sector that converges to a point is unreadable at the
            // centre and un-tappable, and the hole gives the total somewhere to sit.
            let inner = outer * 0.26
            let ringWidth = (outer - inner) / CGFloat(MilestoneInsights.Band.allCases.count)
            let busiest = max(1, grid.busiest)

            ZStack {
                ForEach(0..<7, id: \.self) { weekday in
                    ForEach(MilestoneInsights.Band.allCases) { band in
                        let count = grid.count(weekday: weekday, band: band)
                        let share = Double(count) / Double(busiest)
                        let isSelected = selected.map {
                            $0.weekday == weekday && $0.band == band
                        } ?? false
                        RhythmSector(
                            startAngle: angle(weekday),
                            endAngle: angle(weekday + 1),
                            innerRadius: inner + ringWidth * CGFloat(band.rawValue),
                            outerRadius: inner + ringWidth * CGFloat(band.rawValue + 1)
                        )
                        .fill(Theme.accent.opacity(count == 0 ? 0.05 : 0.18 + 0.72 * share))
                        .overlay {
                            if isSelected {
                                RhythmSector(
                                    startAngle: angle(weekday),
                                    endAngle: angle(weekday + 1),
                                    innerRadius: inner + ringWidth * CGFloat(band.rawValue),
                                    outerRadius: inner + ringWidth * CGFloat(band.rawValue + 1)
                                )
                                .stroke(Theme.accent, lineWidth: 2)
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selected = isSelected ? nil : (weekday, band)
                            }
                        }
                    }
                }

                // Day initials, outside the wheel and on the card's own ground.
                ForEach(0..<7, id: \.self) { weekday in
                    let mid = (angle(weekday) + angle(weekday + 1)) / 2
                    let isPeak = selected?.weekday == weekday
                    Text(MilestoneInsights.weekdayName(weekday, short: true))
                        .font(.etch(.caption2, weight: .bold))
                        .foregroundStyle(isPeak ? Theme.accent : Color.secondary)
                        .position(x: centre.x + labelRadius * cos(mid * .pi / 180),
                                  y: centre.y + labelRadius * sin(mid * .pi / 180))
                }

                Text("\(grid.total)")
                    .font(.etch(.headline, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity rhythm by day and time of day")
        .accessibilityValue(MilestoneInsights.rhythmHeadline(grid) ?? "\(grid.total) activities")
    }

    /// Sectors start at the top and run clockwise, so Monday is at twelve o'clock.
    private func angle(_ weekday: Int) -> Double {
        -90 + Double(weekday) * (360.0 / 7.0)
    }

    // MARK: Legend and detail

    private func legend(_ grid: MilestoneInsights.Rhythm) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(MilestoneInsights.Band.allCases.reversed()) { band in
                let count = (0..<7).reduce(0) { $0 + grid.count(weekday: $1, band: band) }
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.accent.opacity(0.25 + 0.2 * Double(band.rawValue)))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(band.label)
                            .font(.etch(.caption, weight: .semibold))
                        Text("\(count)")
                            .font(.etch(.caption2))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func detail(_ grid: MilestoneInsights.Rhythm) -> String {
        if let pick = selected {
            let count = grid.count(weekday: pick.weekday, band: pick.band)
            let day = MilestoneInsights.weekdayName(pick.weekday)
            guard count > 0 else { return "No \(day) \(pick.band.label.lowercased())s on record." }
            let share = Int((Double(count) / Double(max(1, grid.total)) * 100).rounded())
            return "\(count) \(count == 1 ? "activity" : "activities") on \(day) \(pick.band.label.lowercased())s — \(share)% of everything."
        }
        return "Tap any segment to read it. Rings run outward from night to evening."
    }
}

/// One cell of the dial: the area between two angles and two radii.
struct RhythmSector: Shape {
    let startAngle: Double
    let endAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // A hairline of inset on every side so neighbouring cells read as separate tiles rather
        // than one continuous wash — the gap is what makes the shape legible.
        let gap = 1.1
        var path = Path()
        path.addArc(center: centre, radius: outerRadius,
                    startAngle: .degrees(startAngle + gap), endAngle: .degrees(endAngle - gap),
                    clockwise: false)
        path.addArc(center: centre, radius: max(0, innerRadius + 1.5),
                    startAngle: .degrees(endAngle - gap), endAngle: .degrees(startAngle + gap),
                    clockwise: true)
        path.closeSubpath()
        return path
    }
}
