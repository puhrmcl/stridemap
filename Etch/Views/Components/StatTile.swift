import SwiftUI

/// A calm metric tile: big value, quiet label, optional icon.
struct StatTile: View {
    let value: String
    let label: String
    var systemName: String?
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(.subheadline, design: .default))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cardRadius))
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
                    .font(.system(.subheadline, design: .default).weight(.medium))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(value)
                .font(.system(.headline, design: .default))
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
