import SwiftUI
import SwiftData

/// Etch Studio's poster editor.
///
/// Two products — a **Map** poster and a **Gallery** poster — refined through three sections
/// beneath a persistent live preview: **Design** (choose a starting point), **Content** (decide
/// what the poster says), **Customize** (refine how it says it).
///
/// The sections replaced Style · Text · Data · Export, which had become a settings form: every
/// property the composition owned was exposed at the same altitude, on four flat screens, in the
/// renderer's vocabulary rather than the reader's. Nothing was removed in the change — the
/// granular controls moved one level down, behind the decision they belong to, so a first poster
/// is a handful of taps on pictures and the hundredth can still be tuned to the letter.
///
/// Export stopped being a workspace and became what it always was: an action. Share and Order sit
/// permanently under the artwork; the share *format* is a setting inside Customize, where the
/// other settings live.
struct StudioView: View {
    let run: Run
    /// When opened from a kept poster, its stored recipe seeds the editor and future saves update
    /// it in place instead of creating a duplicate.
    private let existingPoster: SavedPoster?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The single source of truth the whole editor binds to.
    @State private var config: PosterConfig

    @State private var section: StudioSection = .design
    @State private var detent: StudioTrayDetent = .medium

    @State private var showPrints = false
    @State private var showExport = false
    /// Full-screen look at the artwork — tap the preview to open, pinch to inspect.
    @State private var showFullScreenPreview = false
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

    /// Which data element the metric picker is open for.
    @State private var editingSlot: StudioContentTarget?
    /// Which Gallery frame is choosing its photo.
    @State private var photoPickingFrame: FramePickTarget?
    /// A frame waiting for a newly added library photo — Add Photo from the frame picker lands
    /// the new photo straight into that frame.
    @State private var pendingPhotoFrame: Int?

    /// The curated pieces the gallery front door offers, and their renders.
    @State private var picks: [StudioPick] = []
    @State private var pickThumbs: [String: UIImage] = [:]

    /// The navigation spine: the product chooser is the root; picking Map or Gallery pushes the
    /// editor for that product. A saved poster or curated preset skips the chooser — its family
    /// is part of its identity — by seeding the path.
    @State private var path: [PosterFamily]

    init(run: Run, poster: SavedPoster? = nil, preset: PosterConfig? = nil) {
        self.run = run
        self.existingPoster = poster
        if let poster {
            let config = PosterConfig(poster: poster)
            _config = State(initialValue: config)
            _savedPosterID = State(initialValue: poster.id)
            _path = State(initialValue: [config.family])
        } else if let preset {
            // A curated entry (a Studio collection) opens on its authored recipe — the piece
            // already looks finished; the sections refine it.
            _config = State(initialValue: preset)
            _path = State(initialValue: [preset.family])
        } else {
            _config = State(initialValue: PosterConfig.makeDefault(for: run))
            _path = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            productChooser
                .navigationTitle("Studio")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                }
                .navigationDestination(for: PosterFamily.self) { family in
                    editor(for: family)
                }
        }
    }

    // MARK: Editor

    /// One product's editor. The family is decided before arriving here — every control belongs to
    /// this product alone.
    ///
    /// The render tasks and every editor-owned sheet live *here*, on the pushed screen — not on
    /// the navigation root. A pushed destination covers the root and SwiftUI cancels the covered
    /// view's `task(id:)`s, so a root-attached render task goes quiet the moment the editor
    /// appears and no edit ever re-renders the preview.
    private func editor(for family: PosterFamily) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                preview
                StudioEditorTray(detent: $detent, availableHeight: geo.size.height) {
                    VStack(spacing: 0) {
                        StudioSectionPicker(section: $section) { raise(to: .medium) }
                            .padding(.bottom, 2)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                sectionContent
                                orderRow
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                            .padding(.bottom, 28)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(family == .map ? "Map Studio" : "Gallery Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            if config.family != family { config.family = family }
            applyPreviewSection()
        }
        .overlay(alignment: .top) { savedConfirmation }
        // Hand the composed artwork to the shop so the frame mockup shows the user's own piece
        // rather than a placeholder — the whole point of the preview.
        .sheet(isPresented: $showPrints) {
            PrintShopView(subjectTitle: config.title.isEmpty ? run.name : config.title,
                          artwork: rendered,
                          renderRequest: config.request(for: run),
                          creationID: (savedPosterID ?? run.id).uuidString,
                          runID: run.id)
        }
        .sheet(isPresented: $showExport) { StudioExportSheet(request: config.request(for: run)) }
        .sheet(isPresented: $showPhotoPicker) {
            AssetPhotoPicker(selectionLimit: 4) { ids in addPhotos(ids) }
                .ignoresSafeArea()
        }
        .sheet(item: $editingSlot) { target in
            MetricPickerSheet(
                run: run,
                current: currentMetric(for: target),
                allowRemove: { if case .slot = target { return true }; return false }(),
                onPick: { applyMetric($0, to: target) },
                onRemove: {
                    if case .slot(let i) = target, config.dataSlots.indices.contains(i) {
                        config.dataSlots.remove(at: i)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showFullScreenPreview) {
            ArtworkPreviewView(image: rendered)
        }
        .sheet(item: $photoPickingFrame) { target in
            FramePhotoPickerSheet(
                run: run,
                current: effectivePhotoPick(target.frame),
                onPick: { index in assignPhoto(index, toFrame: target.frame) },
                onAddPhoto: {
                    pendingPhotoFrame = target.frame
                    Task { await PhotoLibrary.requestAuthorization(); showPhotoPicker = true }
                }
            )
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

    @ViewBuilder private var sectionContent: some View {
        switch section {
        case .design:
            StudioDesignEditor(run: run, config: $config, onNeedRoom: { raise(to: .medium) })
        case .content:
            StudioContentEditor(
                run: run, config: $config,
                onEditMetric: { editingSlot = $0 },
                onAddPhoto: {
                    Task { await PhotoLibrary.requestAuthorization(); showPhotoPicker = true }
                },
                onPickFramePhoto: { photoPickingFrame = FramePickTarget(frame: $0) }
            )
        case .customize:
            // A sub-editor wants the room a drill-down implies, so opening one raises the tray
            // rather than making the user resize it by hand first.
            StudioCustomizeEditor(run: run, config: $config, onNeedRoom: { raise(to: .expanded) })
        }
    }

    /// Opens the editor on a named section, so CI can photograph Content and Customize — which
    /// are otherwise two taps past the screen a launch lands on. `map-studio@content` reaches
    /// them; inert without the environment variable, like the rest of the harness.
    private func applyPreviewSection() {
        guard let anchor = ProcessInfo.processInfo.environment["ETCH_PREVIEW_SCROLL"],
              let named = StudioSection(rawValue: anchor) else { return }
        section = named
        detent = .expanded
    }

    /// Grows the tray to at least the given stop, never shrinking it — a control asking for room
    /// should not take room away from someone who had already opened the tray wider.
    private func raise(to target: StudioTrayDetent) {
        let order: [StudioTrayDetent] = [.collapsed, .medium, .expanded]
        guard let current = order.firstIndex(of: detent),
              let wanted = order.firstIndex(of: target), wanted > current else { return }
        withAnimation(.interpolatingSpring(stiffness: 320, damping: 30)) { detent = target }
    }

    // MARK: The gallery — finished pieces, not a fork

    /// Studio's front door: the activity already made into four or five finished pieces, each
    /// buyable exactly as shown. Choosing one opens the editor *on* it, seeded, so refinement is
    /// optional rather than required.
    ///
    /// This replaced a product fork ("What are we making?" — Map or Gallery), which asked the
    /// customer to pick an abstraction before showing them anything they might want. Nobody walks
    /// into a gallery and is asked which medium they intend to buy. The curator reads the
    /// activity — a race leads with the marathon print, a summit with the contour journals — and
    /// the two product families are simply present among the picks.
    private var productChooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(run.name)
                        .font(.etch(.title2, weight: .bold))
                    Text("Made into \(picks.count) pieces. Choose one — every detail stays yours to change.")
                        .font(.etch(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                ForEach(picks) { pick in
                    pickCard(pick)
                        .padding(.horizontal, 24)
                }

                Text("Every piece is printed to order on archival paper — from \(PrintProduct.print.entryPrice.replacingOccurrences(of: "From ", with: ""))")
                    .font(.etch(.caption))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                    .padding(.bottom, 24)
            }
            .padding(.top, 14)
        }
        .background(Color(.systemGroupedBackground))
        .task { await renderPicks() }
    }

    private func pickCard(_ pick: StudioPick) -> some View {
        Button {
            config = pick.config
            path.append(pick.config.family)
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(pick.config.groundColor ?? pick.config.edition.ground)
                    if let image = pickThumbs[pick.id] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .transition(.opacity)
                    } else {
                        ProgressView()
                            .tint(.secondary)
                    }
                }
                .aspectRatio(pickAspect(pick), contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.16), radius: 14, y: 7)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.name)
                            .font(.etch(.headline))
                            .foregroundStyle(.primary)
                        Text(pick.line)
                            .font(.etch(.caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 10)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func pickAspect(_ pick: StudioPick) -> CGFloat {
        let s = StudioComposition.nominalSize(pick.config.orientation, pick.config.dataPlacement)
        return s.width / s.height
    }

    /// One render at a time, top to bottom — the reading order — never a thundering herd of
    /// simultaneous map snapshots.
    private func renderPicks() async {
        if picks.isEmpty { picks = StudioCurator.picks(for: run) }
        for pick in picks where pickThumbs[pick.id] == nil {
            if Task.isCancelled { return }
            var recipe = pick.config
            recipe.outputSize = .poster
            let image = await StudioRenderer.image(for: recipe.request(for: run), scale: 0.55)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.2)) { pickThumbs[pick.id] = image }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
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
            Button { showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share or save the image")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showPrints = true } label: { Image(systemName: "bag") }
                .accessibilityLabel("Order a print")
        }
    }

    @ViewBuilder private var savedConfirmation: some View {
        if showSavedConfirmation {
            Label(confirmationText, systemImage: "checkmark.circle.fill")
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.accent, in: .capsule)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
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
                    Button { showFullScreenPreview = true } label: {
                        Image(uiImage: rendered)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View full screen")
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
                                        .font(.etch(.footnote, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text("It needs a recorded route. Try another activity, or a style without a map.")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 26)
                                } else {
                                    ProgressView().tint(config.edition.accent)
                                    Text("Composing…")
                                        .font(.etch(.footnote))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                }
            }
            .padding(.horizontal, 26)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Action bar

    /// Ordering, at the foot of whichever section you are in.
    ///
    /// This was a permanent band of two buttons between the artwork and the controls, and on a
    /// 6.9" phone it cost the poster 56 points it could not spare — the artwork was down to about
    /// two fifths of the screen on the one screen where it is supposed to be the hero. Share and
    /// the shop both live in the toolbar, which is where they were already reachable; this row is
    /// the merchandising one, so it sits inside the tray and scrolls with everything else.
    private var orderRow: some View {
        Button { showPrints = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Order this print")
                        .font(.etch(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Papers, frames and sizes — from \(PrintProduct.print.entryPrice.replacingOccurrences(of: "From ", with: ""))")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: Gallery frame photo picking

    struct FramePickTarget: Identifiable {
        let frame: Int
        var id: Int { frame }
    }

    private func effectivePhotoPick(_ i: Int) -> Int {
        let picks = config.resolvedPhotoPicks
        if i < picks.count, picks[i] >= 0 { return picks[i] }
        return config.resolvedFrames.prefix(i).filter { $0 == .photo }.count
    }

    private func assignPhoto(_ index: Int, toFrame frame: Int) {
        var picks = config.resolvedPhotoPicks
        guard picks.indices.contains(frame) else { return }
        picks[frame] = index
        config.galleryPhotoPicks = picks
    }

    // MARK: Data slots

    private func currentMetric(for target: StudioContentTarget) -> StatMetric {
        switch target {
        case .hero:
            return config.heroMetric
        case .slot(let i):
            return config.dataSlots.indices.contains(i) ? config.dataSlots[i] : .none
        case .add:
            return .none
        }
    }

    /// Applies a metric-picker choice to the targeted element.
    private func applyMetric(_ metric: StatMetric, to target: StudioContentTarget) {
        switch target {
        case .hero:
            config.heroMetric = metric
        case .slot(let i):
            guard config.dataSlots.indices.contains(i) else { return }
            config.dataSlots[i] = metric
        case .add:
            guard config.dataSlots.count < 4 else { return }
            config.dataSlots.append(metric)
        }
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
         "\(config.titleScale)|\(config.locationScale)|\(config.dateScale)|\(config.heroScale)|\(config.statScale)",
         config.textJustification.rawValue,
         config.galleryDesign.rawValue,
         config.resolvedFrames.map(\.rawValue).joined(separator: ","),
         config.resolvedPhotoPicks.map(String.init).joined(separator: ","),
         "\(config.monochrome)", config.orientation.rawValue, config.dataPlacement.rawValue,
         // Text fields use their *debounced* mirrors. Typing a title used to re-render the whole
         // composition — and start a fresh map snapshot — on every keystroke.
         config.font.rawValue, config.dataFont.rawValue, "\(config.showTitle)", debouncedText,
         "\(config.showLocation)", "\(config.showDate)",
         config.heroMetric.rawValue,
         config.dataSlots.map(\.rawValue).joined(separator: ","),
         "\(config.showStatLabels)",
         "\(config.showElevation)", "\(config.showPace)", "\(config.includeWeather)",
         config.outputSize.rawValue,
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
        guard !ids.isEmpty else { pendingPhotoFrame = nil; return }
        var refs = run.photoReferences
        for id in ids where !refs.contains(id) { refs.append(id) }
        if refs.count != run.photoReferences.count {
            run.photoReferences = refs
            try? modelContext.save()
        }
        // A Gallery frame was waiting on this add: land the first picked photo straight into it —
        // add-and-place in one gesture, no second trip through the picker.
        if let frame = pendingPhotoFrame, let first = ids.first,
           let index = refs.firstIndex(of: first) {
            assignPhoto(index, toFrame: frame)
        }
        pendingPhotoFrame = nil
    }
}
