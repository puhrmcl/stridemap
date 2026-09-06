import SwiftUI

/// **Customize** — quiet, deliberate refinements after the artwork is already composed.
///
/// Design owns the big visual decisions. Content owns what the piece says. Customize is only for
/// the handful of finishing choices that can make a finished piece feel more personal without
/// turning Studio into a settings screen.
struct StudioCustomizeEditor: View {
    let run: Run
    @Binding var config: PosterConfig
    /// Asks the editor tray for more height when a drill-down opens.
    var onNeedRoom: () -> Void

    @State private var detail: Detail?
    @State private var typeAdvanced = false

    enum Detail: String, Identifiable {
        case typography, colours, layout, sharing
        var id: String { rawValue }

        var title: String {
            switch self {
            case .typography: return "Typography"
            case .colours:    return "Colors"
            case .layout:     return "Layout"
            case .sharing:    return "Sharing"
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
                    case .layout:     layout
                    case .sharing:    sharing
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                root
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    // MARK: - Root

    private var root: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                door(.typography,
                     value: StudioTypeSystem.current(for: config)?.name ?? "Custom",
                     icon: "textformat")
                Divider()
                door(.colours, value: colourSummary, icon: "paintpalette")
                if config.family == .map {
                    Divider()
                    door(.layout, value: layoutSummary, icon: "rectangle.inset.filled")
                }
                Divider()
                door(.sharing, value: config.outputSize.name, icon: "square.and.arrow.up")
            }

            if !isDefaulted {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { resetAppearance() }
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

    private func door(_ target: Detail, value: String?, icon: String) -> some View {
        StudioDrillRow(title: target.title, value: value, systemImage: icon) {
            withAnimation(.easeInOut(duration: 0.22)) { detail = target }
            onNeedRoom()
        }
    }

    /// Design already owns the coordinated Look. This summary simply tells the reader whether the
    /// current inks still belong to one of those authored worlds or have been individually tuned.
    private var colourSummary: String {
        if let look = StudioLook.current(for: config) { return look.name }
        if let palette = StudioPalette.current(for: config) { return palette.name }
        if config.textColor == nil && config.groundColor == nil && config.routeColor == nil {
            return "Designed"
        }
        return "Custom"
    }

    private var layoutSummary: String {
        if config.mapLayout == .fullBleed { return "Edge to edge" }
        if config.orientation == .landscape {
            return config.dataPlacement.name
        }
        return config.mapInset ? "Bordered" : "Edge to edge"
    }

    private var isDefaulted: Bool {
        config.textColor == nil
            && config.groundColor == nil
            && config.routeColor == nil
            && !config.monochrome
            && config.font == .editorial
            && config.dataFont == .modern
            && config.textJustification == .automatic
            && [config.textScale, config.titleScale, config.locationScale,
                config.dateScale, config.heroScale, config.statScale]
                .allSatisfy { abs($0 - 1) < 0.01 }
    }

    /// Resets only the visual fine-tuning. Content, photographs, layout choices and share format
    /// are intentionally untouched — a reset should never erase a decision about what the piece is.
    private func resetAppearance() {
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
        config.dataFont = .modern
        config.textJustification = .automatic
    }

    // MARK: - Typography

    private var typography: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioGroupLabel(text: "Type system")
            HStack(spacing: 8) {
                ForEach(StudioTypeSystem.allCases) { system in
                    let selected = StudioTypeSystem.current(for: config) == system
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config = system.applied(to: config)
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text("Aa")
                                .font(.etch(size: 20,
                                            weight: system.font.titleWeight,
                                            face: system.font.face))
                            Text(system.name)
                                .font(.etch(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(selected ? .white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected ? Theme.accent : Color.secondary.opacity(0.12),
                                    in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }

            scaleRow("Overall scale", $config.textScale)

            StudioGroupLabel(text: "Alignment")
            HStack(spacing: 8) {
                ForEach(TextJustification.allCases) { option in
                    let selected = config.textJustification == option
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config.textJustification = option
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: option.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(option.name)
                                .font(.etch(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(selected ? .white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.accent : Color.secondary.opacity(0.12),
                                    in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.name) alignment")
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }

            DisclosureGroup(isExpanded: $typeAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    StudioGroupLabel(text: "Title typeface")
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

                    StudioGroupLabel(text: "Data typeface")
                    HStack(spacing: 8) {
                        ForEach(PosterFont.allCases) { face in
                            Button { config.dataFont = face } label: {
                                Text(face.name)
                                    .font(.etch(size: 11, weight: .semibold, face: face.face))
                                    .foregroundStyle(config.dataFont == face ? .white : Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(config.dataFont == face ? Theme.accent
                                                                        : Color.secondary.opacity(0.12),
                                                in: .rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
                Text("Fine tune")
                    .font(.etch(.subheadline, weight: .semibold))
            }
            .tint(Theme.accent)
        }
    }

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

    // MARK: - Colors

    /// The coordinated colour world is chosen visually in Design. These are the three deliberate
    /// per-ink overrides for someone who wants to refine that authored starting point.
    private var colours: some View {
        VStack(alignment: .leading, spacing: 14) {
            colorRow("Text", selection: $config.textColor,
                     swatches: [Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass],
                     fallback: config.edition.ink)
            colorRow("Paper", selection: $config.groundColor,
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

    // MARK: - Layout

    /// Only the layout refinements that Design does not already expose. The template and
    /// orientation remain where the user chose them visually; this avoids two controls for the
    /// same decision in two different sections.
    @ViewBuilder
    private var layout: some View {
        VStack(alignment: .leading, spacing: 14) {
            if config.mapLayout == .fullBleed {
                Label("This layout is edge to edge by design.", systemImage: "rectangle.inset.filled")
                    .font(.etch(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                StudioGroupLabel(text: "Map frame")
                Picker("Map frame", selection: $config.mapInset) {
                    Text("Edge to Edge").tag(false)
                    Text("Bordered").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if config.orientation == .landscape {
                StudioGroupLabel(text: "Data position")
                Picker("Data position", selection: $config.dataPlacement) {
                    ForEach(StudioDataPlacement.allCases) { placement in
                        Image(systemName: placement.symbol).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Sharing

    private var sharing: some View {
        VStack(alignment: .leading, spacing: 10) {
            StudioGroupLabel(text: "Share format")
            Picker("Share format", selection: $config.outputSize) {
                ForEach(StudioOutputSize.allCases) { size in
                    Text(size.name).tag(size)
                }
            }
            .pickerStyle(.segmented)

            Text("Poster preserves the print composition. Square, Feed and Story place that same artwork on a sharing canvas without changing the print itself.")
                .font(.caption)
                .foregroundStyle(Color.secondary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Shared

    private func colorRow(_ title: String, selection: Binding<Color?>,
                          swatches: [Color], fallback: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            StudioGroupLabel(text: title)
            HStack(spacing: 11) {
                Button { selection.wrappedValue = nil } label: {
                    Text("Designed")
                        .font(.etch(size: 11, weight: .semibold))
                        .foregroundStyle(selection.wrappedValue == nil ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(selection.wrappedValue == nil ? Theme.accent
                                                                 : Color.secondary.opacity(0.15),
                                    in: .capsule)
                }
                .buttonStyle(.plain)

                ForEach(swatches.indices, id: \.self) { index in
                    Button { selection.wrappedValue = swatches[index] } label: {
                        Circle()
                            .fill(swatches[index])
                            .frame(width: 27, height: 27)
                            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            .overlay {
                                Circle()
                                    .stroke(Theme.accent,
                                            lineWidth: selection.wrappedValue == swatches[index] ? 2.5 : 0)
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose \(title.lowercased()) color")
                }

                ColorPicker("Custom \(title.lowercased()) color", selection: Binding(
                    get: { selection.wrappedValue ?? fallback },
                    set: { selection.wrappedValue = $0 }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)
            }
        }
    }
}
