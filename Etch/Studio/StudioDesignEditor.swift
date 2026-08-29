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
    /// Presets get a larger card than the axis strips: they are the decision the section leads
    /// with, and a chooser you are meant to decide from has to be big enough to decide from.
    var cardWidth: CGFloat = 88

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var renderedKey: String = ""

    private static let thumbnailScale: CGFloat = 0.3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(variants) { variant in
                    StudioThumbCard(
                        title: variant.name,
                        isSelected: variant.matches(config),
                        width: cardWidth,
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

    /// Two rows of pictures and two compact controls.
    ///
    /// It was four stacked scrollers — seven presets, five templates, ten map styles, four looks —
    /// twenty-six choices in one section, which is not a design surface, it is a catalogue. Style
    /// is the decision; Map is the one axis people genuinely want to move; Look and Orientation are
    /// small enough to be rows rather than galleries. The arrangement moved in with the other
    /// arrangement controls, under Customize › Layout, where orientation and data position already
    /// lived.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if config.family == .map {
                presets
                mapMaterial
            } else {
                template
            }
            look
            orientation
        }
    }

    // MARK: Start here

    /// Seven finished posters, first thing. One tap and the piece is done — which is the promise
    /// the section made and could not keep while it opened on three separate axes that only mean
    /// something in combination.
    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Start here")
            StudioVariantStrip(
                run: run, config: $config,
                variants: StudioPreset.all.map { preset in
                    StudioVariant(
                        id: "preset-\(preset.id)",
                        name: preset.name,
                        apply: { preset.applied(to: $0) },
                        matches: { preset.matches($0) }
                    )
                },
                // Presets are whole compositions, so their cards do not follow the recipe the way
                // the axis strips do — only the content changes them.
                refreshKey: "presets-\(config.orientation.rawValue)",
                cardWidth: 96
            )
        }
    }

    // MARK: Layout — Gallery only

    /// The Gallery product's arrangement. A Gallery sheet has no map and no presets, so this row
    /// *is* its starting decision and stays here; the Map product's templates moved to
    /// Customize › Layout, where they are a refinement of what a preset already chose.
    private var template: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Layout")
            StudioVariantStrip(
                run: run, config: $config,
                variants: GalleryDesign.allCases.map { design in
                    StudioVariant(
                        id: "gallery-\(design.rawValue)",
                        name: design.name,
                        apply: { var c = $0; c.galleryDesign = design; return c },
                        matches: { $0.galleryDesign == design }
                    )
                },
                refreshKey: "gallery-\(config.orientation.rawValue)",
                cardWidth: 96
            )
        }
    }

    // MARK: Map

    /// Five materials, not ten styles. The colour comes from Look, so this row asks one question
    /// and asks it once.
    private var mapMaterial: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Map")
            StudioVariantStrip(
                run: run, config: $config,
                variants: MapMaterial.allCases.map { material in
                    StudioVariant(
                        id: "material-\(material.rawValue)",
                        name: material.name,
                        apply: { base in
                            var c = base
                            c.mapStyle = material.style(for: StudioLook.current(for: base))
                            return c
                        },
                        matches: { MapMaterial.of($0.mapStyle) == material }
                    )
                },
                refreshKey: "material-\(config.mapLayout.rawValue)-\(config.orientation.rawValue)-\(StudioLook.current(for: config)?.rawValue ?? "custom")"
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
