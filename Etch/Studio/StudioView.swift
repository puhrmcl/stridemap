import SwiftUI
import SwiftData

/// Etch Studio: a gallery-like way to turn a run into a finished piece. The user swipes
/// through curated *editions* — each a complete composition — and can retune the path and text
/// colours from a curated set before exporting. Deliberately editorial: the artwork is the
/// hero, chrome stays quiet.
struct StudioView: View {
    let run: Run
    /// When opened from a kept poster, its stored recipe seeds every control below and future
    /// saves update it in place instead of creating a duplicate.
    private let existingPoster: SavedPoster?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var selection: StudioEdition.ID = .gallery
    @State private var includeWeather = false
    @State private var routeColor: Color?
    @State private var textColor: Color?
    @State private var groundColor: Color?
    @State private var layout: StudioLayout = .classic
    @State private var orientation: StudioOrientation = .portrait
    @State private var dataPlacement: StudioDataPlacement = .side
    @State private var photoLayout: StudioPhotoLayout = .single
    /// The share/export canvas — Poster (native) or a social aspect (Square / Feed / Story).
    @State private var outputSize: StudioOutputSize = .poster
    @State private var customTitle = ""
    @State private var customDate = ""
    @State private var showEditorialPhoto = false
    @State private var showMemoryRoute = false
    @State private var heroMetric: StatMetric = .distance
    @State private var statSlots: [StatMetric] = [.time, .pace, .elevationGain]
    @State private var showElevationProfile = false
    @State private var galleryShowMapTile = false
    @State private var showPrints = false
    @State private var showCustomize = false
    @State private var showExport = false
    /// The id of the kept poster this composition is linked to, once saved — so a second Save
    /// updates the same piece rather than piling up copies.
    @State private var savedPosterID: UUID?
    /// Drives the brief confirmation pill after a keep/update/remove.
    @State private var showSavedConfirmation = false
    @State private var confirmationText = "Kept in Studio"
    /// Bumped on any customization change; part of the cache key so artwork re-renders.
    @State private var revision = 0

    @State private var rendered: [String: UIImage] = [:]
    @State private var rendering: Set<String> = []

    init(run: Run, poster: SavedPoster? = nil) {
        self.run = run
        self.existingPoster = poster
        guard let p = poster else {
            // A fresh poster defaults its metrics to what suits the activity — speed for rides,
            // elevation for hikes, pace for runs.
            let defaults = StatMetric.defaults(for: run.activityType)
            _heroMetric = State(initialValue: defaults.hero)
            _statSlots = State(initialValue: defaults.slots)
            return
        }
        _selection = State(initialValue: p.editionID)
        _includeWeather = State(initialValue: p.includeWeather)
        _routeColor = State(initialValue: Color(hex: p.routeColorHex))
        _textColor = State(initialValue: Color(hex: p.textColorHex))
        _groundColor = State(initialValue: Color(hex: p.groundColorHex))
        _layout = State(initialValue: StudioLayout(rawValue: p.layoutRaw) ?? .classic)
        _orientation = State(initialValue: StudioOrientation(rawValue: p.orientationRaw) ?? .portrait)
        _dataPlacement = State(initialValue: StudioDataPlacement(rawValue: p.dataPlacementRaw) ?? .side)
        _photoLayout = State(initialValue: StudioPhotoLayout(rawValue: p.photoLayoutRaw) ?? .single)
        _customTitle = State(initialValue: p.customTitle)
        _customDate = State(initialValue: p.customDate)
        _showEditorialPhoto = State(initialValue: p.showEditorialPhoto)
        _showMemoryRoute = State(initialValue: p.showMemoryRoute)
        _heroMetric = State(initialValue: StatMetric(rawValue: p.heroMetricRaw) ?? .distance)
        let slots = p.statSlotsRaw.compactMap { StatMetric(rawValue: $0) }
        _statSlots = State(initialValue: slots.isEmpty ? [.time, .pace, .elevationGain] : slots)
        _showElevationProfile = State(initialValue: p.showElevationProfile)
        _savedPosterID = State(initialValue: p.id)
    }

    private let pathSwatches: [Color] = [
        Theme.Palette.blue, Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass, Theme.Palette.sage
    ]
    private let textSwatches: [Color] = [Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass]
    private let groundSwatches: [Color] = [Theme.Palette.ink, Theme.Palette.forest, Theme.Palette.bone]

    private var editions: [StudioEdition] { StudioEdition.available(for: run) }
    private var current: StudioEdition { StudioEdition.edition(selection) }
    private func key(_ id: StudioEdition.ID) -> String { "\(id.rawValue)-\(revision)" }
    private var currentKey: String { key(selection) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(editions) { edition in
                        page(for: edition).tag(edition.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                controls
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Etch Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                        .sheet(isPresented: $showExport) {
                            StudioExportSheet(request: request(for: current))
                        }
                }
            }
            .overlay(alignment: .top) { savedConfirmation }
            .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: run.name) }
            .task(id: currentKey) { await renderIfNeeded(selection) }
        }
    }

    /// A brief pill confirming the composition was kept, so the user knows it's now in Studio.
    @ViewBuilder
    private var savedConfirmation: some View {
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

    /// Aspect (w/h) of the current output — the social canvas when one is chosen, else the poster.
    private var previewAspect: CGFloat {
        if let aspect = outputSize.aspect { return aspect }
        let s = StudioComposition.nominalSize(orientation, dataPlacement)
        return s.width / s.height
    }

    // MARK: Pages

    private func page(for edition: StudioEdition) -> some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let image = rendered[key(edition.id)] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(edition.id == selection ? (groundColor ?? edition.ground) : edition.ground)
                        .aspectRatio(previewAspect, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                ProgressView().tint(edition.accent)
                                Text("Composing…")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(edition.subtle)
                            }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
    }

    // MARK: Controls

    /// Format pickers — extracted so the customize VStack stays within the type-checker's budget.
    @ViewBuilder private var formatControls: some View {
        if current.isPhoto, run.photoReferences.count > 1 {
            Picker("Photos", selection: $photoLayout) {
                ForEach(StudioPhotoLayout.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 320)
        }
        Picker("Orientation", selection: $orientation) {
            ForEach(StudioOrientation.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented).frame(maxWidth: 320)
        Picker("Output", selection: $outputSize) {
            ForEach(StudioOutputSize.allCases) { size in
                Label(size.name, systemImage: size.symbol).tag(size)
            }
        }
        .pickerStyle(.segmented).frame(maxWidth: 320)
        if orientation == .landscape {
            Picker("Data", selection: $dataPlacement) {
                ForEach(StudioDataPlacement.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 320)
        }
        Picker("Layout", selection: $layout) {
            ForEach(StudioLayout.allCases) { Text($0.name).tag($0) }
        }
        .pickerStyle(.segmented).frame(maxWidth: 320)
    }

    /// Title / date / colour rows — extracted for the same reason.
    @ViewBuilder private var fieldControls: some View {
        textFieldRow("Title", text: $customTitle, placeholder: run.name)
        textFieldRow("Date", text: $customDate, placeholder: Format.date(run.startDate))
        colorRow("Path", selection: $routeColor, swatches: pathSwatches, fallback: current.route)
        colorRow("Text", selection: $textColor, swatches: textSwatches, fallback: current.ink)
        colorRow("Panel", selection: $groundColor, swatches: groundSwatches, fallback: current.ground)
    }

    /// The option toggles for the customize sheet — extracted so the customize VStack stays within
    /// the Swift type-checker's budget.
    @ViewBuilder private var optionToggles: some View {
        if layout == .editorial, !run.photoReferences.isEmpty {
            Toggle(isOn: $showEditorialPhoto) {
                Label("Photo beside text", systemImage: "photo")
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(Theme.accent)
            .frame(maxWidth: 280)
        }

        if current.isPhoto {
            Toggle(isOn: $showMemoryRoute) {
                Label("Show route in layout", systemImage: "scribble.variable")
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(Theme.accent)
            .frame(maxWidth: 280)
        }

        Toggle(isOn: $showElevationProfile) {
            Label("Elevation profile", systemImage: "mountain.2")
                .font(.system(.subheadline, design: .rounded))
        }
        .tint(Theme.accent)
        .frame(maxWidth: 280)

        if layout == .gallery && run.hasRoute {
            Toggle(isOn: $galleryShowMapTile) {
                Label("Map as a tile", systemImage: "map")
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(Theme.accent)
            .frame(maxWidth: 280)
        }

        if run.hasWeather {
            Toggle(isOn: $includeWeather) {
                Label("Include weather", systemImage: "cloud.sun")
                    .font(.system(.subheadline, design: .rounded))
            }
            .tint(Theme.accent)
            .frame(maxWidth: 280)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(editions) { edition in
                    Circle()
                        .fill(edition.id == selection ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            VStack(spacing: 2) {
                Text(current.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(current.descriptor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showCustomize.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.caption)
                    Text("Customize")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Image(systemName: showCustomize ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            if showCustomize {
                ScrollView {
                    VStack(spacing: 12) {
                    formatControls
                    fieldControls

                    headlineEditor

                    if layout != .minimal {
                        statSlotEditor
                    }

                    optionToggles
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 300)
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .onChange(of: includeWeather) { bump() }
        .onChange(of: routeColor) { bump() }
        .onChange(of: textColor) { bump() }
        .onChange(of: groundColor) { bump() }
        .onChange(of: layout) { bump() }
        .onChange(of: orientation) { bump() }
        .onChange(of: dataPlacement) { bump() }
        .onChange(of: photoLayout) { bump() }
        .onChange(of: customTitle) { bump() }
        .onChange(of: customDate) { bump() }
        .onChange(of: showEditorialPhoto) { bump() }
        .onChange(of: showMemoryRoute) { bump() }
        .onChange(of: heroMetric) { bump() }
        .onChange(of: statSlots) { bump() }
        .onChange(of: showElevationProfile) { bump() }
        .onChange(of: galleryShowMapTile) { bump() }
        .onChange(of: outputSize) { bump() }
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

    /// The big headline metric — tap to swap the hero number (distance by default) for any
    /// available metric.
    private var headlineEditor: some View {
        HStack(spacing: 10) {
            Text("Headline")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Menu {
                ForEach(StatMetric.allCases) { metric in
                    Button {
                        heroMetric = metric
                    } label: {
                        if metric == heroMetric {
                            Label(metric.menuName, systemImage: "checkmark")
                        } else {
                            Text(metric.menuName)
                        }
                    }
                    .disabled(!metric.isAvailable(for: run))
                }
            } label: {
                slotChip(heroMetric)
            }
            .menuStyle(.borderlessButton)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 340)
    }

    /// "Complication"-style stat slots: tap a slot to choose which metric it shows, from a
    /// curated set. Unavailable metrics (no HR, etc.) are greyed out.
    private var statSlotEditor: some View {
        HStack(spacing: 10) {
            Text("Stats")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
            ForEach(statSlots.indices, id: \.self) { i in
                Menu {
                    ForEach(StatMetric.allCases) { metric in
                        Button {
                            statSlots[i] = metric
                        } label: {
                            if metric == statSlots[i] {
                                Label(metric.menuName, systemImage: "checkmark")
                            } else {
                                Text(metric.menuName)
                            }
                        }
                        .disabled(!metric.isAvailable(for: run))
                    }
                } label: {
                    slotChip(statSlots[i])
                }
                .menuStyle(.borderlessButton)
            }
        }
        .frame(maxWidth: 340)
    }

    private func slotChip(_ metric: StatMetric) -> some View {
        VStack(spacing: 2) {
            Text(metric.value(for: run) ?? "—")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(metric.label)
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

    /// The kept poster this composition is currently linked to, if any.
    private var linkedPoster: SavedPoster? {
        guard let id = savedPosterID else { return nil }
        return try? modelContext.fetch(
            FetchDescriptor<SavedPoster>(predicate: #Predicate { $0.id == id })
        ).first
    }

    /// A fresh SavedPoster capturing the current composition.
    private func makePoster() -> SavedPoster {
        SavedPoster(
            runID: run.id, runName: run.name,
            editionRaw: selection.rawValue, layoutRaw: layout.rawValue,
            orientationRaw: orientation.rawValue, dataPlacementRaw: dataPlacement.rawValue,
            photoLayoutRaw: photoLayout.rawValue, customTitle: customTitle, customDate: customDate,
            heroMetricRaw: heroMetric.rawValue, statSlotsRaw: statSlots.map(\.rawValue),
            showEditorialPhoto: showEditorialPhoto, showMemoryRoute: showMemoryRoute,
            showElevationProfile: showElevationProfile, includeWeather: includeWeather,
            routeColorHex: routeColor?.hexString, textColorHex: textColor?.hexString,
            groundColorHex: groundColor?.hexString
        )
    }

    /// Keep the current composition as a *new* piece in Studio, and link to it — so the same run
    /// can hold several saved versions (a Gallery and a Night, say).
    private func saveAsNew() {
        let poster = makePoster()
        modelContext.insert(poster)
        savedPosterID = poster.id
        confirm("Kept in Studio")
    }

    /// Overwrite the linked kept poster with the current composition.
    private func updateSaved() {
        guard let existing = linkedPoster else { saveAsNew(); return }
        writeRecipe(into: existing)
        confirm("Updated")
    }

    /// Un-keep: remove the linked poster from Studio.
    private func removeSaved() {
        if let existing = linkedPoster { modelContext.delete(existing) }
        savedPosterID = nil
        confirm("Removed from Studio")
    }

    /// Flash a brief confirmation pill.
    private func confirm(_ text: String) {
        confirmationText = text
        withAnimation(.spring(duration: 0.35)) { showSavedConfirmation = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { showSavedConfirmation = false }
        }
    }

    /// Copy the live controls into an existing kept poster.
    private func writeRecipe(into p: SavedPoster) {
        p.runName = run.name
        p.editionRaw = selection.rawValue
        p.layoutRaw = layout.rawValue
        p.orientationRaw = orientation.rawValue
        p.dataPlacementRaw = dataPlacement.rawValue
        p.photoLayoutRaw = photoLayout.rawValue
        p.customTitle = customTitle
        p.customDate = customDate
        p.heroMetricRaw = heroMetric.rawValue
        p.statSlotsRaw = statSlots.map(\.rawValue)
        p.showEditorialPhoto = showEditorialPhoto
        p.showMemoryRoute = showMemoryRoute
        p.showElevationProfile = showElevationProfile
        p.includeWeather = includeWeather
        p.routeColorHex = routeColor?.hexString
        p.textColorHex = textColor?.hexString
        p.groundColorHex = groundColor?.hexString
        p.updatedAt = Date()
    }

    // MARK: Rendering

    private func bump() {
        rendered.removeAll()
        rendering.removeAll()
        revision += 1
    }

    private func renderIfNeeded(_ id: StudioEdition.ID) async {
        let k = key(id)
        guard rendered[k] == nil, !rendering.contains(k) else { return }
        rendering.insert(k)
        defer { rendering.remove(k) }
        if let image = await render(StudioEdition.edition(id)) {
            rendered[k] = image
        }
    }

    @MainActor
    private func render(_ edition: StudioEdition) async -> UIImage? {
        await StudioRenderer.image(for: request(for: edition), scale: 2)
    }

    /// The render request for a given edition, using the current layout/colour/weather options.
    private func request(for edition: StudioEdition) -> StudioRenderer.Request {
        StudioRenderer.Request(
            run: run, edition: edition, layout: layout, orientation: orientation,
            dataPlacement: dataPlacement,
            photoLayout: photoLayout,
            titleOverride: customTitle.isEmpty ? nil : customTitle,
            dateOverride: customDate.isEmpty ? nil : customDate,
            showEditorialPhoto: showEditorialPhoto,
            showMemoryRoute: showMemoryRoute,
            heroMetric: heroMetric, statSlots: statSlots, showElevationProfile: showElevationProfile,
            galleryShowMapTile: galleryShowMapTile,
            includeWeather: includeWeather, routeColor: routeColor, textColor: textColor,
            groundColor: groundColor, outputSize: outputSize
        )
    }
}
