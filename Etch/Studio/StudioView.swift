import SwiftUI
import SwiftData

/// Etch Studio's poster editor.
///
/// Two products — a **Map** poster and a **Gallery** poster — refined through three sections
/// beneath a persistent live preview: **Design** (choose a starting point), **Content** (decide
/// what the poster says), **Personalize** (make the finished piece yours).
///
/// The sections replaced Style · Text · Data · Export, which had become a settings form: every
/// property the composition owned was exposed at the same altitude, on four flat screens, in the
/// renderer's vocabulary rather than the reader's. Nothing was removed in the change — the
/// granular controls moved one level down, behind the decision they belong to, so a first poster
/// is a handful of taps on pictures and the hundredth can still be tuned to the letter.
///
/// Export stopped being a workspace and became what it always was: an action. Share and Order sit
/// permanently under the artwork; the share *format* is a setting inside Personalize, where the
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
    /// True when the last render came back nil, so the canvas can explain itself.
    @State private var renderFailed = false

    /// Which data element the metric picker is open for.
    @State private var editingSlot: StudioContentTarget?
    /// Which Gallery frame is choosing its photo.
    @State private var photoPickingFrame: FramePickTarget?
    /// A frame waiting for a newly added library photo — Add Photo from the frame picker lands
    /// the new photo straight into that frame.
    @State private var pendingPhotoFrame: Int?

    @State private var history = StudioEditHistory<PosterConfig>()
    @State private var savedError = false
    @State private var retryID = 0
    @State private var renderedKey: PreviewKey?

    init(run: Run, poster: SavedPoster? = nil, preset: PosterConfig? = nil) {
        self.run = run
        self.existingPoster = poster
        if let poster {
            let config = PosterConfig(poster: poster)
            _config = State(initialValue: config)
            _savedPosterID = State(initialValue: poster.id)
        } else if let preset {
            // A curated entry (a Studio collection) opens on its authored recipe — the piece
            // already looks finished; the sections refine it.
            _config = State(initialValue: preset)
        } else {
            _config = State(initialValue: PosterConfig.makeDefault(for: run))
        }
    }

    var body: some View {
        NavigationStack {
            editor(for: config.family)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                }
        }
    }

    // MARK: Editor

    /// Direct entry keeps rendering, sheets and edits on the same visible workspace.
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
                                if renderFailed && config.request(for: run).needsMapPanel {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("The map couldn’t load for this print.").font(.headline)
                                        Text("Retry above, or keep the route and photographs with a clean paper background.")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        Button("Use No Map") { config.mapStyle = .none }
                                            .frame(minHeight: 44)
                                    }
                                }
                                sectionContent
                                orderRow
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                            .padding(.bottom, 28)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(family == .map ? "Map Print" : "Gallery Print")
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
        .onChange(of: config) { before, after in history.record(from: before, to: after) }
        .alert("Couldn’t save this print", isPresented: $savedError) {
            Button("Try again") { if savedPosterID == nil { saveAsNew() } else { updateSaved() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your design is still open. Try saving again before leaving Studio.") }

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

    /// Opens the editor on a named section, so CI can photograph Content and Personalize — which
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

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { if let value = history.undo(config) { config = value } } label: {
                Image(systemName: "arrow.uturn.backward")
            }.disabled(!history.canUndo).accessibilityLabel("Undo edit")
            Button { if let value = history.redo(config) { config = value } } label: {
                Image(systemName: "arrow.uturn.forward")
            }.disabled(!history.canRedo).accessibilityLabel("Redo edit")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showExport = true } label: { Label("Share or export", systemImage: "square.and.arrow.up") }
                    .disabled(!previewReady)
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
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Print options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Order") { showPrints = true }
                .fontWeight(.semibold)
                .disabled(!previewReady)
                .accessibilityLabel("Order artwork: choose size and finish")
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

    private var previewReady: Bool { rendered != nil && renderedKey == renderKey && !renderFailed }

    private var preview: some View {
        StudioArtworkStage(image: rendered, aspect: previewAspect,
                           updating: isRendering || (!previewReady && !renderFailed), failed: renderFailed,
                           inspect: { showFullScreenPreview = true }, retry: {
                               EtchMapSnapshotter.retry(config.request(for: run).edition)
                               retryID += 1
                           })
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
        .disabled(!previewReady)
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
        do { try modelContext.save(); confirm("Kept in Studio") }
        catch { savedError = true }
    }

    private func updateSaved() {
        guard let existing = linkedPoster else { saveAsNew(); return }
        config.write(into: existing, run: run)
        do { try modelContext.save(); confirm("Updated") }
        catch { savedError = true }
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
    private struct PreviewKey: Equatable {
        let config: PosterConfig
        let photos: [String]
        let revision: Date
        let retry: Int
    }
    private var renderKey: PreviewKey {
        PreviewKey(config: config, photos: run.photoReferences, revision: run.updatedAt, retry: retryID)
    }

    private func renderPreview() async {
        let key = renderKey
        isRendering = true
        renderFailed = false
        do { try await Task.sleep(for: .milliseconds(220)) }
        catch { return }
        let image = await StudioRenderer.image(for: key.config.request(for: run), scale: 1.5)
        guard !Task.isCancelled, key == renderKey else { return }
        renderedKey = key
        isRendering = false
        renderFailed = image == nil
        if let image { rendered = image }
    }

    /// Appends newly picked library photos to this run (de-duplicated), which persists them on the
    /// run so they show both here and in the run's activity details, then re-renders the preview.
    private func addPhotos(_ ids: [String]) {
        guard !ids.isEmpty else { pendingPhotoFrame = nil; return }
        run.attachPhotos(ids, manually: true)
        let refs = run.photoReferences
        try? modelContext.save()
        // A Gallery frame was waiting on this add: land the first picked photo straight into it —
        // add-and-place in one gesture, no second trip through the picker.
        if let frame = pendingPhotoFrame, let first = ids.first,
           let index = refs.firstIndex(of: first) {
            assignPhoto(index, toFrame: frame)
        }
        pendingPhotoFrame = nil
    }
}
