import SwiftUI

/// One option in a thumbnail strip: how to apply it, and how to tell whether it is already on.
struct StudioVariant: Identifiable {
    let id: String
    let name: String
    let apply: (PosterConfig) -> PosterConfig
    let matches: (PosterConfig) -> Bool
}

/// A horizontally scrolling row of *this activity* rendered through each variant.
///
/// Generalised out of the old style strip, which could only ever show map styles. Templates,
/// layouts and styles are all "which of these do I want", and the honest answer to that question
/// is always the user's own run drawn each way — not a row of option names and a guess.
///
/// Renders one thumbnail at a time, never the whole row at once: a strip that kicked off eight
/// simultaneous map snapshots is exactly the thundering herd the snapshot cache exists to stop.
struct StudioVariantStrip: View {
    let run: Run
    @Binding var config: PosterConfig
    let variants: [StudioVariant]
    /// Changes to this string throw the cache away — used to keep template thumbnails honest when
    /// the map style beneath them changes.
    let refreshKey: String

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var renderedKey: String = ""

    private static let cardWidth: CGFloat = 82
    private static let thumbnailScale: CGFloat = 0.3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(variants) { variant in
                    StudioThumbCard(
                        title: variant.name,
                        isSelected: variant.matches(config),
                        width: Self.cardWidth,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                config = variant.apply(config)
                            }
                        }
                    ) {
                        ZStack {
                            Rectangle().fill(config.groundColor ?? config.edition.ground)
                            if let image = thumbnails[variant.id] {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .transition(.opacity)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 3)
        }
        .task(id: refreshKey) { await render() }
    }

    private func render() async {
        if renderedKey != refreshKey {
            thumbnails = [:]
            renderedKey = refreshKey
        }
        // The current selection first, so the strip resolves where the eye already is.
        let ordered = variants.sorted { a, _ in a.matches(config) }
        for variant in ordered {
            if Task.isCancelled { return }
            guard thumbnails[variant.id] == nil else { continue }
            var recipe = variant.apply(config)
            recipe.outputSize = .poster
            let image = await StudioRenderer.image(for: recipe.request(for: run),
                                                   scale: Self.thumbnailScale)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.18)) { thumbnails[variant.id] = image }
        }
    }
}

/// **Design** — the fast start. Four decisions, all visual, all reversible: the arrangement, the
/// map beneath it, the colour world, and the shape of the paper.
///
/// Nothing here exposes an individual property. That is the whole point of the section: a first
/// poster should be four taps of picking pictures, and every one of those taps should produce
/// something already worth printing.
struct StudioDesignEditor: View {
    let run: Run
    @Binding var config: PosterConfig
    /// Raises the tray when a control needs more room than the medium detent gives.
    var onNeedRoom: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            template
            if config.family == .map { mapStyle }
            look
            orientation
        }
    }

    // MARK: Template

    @ViewBuilder private var template: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: config.family == .map ? "Template" : "Layout")
            StudioVariantStrip(
                run: run, config: $config,
                variants: templateVariants,
                refreshKey: "template-\(config.family.rawValue)-\(config.mapStyle.rawValue)-\(config.orientation.rawValue)"
            )
        }
    }

    private var templateVariants: [StudioVariant] {
        switch config.family {
        case .map:
            return MapLayout.allCases.map { layout in
                StudioVariant(
                    id: "layout-\(layout.rawValue)",
                    name: layout.name,
                    apply: { var c = $0; c.mapLayout = layout; return c },
                    matches: { $0.mapLayout == layout }
                )
            }
        case .gallery:
            return GalleryDesign.allCases.map { design in
                StudioVariant(
                    id: "gallery-\(design.rawValue)",
                    name: design.name,
                    apply: { var c = $0; c.galleryDesign = design; return c },
                    matches: { $0.galleryDesign == design }
                )
            }
        }
    }

    // MARK: Map style

    private var mapStyle: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Map Style")
            StudioVariantStrip(
                run: run, config: $config,
                variants: MapStyle.allCases.map { style in
                    StudioVariant(
                        id: "map-\(style.rawValue)",
                        name: style.name,
                        apply: { var c = $0; c.mapStyle = style; return c },
                        matches: { $0.mapStyle == style }
                    )
                },
                refreshKey: "mapstyle-\(config.mapLayout.rawValue)-\(config.orientation.rawValue)"
            )
        }
    }

    // MARK: Look

    /// The coordinated colour worlds. Custom is shown, not hidden — a user who has hand-tuned a
    /// colour deserves to see that named rather than to see four presets none of which is lit.
    private var look: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Look")
            let active = StudioLook.current(for: config)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StudioLook.allCases) { look in
                        lookChip(look, isSelected: active == look)
                    }
                    if active == nil {
                        // The state the old editor could never show: your own colours, named.
                        Text("Custom")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Theme.accent.opacity(0.12), in: .capsule)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func lookChip(_ look: StudioLook, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { config = look.applied(to: config) }
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(look.groundSwatch)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    Circle().fill(look.routeSwatch).frame(width: 8, height: 8)
                }
                Text(look.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isSelected ? Theme.accent : Color.secondary.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Orientation

    private var orientation: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Orientation")
            Picker("Orientation", selection: $config.orientation) {
                ForEach(StudioOrientation.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}
