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

/// A circular glass button for map affordances (locate, layers, nav, etc.). Rendered as a piece of
/// "liquid glass": a frosted disc with a top-lit sheen and a gradient hairline edge that catches the
/// light, for a more premium, tactile feel than a flat material fill.
struct GlassIconButton: View {
    let systemName: String
    var isActive: Bool = false
    /// Lighter than a filled glyph for a refined, modern line — override per-icon if needed.
    var weight: Font.Weight = .medium
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: weight))
                .foregroundStyle(isActive ? Theme.accentOnGlass : .primary)
                .frame(width: 48, height: 48)
                .glassCircle()
                .overlay {
                    // A whisper of accent glow when active, so selection reads as a lit state.
                    if isActive {
                        Circle().stroke(Theme.accentOnGlass.opacity(0.5), lineWidth: 1)
                    }
                }
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

// MARK: - Glass treatments

extension View {
    /// The premium circular glass used by the floating map controls: a frosted disc with a top-lit
    /// sheen and a gradient hairline rim that catches the light. Apply to a fixed-size square label.
    func glassCircle() -> some View {
        self
            .background {
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    // A soft top-down sheen reads as light falling across glass.
                    Circle().fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.02), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .overlay(
                // A brighter top edge, fading down — the lit rim of a glass disc.
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.30), .white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
            .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
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
