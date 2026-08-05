import SwiftUI

/// A floating, frosted-glass container used for every overlay control on the map.
/// Uses the native iOS 26 Liquid Glass effect where available, degrading gracefully.
struct GlassContainer<Content: View>: View {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = Theme.controlRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .glassBackground(cornerRadius: cornerRadius)
    }
}

/// A circular glass button for map affordances (locate, layers, etc.).
struct GlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : .primary)
                .frame(width: 46, height: 46)
                .glassBackground(cornerRadius: 23)
        }
        .buttonStyle(.plain)
    }
}

/// A small pill used to display a stat or an active filter.
struct GlassPill: View {
    let title: String
    var value: String?
    var systemName: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            if let value {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
            }
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassBackground(cornerRadius: 18)
    }
}

// MARK: - Glass background modifier

extension View {
    /// Applies a frosted-glass background, preferring the iOS 26 `glassEffect`.
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
    }
}
