import SwiftUI

/// A metric tile, set the way the brand sheet sets one: a small tracked uppercase label over a
/// large tabular figure, on a Gallery White card with a Mist hairline.
///
/// The label leads and the figure follows, which is the opposite of the arrangement this tile
/// used to have. It is the right way round: the label is what you read to know *which* number
/// you are looking at, and putting it underneath makes every tile a small puzzle solved
/// backwards. The figure still wins the tile by size.
struct StatTile: View {
    let value: String
    let label: String
    /// An optional glyph, set beside the label rather than above the figure — the sheet's tiles
    /// carry no icon, and one placed over the number competes with it.
    var systemName: String?
    /// Marks the tile as the notable one in a group by tinting its figure. Used sparingly; a
    /// wall of accented tiles accents nothing.
    var accent: Bool = false

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 5) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 10, weight: .medium))
                }
                Text(label)
            }
            .etchLabelStyle(10)
            .foregroundStyle(Theme.Ink.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(value)
                .font(.etchMetric(30, weight: .etchRoman))
                .foregroundStyle(accent ? Theme.accentText : Theme.Ink.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Theme.Surface.raised, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Line.hairline, lineWidth: 1)
        }
    }
}

/// A single-line superlative row (e.g. "Longest Run — 26.2 mi").
struct SuperlativeRow: View {
    let icon: String
    let title: String
    let value: String
    var subtitle: String?
    var action: (() -> Void)?
    /// Show a trailing chevron even without an inline action — e.g. when the row is used as
    /// the label of a `NavigationLink`.
    var showsChevron: Bool = false

    var body: some View {
        // Only wrap in a Button when there's an inline action. With no action the row renders
        // as plain content (not a disabled Button, which greyed it out) so it can serve as a
        // navigation-link label or a static row.
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.etch(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(value)
                .font(.etch(.headline))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
            if action != nil || showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
    }
}
