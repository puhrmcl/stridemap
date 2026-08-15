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
                .foregroundStyle(isActive ? Theme.accentOnGlass : .primary)
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
                    .foregroundStyle(Theme.accentOnGlass)
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
    /// A frosted background for floating controls.
    ///
    /// NOTE: temporarily using the plain material on all versions. Applying `.glassEffect`
    /// to interactive button labels appears to break their touch handling on iOS 26 (the
    /// controls didn't even register taps and menus flickered). If the material fixes it,
    /// glass is reintroduced properly via `.buttonStyle(.glass)` / interactive glass.
    @ViewBuilder
    func glassBackground(cornerRadius: CGFloat) -> some View {
        self
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}
