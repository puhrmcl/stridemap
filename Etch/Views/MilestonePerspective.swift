import SwiftUI

/// PERSPECTIVE — the totals, put beside something a person can picture.
///
/// "41,230 ft climbed" is a fact and not an image. "Everest, four and a half times over — and 62%
/// of the way to doing it five" is the same fact doing some work. This is the section that turns
/// an accumulated number into something the reader can feel, without inflating it: every rung is
/// a real figure, the cleared one is the largest actually passed, and the bar shows honest
/// progress toward the next rather than a invented score.
struct MilestonePerspective: View {
    let runs: [Run]

    private var comparisons: [MilestoneInsights.Comparison] {
        MilestoneInsights.perspective(runs)
    }

    var body: some View {
        let items = comparisons
        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("In perspective")
                        .font(.etch(.title2, weight: .bold))
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            card(item)
                        }
                    }
                }
            }
        }
    }

    private func card(_ item: MilestoneInsights.Comparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.total)
                    .font(.etch(size: 26, weight: .bold))
                    .monospacedDigit()
                Spacer(minLength: 10)
                if let multiple = item.multiple {
                    Text(multiple)
                        .font(.etch(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                }
            }
            Text(item.subject)
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The bar is the point of the card: a number beside a landmark is a comparison, a
            // number beside a landmark *and a distance still to run* is a thing you can act on.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.accent.opacity(0.12))
                    Capsule()
                        .fill(
                            .linearGradient(colors: [Theme.accent.opacity(0.7), Theme.accent],
                                            startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(6, geometry.size.width * item.progress))
                }
            }
            .frame(height: 8)

            Text(item.caption)
                .font(.etch(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
