import SwiftUI
import SwiftData

/// Etch Studio's poster editor, remodelled around two products — a **Map** poster and a **Gallery**
/// poster — each refined through a small, tabbed control tray (Style · Text · Data · Export) beneath
/// a live preview. Deliberately editorial: the artwork is the hero, chrome stays quiet, and one
/// decision is made at a time.
struct StudioView: View {
    let run: Run
    /// When opened from a kept poster, its stored recipe seeds the editor and future saves update it
    /// in place instead of creating a duplicate.
    private let existingPoster: SavedPoster?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The single source of truth the whole editor binds to.
    @State private var config: PosterConfig

    /// Which control tab is showing.
    private enum Tab: String, CaseIterable, Identifiable {
        case style, text, data, export
        var id: String { rawValue }
        var name: String {
            switch self {
            case .style: return "Style"
            case .text: return "Text"
            case .data: return "Data"
            case .export: return "Export"
            }
        }
        var icon: String {
            switch self {
            case .style: return "paintpalette"
            case .text: return "textformat"
            case .data: return "chart.bar"
            case .export: return "square.and.arrow.up"
            }
        }
    }
    @State private var tab: Tab = .style

    @State private var showPrints = false
    @State private var showExport = false
    /// Presenting the library picker to add a photo to this run.
    @State private var showPhotoPicker = false
    /// The kept poster this composition is linked to, once saved — so a second Save updates the
    /// same piece rather than piling up copies.
    @State private var savedPosterID: UUID?
    @State private var showSavedConfirmation = false
    @State private var confirmationText = "Kept in Studio"

    @State private var rendered: UIImage?
    @State private var isRendering = false
    /// The text fields' debounced value — what the render key actually reads.
    @State private var debouncedText = ""
    /// True when the last render came back nil, so the canvas can explain itself.
    @State private var renderFailed = false

    init(run: Run, poster: SavedPoster? = nil) {
        self.run = run
        self.existingPoster = poster
        if let poster {
            _config = State(initialValue: PosterConfig(poster: poster))
            _savedPosterID = State(initialValue: poster.id)
        } else {
            _config = State(initialValue: PosterConfig.makeDefault(for: run))
        }
    }

    private let pathSwatches: [Color] = [
        Theme.Palette.blue, Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass, Theme.Palette.sage
    ]
    private let textSwatches: [Color] = [Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass]
    private let groundSwatches: [Color] = [Theme.Palette.bone, Theme.Palette.ink, Theme.Palette.forest]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                productPicker
                preview
                Divider()
                trayTabBar
                tray
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Etch Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay(alignment: .top) { savedConfirmation }
            // Hand the composed artwork to the shop so the frame mockup shows the user's own piece
            // rather than a placeholder — the whole point of the preview.
            .sheet(isPresented: $showPrints) {
                PrintShopView(subjectTitle: config.title.isEmpty ? run.name : config.title,
                              artwork: rendered)
            }
            .sheet(isPresented: $showExport) { StudioExportSheet(request: config.request(for: run)) }
            .sheet(isPresented: $showPhotoPicker) {
                AssetPhotoPicker(selectionLimit: 4) { ids in addPhotos(ids) }
                    .ignoresSafeArea()
            }
            .task(id: renderKey) { await renderPreview() }
            // Debounce the free-text fields: commit them ~350ms after typing stops, so the preview
            // re-renders once per edit rather than once per keystroke.
            .task(id: liveText) {
                let text = liveText
                if !debouncedText.isEmpty || !text.isEmpty {
                    try? await Task.sleep(for: .milliseconds(350))
                }
                guard !Task.isCancelled else { return }
                debouncedText = text
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if savedPosterID == nil {
                    Button { saveAsNew() } label: { Label("Keep in Studio", systemImage: "bookmark") }
                } else {
                    Button { updateSaved() } label: {
                        Label("Update saved", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { saveAsNew() } label: {
                        Label("Save as new copy", systemImage: "plus.square.on.square")
                    }
                    Button(role: .destructive) { removeSaved() } label: {
                        Label("Remove from Studio", systemImage: "bookmark.slash")
                    }
                }
            } label: {
                Image(systemName: savedPosterID == nil ? "bookmark" : "bookmark.fill")
            }
            .accessibilityLabel(savedPosterID == nil ? "Keep in Studio" : "Saved — options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showPrints = true } label: { Image(systemName: "bag") }
        }
    }

    @ViewBuilder private var savedConfirmation: some View {
        if showSavedConfirmation {
            Label(confirmationText, systemImage: "checkmark.circle.fill")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.accent, in: .capsule)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Product picker

    private var productPicker: some View {
        Picker("Product", selection: $config.family) {
            ForEach(PosterFamily.allCases) { family in
                Label(family.name, systemImage: family.icon).tag(family)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Preview

    /// Aspect (w/h) of the current output — the social canvas when one is chosen, else the poster.
    private var previewAspect: CGFloat {
        if let aspect = config.outputSize.aspect { return aspect }
        let s = StudioComposition.nominalSize(config.orientation, config.dataPlacement)
        return s.width / s.height
    }

    private var preview: some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let rendered {
                    Image(uiImage: rendered)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(config.groundColor ?? config.edition.ground)
                        .aspectRatio(previewAspect, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                if renderFailed && !isRendering {
                                    // A nil render used to leave this panel blank indefinitely with
                                    // a spinner that never resolved. Name the likely cause instead.
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.secondary)
                                    Text("This activity can't be composed")
                                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text("It needs a recorded route. Try another activity, or a style without a map.")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 26)
                                } else {
                                ProgressView().tint(config.edition.accent)
                                Text("Composing…")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                }
            }
            .padding(.horizontal, 30)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Tray

    private var trayTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(.easeInOut(duration: 0.18)) { tab = t } } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 16, weight: .semibold))
                        Text(t.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(tab == t ? Theme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var tray: some View {
        ScrollView {
            VStack(spacing: 14) {
                switch tab {
                case .style:  styleTab
                case .text:   textTab
                case .data:   dataTab
                case .export: exportTab
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(height: 250)
        .scrollBounceBehavior(.basedOnSize)
        .background(.regularMaterial)
    }

    // MARK: Style tab

    @ViewBuilder private var styleTab: some View {
        // Lead with the piece itself, rendered through every curated style. Choosing a finished
        // look is the first decision; the controls beneath refine it.
        EditionGalleryStrip(run: run, config: $config)
        if config.family == .map {
            // The layout beneath the map — sits directly under the style strip.
            chipRow("Layout", MapLayout.allCases, selection: $config.mapLayout,
                    label: { $0.name }, icon: { $0.icon })
            if config.mapLayout == .photo { mapPhotoControls }
        } else {
            // The style strip above already picks the Gallery design, so no second control for it.
            galleryFramesEditor
            addPhotoButton
        }
        colorModeToggle
        orientationPicker
        // Where the data sits relative to the art — only meaningful in landscape (portrait always
        // stacks the data beneath the art).
        if config.orientation == .landscape { dataPlacementPicker }
    }

    /// Photo controls for the map Photo layout — how many photos, plus Add Photo.
    private var mapPhotoControls: some View {
        VStack(spacing: 8) {
            Stepper("Photos: \(config.mapPhotoCount)", value: $config.mapPhotoCount, in: 1...3)
                .font(.system(.subheadline, design: .rounded))
                .frame(maxWidth: 300)
            addPhotoButton
        }
        .frame(maxWidth: 340)
    }

    /// Adds a photo from the library to this run — so it appears in the poster *and* in the run's
    /// activity details (both read `Run.photoReferences`).
    private var addPhotoButton: some View {
        Button {
            Task { await PhotoLibrary.requestAuthorization(); showPhotoPicker = true }
        } label: {
            Label(run.photoReferences.isEmpty ? "Add Photo" : "Add Photo · \(run.photoReferences.count) on run",
                  systemImage: "photo.badge.plus")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: 300)
                .frame(height: 44)
                .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// Landscape only: place the data column left / right of the art, or across the top / bottom.
    private var dataPlacementPicker: some View {
        VStack(spacing: 6) {
            Text("DATA POSITION")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Data position", selection: $config.dataPlacement) {
                ForEach(StudioDataPlacement.allCases) { p in
                    Image(systemName: p.symbol).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: 340)
    }

    private var colorModeToggle: some View {
        Picker("Colour", selection: $config.monochrome) {
            Text("Colour").tag(false)
            Text("B & W").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }

    private var orientationPicker: some View {
        Picker("Orientation", selection: $config.orientation) {
            ForEach(StudioOrientation.allCases) { Label($0.name, systemImage: $0.symbol).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }

    /// Per-frame media pickers for the Gallery product — each frame shows a Photo, the Map, the
    /// Route line, or the Elevation profile.
    private var galleryFramesEditor: some View {
        VStack(spacing: 6) {
            Text("FRAMES")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(0..<config.galleryDesign.frameCount, id: \.self) { i in
                    Menu {
                        Picker("Frame", selection: frameBinding(i)) {
                            ForEach(GalleryTileKind.allCases) { kind in
                                Label(kind.name, systemImage: kind.icon).tag(kind)
                            }
                        }
                    } label: {
                        let kind = frameKind(i)
                        VStack(spacing: 3) {
                            Image(systemName: kind.icon).font(.system(size: 15, weight: .semibold))
                            Text(kind.name).font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 340)
    }

    private func frameKind(_ i: Int) -> GalleryTileKind {
        let frames = config.resolvedFrames
        return i < frames.count ? frames[i] : .photo
    }

    private func frameBinding(_ i: Int) -> Binding<GalleryTileKind> {
        Binding(
            get: { frameKind(i) },
            set: { newValue in
                var frames = config.resolvedFrames
                guard frames.indices.contains(i) else { return }
                frames[i] = newValue
                config.galleryFrames = frames
            }
        )
    }

    // MARK: Text tab

    @ViewBuilder private var textTab: some View {
        toggleFieldRow("Title", show: $config.showTitle, text: $config.title, placeholder: run.name)
        toggleFieldRow("Location", show: $config.showLocation, text: $config.location,
                       placeholder: derivedPlace)
        textFieldRow("Date", text: $config.date, placeholder: Format.date(run.startDate))
        fontPicker
        textSizePicker
        colorRow("Text", selection: $config.textColor, swatches: textSwatches, fallback: config.edition.ink)
        colorRow("Panel", selection: $config.groundColor, swatches: groundSwatches, fallback: config.edition.ground)
        colorRow("Path", selection: $config.routeColor, swatches: pathSwatches, fallback: config.edition.route)
    }

    private var derivedPlace: String {
        [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Scales all of the poster's type up or down together (Small … XL).
    private var textSizePicker: some View {
        HStack(spacing: 10) {
            Text("Size")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Picker("Text size", selection: $config.textScale) {
                Text("S").tag(CGFloat(0.85))
                Text("M").tag(CGFloat(1.0))
                Text("L").tag(CGFloat(1.15))
                Text("XL").tag(CGFloat(1.3))
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: 340)
    }

    private var fontPicker: some View {
        HStack(spacing: 10) {
            Text("Font")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            ForEach(PosterFont.allCases) { face in
                Button { config.font = face } label: {
                    VStack(spacing: 2) {
                        Text(face.sample)
                            .font(.system(size: 20, weight: face.titleWeight, design: face.design))
                        Text(face.name)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(config.font == face ? .white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(config.font == face ? Theme.accent : Color.secondary.opacity(0.12),
                                in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 340)
    }

    // MARK: Data tab

    @ViewBuilder private var dataTab: some View {
        // The big headline metric, chosen from the same set as the data slots.
        HStack(spacing: 10) {
            Text("Headline")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Menu {
                ForEach(StatMetric.allCases) { metric in
                    Button {
                        config.heroMetric = metric
                    } label: {
                        if metric == config.heroMetric {
                            Label(metric.menuName, systemImage: "checkmark")
                        } else {
                            Text(metric.menuName)
                        }
                    }
                    .disabled(!metric.isAvailable(for: run))
                }
            } label: {
                slotChip(config.heroMetric)
            }
            .menuStyle(.borderlessButton)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 340)

        VStack(spacing: 8) {
            Stepper("Data points: \(config.dataSlots.count)", value: slotCount, in: 0...4)
                .font(.system(.subheadline, design: .rounded))
                .frame(maxWidth: 300)
            if config.dataSlots.isEmpty {
                Text("No data shown — just the art and title.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ForEach(config.dataSlots.indices, id: \.self) { i in
                        Menu {
                            ForEach(StatMetric.allCases) { metric in
                                Button {
                                    config.dataSlots[i] = metric
                                } label: {
                                    if metric == config.dataSlots[i] {
                                        Label(metric.menuName, systemImage: "checkmark")
                                    } else {
                                        Text(metric.menuName)
                                    }
                                }
                                .disabled(!metric.isAvailable(for: run))
                            }
                        } label: {
                            slotChip(config.dataSlots[i])
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                .frame(maxWidth: 340)
            }
        }

        Toggle(isOn: $config.showElevation) {
            Label("Elevation profile", systemImage: "mountain.2")
                .font(.system(.subheadline, design: .rounded))
        }
        .tint(Theme.accent)
        .frame(maxWidth: 300)

        if run.hasWeather {
            Toggle(isOn: $config.includeWeather) {
                Label("Include weather", systemImage: "cloud.sun")
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(Theme.accent)
            .frame(maxWidth: 300)
        }
    }

    private var slotCount: Binding<Int> {
        Binding(
            get: { config.dataSlots.count },
            set: { n in
                var slots = config.dataSlots
                let pool: [StatMetric] = [.time, .pace, .elevationGain, .speed, .avgHeartRate, .calories]
                while slots.count < n { slots.append(pool.first { !slots.contains($0) } ?? .time) }
                while slots.count > n { slots.removeLast() }
                config.dataSlots = slots
            }
        )
    }

    // MARK: Export tab

    @ViewBuilder private var exportTab: some View {
        Picker("Output", selection: $config.outputSize) {
            ForEach(StudioOutputSize.allCases) { size in
                Label(size.name, systemImage: size.symbol).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 340)

        Text("Poster keeps print proportions; Square / Feed / Story mat it onto a social canvas.")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

        Button { showExport = true } label: {
            Label("Share / Save Image", systemImage: "square.and.arrow.up")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 300)
                .frame(height: 46)
                .background(Theme.accent, in: .capsule)
        }
        .buttonStyle(.plain)

        Button { showPrints = true } label: {
            Label("Order a Print", systemImage: "bag")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: 300)
                .frame(height: 46)
                .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared control components

    /// A horizontal chip row for an enum choice (map style, gallery design), with a header.
    private func chipRow<T: Hashable & Identifiable>(
        _ header: String, _ options: [T], selection: Binding<T>,
        label: @escaping (T) -> String, icon: @escaping (T) -> String
    ) -> some View {
        VStack(spacing: 6) {
            Text(header.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let isOn = selection.wrappedValue == option
                        Button { selection.wrappedValue = option } label: {
                            VStack(spacing: 4) {
                                Image(systemName: icon(option)).font(.system(size: 16, weight: .semibold))
                                Text(label(option)).font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(isOn ? .white : Color.primary)
                            .frame(width: 66, height: 52)
                            .background(isOn ? Theme.accent : Color.secondary.opacity(0.12),
                                        in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: 340)
    }

    private func textFieldRow(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(.subheadline, design: .rounded))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 340)
    }

    /// A field row with a show/hide toggle at the front — for Title and Location.
    private func toggleFieldRow(_ title: String, show: Binding<Bool>, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Button { show.wrappedValue.toggle() } label: {
                Image(systemName: show.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(show.wrappedValue ? Theme.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(.subheadline, design: .rounded))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .disabled(!show.wrappedValue)
                .opacity(show.wrappedValue ? 1 : 0.4)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 340)
    }

    private func slotChip(_ metric: StatMetric) -> some View {
        VStack(spacing: 2) {
            Text(metric == .none ? "None" : (metric.value(for: run) ?? "—"))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(metric == .none ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(metric == .none ? "BLANK" : metric.label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    private func colorRow(_ title: String, selection: Binding<Color?>, swatches: [Color], fallback: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            autoChip(isSelected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
            ForEach(swatches.indices, id: \.self) { i in
                swatchDot(swatches[i], isSelected: selection.wrappedValue == swatches[i]) {
                    selection.wrappedValue = swatches[i]
                }
            }
            ColorPicker("", selection: Binding(
                get: { selection.wrappedValue ?? fallback },
                set: { selection.wrappedValue = $0 }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32)
        }
        .frame(maxWidth: 340)
    }

    private func autoChip(isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Auto")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(isSelected ? Theme.accent : Color.secondary.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func swatchDot(_ color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Circle().stroke(Theme.accent, lineWidth: isSelected ? 2.5 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Keeping

    private var linkedPoster: SavedPoster? {
        guard let id = savedPosterID else { return nil }
        return try? modelContext.fetch(
            FetchDescriptor<SavedPoster>(predicate: #Predicate { $0.id == id })
        ).first
    }

    private func saveAsNew() {
        let poster = SavedPoster(runID: run.id, runName: run.name)
        config.write(into: poster, run: run)
        modelContext.insert(poster)
        savedPosterID = poster.id
        confirm("Kept in Studio")
    }

    private func updateSaved() {
        guard let existing = linkedPoster else { saveAsNew(); return }
        config.write(into: existing, run: run)
        confirm("Updated")
    }

    private func removeSaved() {
        if let existing = linkedPoster { modelContext.delete(existing) }
        savedPosterID = nil
        confirm("Removed from Studio")
    }

    private func confirm(_ text: String) {
        confirmationText = text
        withAnimation(.spring(duration: 0.35)) { showSavedConfirmation = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { showSavedConfirmation = false }
        }
    }

    // MARK: Rendering

    /// A compact signature of every render-affecting field — one `task(id:)` re-renders the preview
    /// when any of them changes.
    private var renderKey: String {
        [config.family.rawValue, config.mapStyle.rawValue,
         config.mapLayout.rawValue, "\(config.mapPhotoCount)", "\(run.photoReferences.count)",
         "\(config.textScale)",
         config.galleryDesign.rawValue,
         config.resolvedFrames.map(\.rawValue).joined(separator: ","),
         "\(config.monochrome)", config.orientation.rawValue, config.dataPlacement.rawValue,
         // Text fields use their *debounced* mirrors. Typing a title used to re-render the whole
         // composition — and start a fresh map snapshot — on every keystroke.
         config.font.rawValue, "\(config.showTitle)", debouncedText,
         "\(config.showLocation)",
         config.heroMetric.rawValue,
         config.dataSlots.map(\.rawValue).joined(separator: ","),
         "\(config.showElevation)", "\(config.includeWeather)", config.outputSize.rawValue,
         config.routeColor?.hexString ?? "-", config.textColor?.hexString ?? "-",
         config.groundColor?.hexString ?? "-"
        ].joined(separator: "|")
    }

    /// The three free-text fields, as one value. Debounced into `debouncedText` so the preview
    /// re-renders once the user pauses, not once per character.
    private var liveText: String { [config.title, config.location, config.date].joined(separator: "\u{1F}") }

    /// Preview render scale. The composition is authored 1000pt wide, so scale 1.5 gives a
    /// 1500px-wide preview — comfortably sharp on any device at a quarter of the pixel work the
    /// previous `scale: 2` cost. Print export is unaffected; it renders at its own scale.
    private static let previewScale: CGFloat = 1.5

    private func renderPreview() async {
        isRendering = true
        defer { isRendering = false }
        let image = await StudioRenderer.image(for: config.request(for: run), scale: Self.previewScale)
        guard !Task.isCancelled else { return }
        rendered = image
        // A nil render used to leave the canvas silently blank forever; say so instead.
        renderFailed = (image == nil)
    }

    /// Appends newly picked library photos to this run (de-duplicated), which persists them on the
    /// run so they show both here and in the run's activity details, then re-renders the preview.
    private func addPhotos(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var refs = run.photoReferences
        for id in ids where !refs.contains(id) { refs.append(id) }
        guard refs.count != run.photoReferences.count else { return }
        run.photoReferences = refs
        try? modelContext.save()
    }
}
