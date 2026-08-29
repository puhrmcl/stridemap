import SwiftUI

/// The shared geometry system for the floating map controls, so the 3D button, the right-side
/// map-type / location capsule, and any future control read as one Apple Maps-style family rather
/// than a set of independently-sized buttons. One number drives them all: the control diameter sets
/// the capsule width and its corner radius (radius = size / 2 → true semicircular caps).
enum MapControl {
    /// The diameter of a single control button — tuned to Apple Maps' compact floating controls.
    static let size: CGFloat = 46
    /// Inset of the control group from the screen edges, matching the reference's tight margins.
    static let edgeInset: CGFloat = 14
}

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
                    .font(.etch(.subheadline, weight: .bold))
                    .contentTransition(.numericText())
            }
            Text(title)
                .font(.etch(.caption, weight: .medium))
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
            // Fill an explicit continuous-corner shape rather than the `in:` parameter — the latter
            // can flash square corners for a frame while the material resolves on first appearance.
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

extension View {
    /// Makes floating map chrome take its appearance from the *map*, not the phone.
    ///
    /// This is why the wordmark went missing from the home pill, and it was never absent from the
    /// view — it was invisible.
    ///
    /// Glass here is `.ultraThinMaterial`, which takes its luminance from whatever is behind it.
    /// Over Night, Satellite or Hybrid the pill is dark whatever the phone is set to. Everything
    /// *inside* the pill, though, resolves against the app's colour scheme: `.primary` is black in
    /// light mode, and the `BrandLogo` asset serves its ink cut. So a phone in light mode showing
    /// a dark base map drew a near-black wordmark on near-black glass, and the mark simply was not
    /// there to look at. The same combination is what made the blue chrome unreadable earlier —
    /// one cause, two reports.
    ///
    /// Overriding the colour scheme to match the base map fixes all of it at once: the asset flips
    /// to its paper cut, `.primary` and `.secondary` invert, and the material resolves to the dark
    /// variant that belongs over dark terrain. The chrome floats on the map, so it should dress
    /// like the map.
    func mapChromeAppearance(_ style: MapStyleOption) -> some View {
        environment(\.colorScheme, style.isDarkBase ? .dark : .light)
    }
}
