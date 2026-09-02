import SwiftUI

/// **Customize** — the deep end, behind one level of disclosure.
///
/// The root shows palettes and five doors, not thirty controls. Every property the old Text tab
/// exposed on one screen still exists; each now lives behind the door it belongs to, and each door
/// carries its current value so the whole section can be read without opening anything.
///
/// The drill-down is *in place* rather than a navigation push. Pushing would replace the screen,
/// and the screen is where the poster is — the artwork has to stay visible while its colours are
/// being changed, or the user is choosing blind.
struct StudioCustomizeEditor: View {
    let run: Run
    @Binding var config: PosterConfig
    /// Asks the tray for more height — the sub-editors want it.
    var onNeedRoom: () -> Void

    @State private var detail: Detail?

    enum Detail: String, Identifiable {
        case typography, colours, route, layout, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .typography: return "Typography"
            case .colours:    return "Text & Colours"
            case .route:      return "Route"
            case .layout:     return "Layout"
            case .advanced:   return "Advanced"
            }
        }
    }

    var body: some View {
        Group {
            if let detail {
                VStack(alignment: .leading, spacing: 14) {
                    StudioDetailHeader(title: detail.title) {
                        withAnimation(.easeInOut(duration: 0.22)) { self.detail = nil }
                    }
                    switch detail {
                    case .typography: typography
                    case .colours:    colours
                    case .route:      route
                    case .layout:     layout
                    case .advanced:   advanced
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                root
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    // MARK: Root

    private var root: some View {
        VStack(alignment: .leading, spacing: 14) {
            palettes
            VStack(spacing: 0) {
                door(.typography, value: StudioTypeSystem.current(for: config)?.name ?? "Custom",
                     icon: "textformat")
                Divider()
                door(.colours, value: paletteName, icon: "paintpalette")
                Divider()
                door(.route, value: config.routeColor == nil ? "Auto" : "Custom",
                     icon: "point.topleft.down.to.point.bottomright.curvepath")
                Divider()
                door(.layout,
                     value: config.family == .map ? config.mapLayout.name : config.orientation.name,
                     icon: "square.resize")
                Divider()
                door(.advanced, value: config.monochrome ? "B & W" : config.outputSize.name,
                     icon: "slider.horizontal.3")
            }

            // The way out. Every control here can be nudged and several of them interact, so a
            // recipe can end up somewhere the user cannot retrace — and until now the only route
            // back was to remember which six things they had touched. Content is untouched: the
            // title, the data and the photographs are theirs, and this resets how the poster
            // looks, not what it says.
            if isDefaulted == false {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        config.textColor = nil
                        config.groundColor = nil
                        config.routeColor = nil
                        config.monochrome = false
                        config.textScale = 1
                        config.titleScale = 1
                        config.locationScale = 1
                        config.dateScale = 1
                        config.heroScale = 1
                        config.statScale = 1
                        config.font = .editorial
                    }
                } label: {
                    Label("Reset appearance", systemImage: "arrow.counterclockwise")
                        .font(.etch(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Theme.accent.opacity(0.10), in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    /// Whether anything under Customize has been moved off its default — the reset only appears
    /// when there is something to undo.
    private var isDefaulted: Bool {
        isAutoPalette && !config.monochrome && config.font == .editorial
            && [config.textScale, config.titleScale, config.locationScale,
                config.dateScale, config.heroScale, config.statScale].allSatisfy { abs($0 - 1) < 0.01 }
    }

    private func door(_ target: Detail, value: String?, icon: String) -> some View {
        StudioDrillRow(title: target.title, value: value, systemImage: icon) {
            withAnimation(.easeInOut(duration: 0.22)) { detail = target }
            onNeedRoom()
        }
    }

    /// True when all three inks are left to the chosen style. This is what a fresh poster is, and
    /// it is not "Custom" — nothing has been customised yet.
    private var isAutoPalette: Bool {
        config.textColor == nil && config.groundColor == nil && config.routeColor == nil
    }

    private var paletteName: String {
        if isAutoPalette { return "Auto" }
        return StudioPalette.current(for: config)?.name ?? "Custom"
    }

    private var palettes: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Palette")
            let active = StudioPalette.current(for: config)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Auto leads, and it is the state a new poster opens in — so the selected
                    // chip is the first one rather than one scrolled off the right-hand end.
                    // It is also the only way back: without it, returning to the style's own
                    // colours meant opening Colours and tapping Auto on three separate rows.
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config.textColor = nil
                            config.groundColor = nil
                            config.routeColor = nil
                        }
                    } label: {
                        Text("Auto")
                            .font(.etch(size: 12, weight: .semibold))
                            .foregroundStyle(isAutoPalette ? .white : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(isAutoPalette ? Theme.accent : Color.secondary.opacity(0.12),
                                        in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isAutoPalette ? [.isSelected] : [])

                    ForEach(StudioPalette.allCases) { palette in
                        paletteChip(palette, isSelected: active == palette)
                    }
                    // "Custom" is lit only when the colours are genuinely hand-set — neither a
                    // named palette nor Auto. Testing `active == nil` alone would light it
                    // beside Auto on every new poster.
                    let isCustom = active == nil && !isAutoPalette
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) { detail = .colours }
                        onNeedRoom()
                    } label: {
                        Text(isCustom ? "Custom" : "Custom…")
                            .font(.etch(size: 12, weight: .semibold))
                            .foregroundStyle(isCustom ? .white : Theme.accent)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(isCustom ? Theme.accent : Theme.accent.opacity(0.12),
                                        in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func paletteChip(_ palette: StudioPalette, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { config = palette.applied(to: config) }
        } label: {
            HStack(spacing: 7) {
                let c = palette.colors
                ZStack {
                    Circle().fill(c.ground).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                    Circle().fill(c.route).frame(width: 8, height: 8)
                }
                Text(palette.name)
                    .font(.etch(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isSelected ? Theme.accent : Color.secondary.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Typography

    @State private var typeAdvanced = false

    private var typography: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioGroupLabel(text: "Type system")
            HStack(spacing: 8) {
                ForEach(StudioTypeSystem.allCases) { system in
                    let on = StudioTypeSystem.current(for: config) == system
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config = system.applied(to: config)
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text("Aa")
                                .font(.etch(size: 20, weight: system.font.titleWeight,
                                            face: system.font.face))
                            Text(system.name).font(.etch(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(on ? .white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(on ? Theme.accent : Color.secondary.opacity(0.12),
                                    in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            scaleRow("Overall scale", $config.textScale)

            // Where the text sits on the sheet. Auto keeps each layout's authored alignment;
            // Filled sets the title at the exact size that spans the column.
            StudioGroupLabel(text: "Justification")
            HStack(spacing: 8) {
                ForEach(TextJustification.allCases) { option in
                    let on = config.textJustification == option
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config.textJustification = option
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: option.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(option.name).font(.etch(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(on ? .white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Theme.accent : Color.secondary.opacity(0.12),
                                    in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.name) justification")
                }
            }

            DisclosureGroup(isExpanded: $typeAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    // The face on its own, for someone who wants a system's rhythm with another
                    // system's letterforms.
                    StudioGroupLabel(text: "Typeface")
                    HStack(spacing: 8) {
                        ForEach(PosterFont.allCases) { face in
                            Button { config.font = face } label: {
                                Text(face.name)
                                    .font(.etch(size: 11, weight: .semibold, face: face.face))
                                    .foregroundStyle(config.font == face ? .white : Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(config.font == face ? Theme.accent
                                                                    : Color.secondary.opacity(0.12),
                                                in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // The three text lines keep the wider six-step range they have always had —
                    // a date can go genuinely small or a title genuinely huge without
                    // unbalancing the piece, which is not true of the headline or the data rows.
                    scaleRow("Title", $config.titleScale, wide: true)
                    scaleRow("Location", $config.locationScale, wide: true)
                    if config.family == .map {
                        scaleRow("Date", $config.dateScale, wide: true)
                        scaleRow("Headline", $config.heroScale)
                    }
                    scaleRow("Data", $config.statScale)
                }
                .padding(.top, 8)
            } label: {
                Text("Advanced")
                    .font(.etch(.subheadline, weight: .semibold))
            }
            .tint(Theme.accent)
        }
    }

    /// Every size control in the editor, in one shape, on exactly the steps the old editor used —
    /// so a saved poster reopens on the size it was saved at rather than snapping to the nearest
    /// survivor. `wide` carries the six-step range the individual text lines have always had.
    private func scaleRow(_ title: String, _ scale: Binding<CGFloat>,
                          wide: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.etch(.caption, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 84, alignment: .leading)
            Picker(title, selection: scale) {
                if wide { Text("XS").tag(CGFloat(0.7)) }
                Text("S").tag(CGFloat(0.85))
                Text("M").tag(CGFloat(1.0))
                Text("L").tag(CGFloat(1.15))
                Text("XL").tag(CGFloat(1.3))
                if wide { Text("XXL").tag(CGFloat(1.5)) }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Colours

    private var colours: some View {
        VStack(alignment: .leading, spacing: 14) {
            palettes
            colorRow("Text", selection: $config.textColor,
                     swatches: [Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass],
                     fallback: config.edition.ink)
            colorRow("Panel", selection: $config.groundColor,
                     swatches: [Theme.Palette.bone, Theme.Palette.ink, Theme.Palette.forest],
                     fallback: config.edition.ground)
            colorRow("Route", selection: $config.routeColor,
                     swatches: [Theme.Palette.blue, Theme.Palette.ink, Theme.Palette.bone,
                                Theme.Palette.brass, Theme.Palette.sage],
                     fallback: config.edition.route)
            Toggle(isOn: $config.monochrome) {
                Label("Black & white", systemImage: "circle.lefthalf.filled")
                    .font(.etch(.subheadline))
            }
            .tint(Theme.accent)
        }
    }

    // MARK: Route

    private var route: some View {
        VStack(alignment: .leading, spacing: 14) {
            colorRow("Colour", selection: $config.routeColor,
                     swatches: [Theme.Palette.blue, Theme.Palette.ink, Theme.Palette.bone,
                                Theme.Palette.brass, Theme.Palette.sage],
                     fallback: config.edition.route)

            // Said plainly rather than shipped as dead controls. Route weight, casing and glow are
            // real properties — they live on the edition (`StudioEdition.routeWidth`, `casing`,
            // `glow`) and each style sets its own — but nothing in the recipe overrides them, so
            // there is no thickness or marker control to surface here yet. Drawing sliders that
            // did nothing would be worse than the gap.
            Text("Route weight and casing come from the chosen map style. Per-poster control over thickness and start/finish markers needs renderer work — it is not hidden elsewhere in this editor.")
                .font(.caption)
                .foregroundStyle(Color.secondary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Layout

    private var layout: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The arrangement, with the other arrangement controls. It used to be a fifth gallery
            // of picture cards at the top of Design, which is where the section tipped from a
            // chooser into a catalogue — and it is a refinement, not a starting decision: the
            // Style row above already set it.
            if config.family == .map {
                StudioGroupLabel(text: "Template")
                Picker("Template", selection: $config.mapLayout) {
                    ForEach(MapLayout.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(templateDescription)
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            StudioGroupLabel(text: "Orientation")
            Picker("Orientation", selection: $config.orientation) {
                ForEach(StudioOrientation.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)

            // Only landscape can move the data — portrait always stacks it beneath the art, which
            // is the composition's rule and not a control we are withholding.
            if config.orientation == .landscape {
                StudioGroupLabel(text: "Data position")
                Picker("Data position", selection: $config.dataPlacement) {
                    ForEach(StudioDataPlacement.allCases) { p in
                        Image(systemName: p.symbol).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Text("In portrait the data always sits beneath the artwork. Switch to landscape to move it.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What each arrangement actually does, so the menu is readable without trying all five.
    private var templateDescription: String {
        switch config.mapLayout {
        case .nameplate: return "The place named large at the top, the map beneath, the figures in a row along the foot."
        case .statement: return "The distance set as a headline under the map, with the place and date beneath it."
        case .minimal:   return "The map, the title and the date. Nothing else."
        case .photo:     return "The map above, your photographs filling the space beneath it."
        case .fullBleed: return "The map runs to every edge, with the type set over it and the figures in the corners."
        }
    }

    // MARK: Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $config.monochrome) {
                Label("Black & white", systemImage: "circle.lefthalf.filled")
                    .font(.etch(.subheadline))
            }
            .tint(Theme.accent)

            StudioGroupLabel(text: "Share format")
            Picker("Share format", selection: $config.outputSize) {
                ForEach(StudioOutputSize.allCases) { size in
                    Text(size.name).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Text("Poster keeps print proportions. Square, Feed and Story mat the piece onto a social canvas for sharing — the print itself is always composed at poster proportions.")
                .font(.caption)
                .foregroundStyle(Color.secondary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Shared

    private func colorRow(_ title: String, selection: Binding<Color?>,
                          swatches: [Color], fallback: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StudioGroupLabel(text: title)
            HStack(spacing: 10) {
                Button { selection.wrappedValue = nil } label: {
                    Text("Auto")
                        .font(.etch(size: 11, weight: .semibold))
                        .foregroundStyle(selection.wrappedValue == nil ? .white : .secondary)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(selection.wrappedValue == nil ? Theme.accent
                                                                 : Color.secondary.opacity(0.15),
                                    in: .capsule)
                }
                .buttonStyle(.plain)

                ForEach(swatches.indices, id: \.self) { i in
                    Button { selection.wrappedValue = swatches[i] } label: {
                        Circle()
                            .fill(swatches[i])
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            .overlay(Circle().stroke(Theme.accent,
                                                     lineWidth: selection.wrappedValue == swatches[i] ? 2.5 : 0)
                                .padding(-3))
                    }
                    .buttonStyle(.plain)
                }

                ColorPicker("", selection: Binding(
                    get: { selection.wrappedValue ?? fallback },
                    set: { selection.wrappedValue = $0 }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)
            }
        }
    }
}
