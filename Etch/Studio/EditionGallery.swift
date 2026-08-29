import SwiftUI

/// One finished look the user can choose, rather than assemble.
///
/// The audit's core product finding: Studio had drifted from a curated system into a configurator.
/// Ten authored editions existed but none was selectable — the editor opened on a tray of
/// orthogonal knobs, and most combinations of twelve free axes are worse than any authored edition.
/// This restores the intended model: choose a finished thing, then refine.
struct StudioStyle: Identifiable, Equatable {
    let id: String
    let name: String
    /// The editorial line from the underlying edition — what the look *is*, not a spec.
    let descriptor: String
    let family: PosterFamily
    let mapStyle: MapStyle?
    let galleryDesign: GalleryDesign?

    /// This style applied to an existing recipe, preserving everything the user has already set
    /// (their title, their data slots, their colours) — switching look is not starting over.
    func applied(to base: PosterConfig) -> PosterConfig {
        var c = base
        c.family = family
        if let mapStyle { c.mapStyle = mapStyle }
        if let galleryDesign { c.galleryDesign = galleryDesign }
        return c
    }

    func matches(_ c: PosterConfig) -> Bool {
        guard c.family == family else { return false }
        switch family {
        case .map:     return c.mapStyle == mapStyle
        case .gallery: return c.galleryDesign == galleryDesign
        }
    }

    /// The curated set for ONE product family — the fork happens before the editor, so a Map
    /// session never sees Gallery designs and vice versa. The two are different objects with
    /// different requirements; mixing their styles in one strip was the cross-contamination the
    /// overhaul removes.
    static func all(for run: Run, family: PosterFamily) -> [StudioStyle] {
        switch family {
        case .map:
            return MapStyle.allCases.map { style in
                StudioStyle(
                    id: "map-\(style.rawValue)",
                    name: style.name,
                    descriptor: style.edition.descriptor,
                    family: .map,
                    mapStyle: style,
                    galleryDesign: nil
                )
            }
        case .gallery:
            // Gallery works without photographs too — frames can show the map, the route line,
            // and the elevation profile; photos join whenever the run has them.
            return GalleryDesign.allCases.map { design in
                StudioStyle(
                    id: "gallery-\(design.rawValue)",
                    name: design.name,
                    descriptor: run.photoReferences.isEmpty
                        ? "The map, the route, and the elevation, composed."
                        : "Your photographs, the route, and the map, composed.",
                    family: .gallery,
                    mapStyle: nil,
                    galleryDesign: design
                )
            }
        }
    }
}

/// A horizontally scrolling row of *this activity* already rendered through every curated style.
///
/// The point is that the user sees their own marathon as Midnight Atlas immediately, rather than
/// choosing between abstract option names and hoping. Thumbnails render one at a time in the
/// background — never all at once — and the art panels behind them are cached by `PosterMap`, so
/// the strip costs one render per style per session and nothing thereafter.
struct EditionGalleryStrip: View {
    let run: Run
    @Binding var config: PosterConfig

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var styles: [StudioStyle] = []

    /// Thumbnails are rendered small — the composition is 1000pt wide, so this is a ~340px card.
    private static let thumbnailScale: CGFloat = 0.34
    private static let cardWidth: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
                .font(.etch(size: 11, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(styles) { style in
                        card(for: style)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .onAppear { if styles.isEmpty { styles = StudioStyle.all(for: run, family: config.family) } }
        .task(id: "\(run.id)-\(config.family.rawValue)") { await renderThumbnails() }
    }

    private func card(for style: StudioStyle) -> some View {
        let selected = style.matches(config)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                config = style.applied(to: config)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // The style's own ground stands in until its thumbnail arrives, so the strip
                    // reads as a row of materials rather than a row of grey boxes.
                    RoundedRectangle(cornerRadius: 8)
                        .fill(groundColor(for: style))
                    if let image = thumbnails[style.id] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(.rect(cornerRadius: 8))
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .tint(style.family == .map ? style.mapStyle?.edition.accent : Theme.accent)
                    }
                }
                .frame(width: Self.cardWidth, height: Self.cardWidth * 1.5)   // 2:3, as printed
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Theme.accent : Color.primary.opacity(0.10),
                                      lineWidth: selected ? 2 : 0.5)
                }

                Text(style.name)
                    .font(.etch(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .lineLimit(1)
            }
            .frame(width: Self.cardWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.name). \(style.descriptor)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func groundColor(for style: StudioStyle) -> Color {
        style.family == .map ? (style.mapStyle?.edition.ground ?? Theme.Palette.bone) : Theme.Palette.bone
    }

    /// Renders each style's thumbnail in turn, current selection first so the strip resolves where
    /// the user is looking. Sequential on purpose — eight simultaneous map snapshots is exactly the
    /// thundering herd the caching work was meant to prevent.
    private func renderThumbnails() async {
        let all = StudioStyle.all(for: run, family: config.family)
        styles = all
        let ordered = all.sorted { a, _ in a.matches(config) }
        for style in ordered {
            if Task.isCancelled { return }
            guard thumbnails[style.id] == nil else { continue }
            var recipe = style.applied(to: config)
            // Thumbnails show the *look*, not the user's copy — keep them uncluttered and identical
            // in content so the comparison is fair.
            recipe.outputSize = .poster
            let image = await StudioRenderer.image(for: recipe.request(for: run),
                                                   scale: Self.thumbnailScale)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.18)) {
                thumbnails[style.id] = image
            }
        }
    }
}
