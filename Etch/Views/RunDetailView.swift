import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Details for a single run, shown as a sheet when a route is tapped.
struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoSelection: PhotoSelection?
    @State private var draggingPhoto: String?
    @State private var isFindingPhotos = false
    @State private var showStudio = false
    @State private var showRename = false
    @State private var draftName = ""
    @State private var showDeleteConfirm = false

    private struct PhotoSelection: Identifiable { let id: String }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if run.isIndoor {
                        indoorPreview
                    } else {
                        RunPreviewMap(run: run, interactive: true)
                            .frame(height: 240)
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    }

                    metrics

                    raceToggle

                    if run.hasRoute { studioButton }

                    photosSection

                    sourceFooter

                    if run.isStravaLinked {
                        openInStrava
                    }

                    deleteButton
                }
                .padding(20)
            }
            .confirmationDialog("Delete this run? This can't be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Run", role: .destructive) { deleteRun() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showStudio) {
                StudioView(run: run)
            }
            .alert("Rename Run", isPresented: $showRename) {
                TextField("Run name", text: $draftName)
                Button("Save") { rename() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give this run your own title.")
            }
            .task { await autoMatchPhotosIfNeeded() }
            .onChange(of: pickerItems) { _, items in addPicked(items) }
            .fullScreenCover(item: $photoSelection) { selection in
                RunPhotoViewer(
                    identifiers: run.photoReferences,
                    selection: selection.id,
                    onDelete: deletePhoto
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            run.isFavorite.toggle()
                        } label: {
                            Image(systemName: run.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(run.isFavorite ? Theme.accent : .secondary)
                        }
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Stands in for the map on treadmill / indoor runs, which have no route to show — a clean
    /// indoor card instead of a blank ocean map.
    private var indoorPreview: some View {
        ZStack {
            LinearGradient(colors: [Theme.Palette.stone, Theme.Palette.mist],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image(systemName: IndoorGlyph.symbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                Text("Indoor Run")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.7))
                Text("No route recorded")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.45))
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    /// Full-width title block at the top of the sheet. Lives in the scroll content (not the
    /// nav bar) so the run name and place have room to be read instead of truncating to
    /// "Ni…/Brec…" in the cramped leading toolbar slot.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(run.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    draftName = run.name
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            if !run.placeLabel.isEmpty {
                Text(run.placeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != run.name else { return }
        run.name = trimmed
        run.nameIsCustom = true
        run.updatedAt = Date()
        try? context.save()
    }

    /// Destructive delete at the foot of the sheet. Removes the run from Etch entirely — it will
    /// re-import on the next sync if it still exists in a connected source (Apple Health / Strava),
    /// but hand-added races and imported files are gone for good.
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete Run", systemImage: "trash")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func deleteRun() {
        // Dismiss first so the sheet isn't rendering a deleted object, then remove and save.
        dismiss()
        context.delete(run)
        try? context.save()
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metric("Distance", Format.distance(run.distance), "point.topleft.down.to.point.bottomright.curvepath")
                metric("Time", Format.duration(run.movingTime), "stopwatch")
            }
            HStack(spacing: 12) {
                metric("Pace", Format.pace(secondsPerKm: run.paceSecondsPerKm), "speedometer")
                metric("Elevation Gain", Format.elevation(run.elevationGain), "mountain.2")
            }
            HStack(spacing: 12) {
                metric("Date", Format.date(run.startDate), "calendar")
                metric("Type", cleanSportType, "figure.run")
            }
            // Physiological metrics (Energy, Avg HR, Cadence), two per row, as available.
            ForEach(Array(stride(from: 0, to: physioMetrics.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    let a = physioMetrics[i]
                    metric(a.label, a.value, a.icon)
                    if i + 1 < physioMetrics.count {
                        let b = physioMetrics[i + 1]
                        metric(b.label, b.value, b.icon)
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            // Weather, when the run captured it.
            if let weather = run.weatherLine() {
                metric("Weather", weather, "cloud.sun")
            }
        }
    }

    /// The available physiological metrics, ordered so heart rate sits next to energy.
    private var physioMetrics: [(label: String, value: String, icon: String)] {
        var items: [(label: String, value: String, icon: String)] = []
        if let energy = run.activeEnergy, energy > 0 {
            items.append((label: "Energy", value: "\(Int(energy)) kcal", icon: "flame"))
        }
        if let hr = run.averageHeartRate, hr > 0 {
            items.append((label: "Avg HR", value: "\(Int(hr)) bpm", icon: "heart"))
        }
        if let cadence = run.averageCadence, cadence > 0 {
            items.append((label: "Cadence", value: "\(Int(cadence)) spm", icon: "figure.run"))
        }
        return items
    }

    private var cleanSportType: String {
        run.sportType.replacingOccurrences(of: "Run", with: " Run").trimmingCharacters(in: .whitespaces)
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    private var raceToggle: some View {
        Toggle(isOn: raceBinding) {
            Label("Race", systemImage: "flag.checkered")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var raceBinding: Binding<Bool> {
        Binding(
            get: { run.isRace },
            set: { newValue in
                run.isRace = newValue
                run.raceIsCustom = true
                run.updatedAt = Date()
                try? context.save()
            }
        )
    }

    private var studioButton: some View {
        Button { showStudio = true } label: {
            Label("Create in Etch Studio", systemImage: "photo.artframe")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Photos").font(.system(.headline, design: .rounded))
                Spacer()
                if isFindingPhotos { ProgressView().controlSize(.small) }
            }

            if run.photoReferences.isEmpty {
                HStack(spacing: 10) {
                    addPhotosButton {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Button {
                        Task { await findPhotos() }
                    } label: {
                        Label("Find from Library", systemImage: "sparkles")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isFindingPhotos)
                }
                Text("Etch can find photos you took during this run.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(run.photoReferences, id: \.self) { identifier in
                            RunPhotoThumbnail(identifier: identifier)
                                .overlay(alignment: .topLeading) {
                                    if identifier == run.photoReferences.first {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(5)
                                            .background(Theme.accent, in: .circle)
                                            .padding(6)
                                    }
                                }
                                .opacity(draggingPhoto == identifier ? 0.5 : 1)
                                .onTapGesture { photoSelection = PhotoSelection(id: identifier) }
                                .onDrag {
                                    draggingPhoto = identifier
                                    return NSItemProvider(object: identifier as NSString)
                                }
                                .onDrop(of: [UTType.text], delegate: PhotoReorderDropDelegate(
                                    item: identifier,
                                    photos: Binding(
                                        get: { run.photoReferences },
                                        set: { run.photoReferences = $0; run.updatedAt = Date() }
                                    ),
                                    dragging: $draggingPhoto
                                ))
                                .contextMenu {
                                    if identifier != run.photoReferences.first {
                                        Button {
                                            setDefaultPhoto(identifier)
                                        } label: {
                                            Label("Set as Default", systemImage: "star")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        deletePhoto(identifier)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                        addPhotosButton {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15))
                                Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                            }
                            .frame(width: 84, height: 84)
                        }
                    }
                }
                if run.photoReferences.count > 1 {
                    Text("Drag to reorder — the first photo is the cover.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// A `PhotosPicker` wrapping the given label. Uses `.shared()` so we get asset identifiers.
    private func addPhotosButton<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        ) { label() }
    }

    private func addIdentifiers(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var refs = run.photoReferences
        for id in ids where !refs.contains(id) { refs.append(id) }
        guard refs.count != run.photoReferences.count else { return }
        run.photoReferences = refs
        run.updatedAt = Date()
        try? context.save()
    }

    private func addPicked(_ items: [PhotosPickerItem]) {
        addIdentifiers(items.compactMap(\.itemIdentifier))
        pickerItems = []
    }

    private func deletePhoto(_ identifier: String) {
        run.photoReferences.removeAll { $0 == identifier }
        run.updatedAt = Date()
        try? context.save()
    }

    /// Makes a photo the run's default (cover) by moving it to the front — this is the photo
    /// used on tiles, the timeline, and the Studio "Memory" edition.
    private func setDefaultPhoto(_ identifier: String) {
        guard let index = run.photoReferences.firstIndex(of: identifier), index != 0 else { return }
        var refs = run.photoReferences
        refs.remove(at: index)
        refs.insert(identifier, at: 0)
        run.photoReferences = refs
        run.updatedAt = Date()
        try? context.save()
    }

    private var photoScanKey: String { "photoScan-\(run.id.uuidString)" }

    /// On first open, if the library is already authorised, quietly pull in matching photos.
    private func autoMatchPhotosIfNeeded() async {
        guard PhotoLibrary.isAuthorized,
              !UserDefaults.standard.bool(forKey: photoScanKey) else { return }
        addIdentifiers(PhotoLibrary.matchingIdentifiers(for: run))
        UserDefaults.standard.set(true, forKey: photoScanKey)
    }

    /// Explicit "Find from Library": request access if needed, then match.
    private func findPhotos() async {
        isFindingPhotos = true
        defer { isFindingPhotos = false }
        guard await PhotoLibrary.requestAuthorization() else { return }
        addIdentifiers(PhotoLibrary.matchingIdentifiers(for: run))
        UserDefaults.standard.set(true, forKey: photoScanKey)
    }

    /// Subtle provenance line — where the workout originated. Deliberately quiet.
    private var sourceFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: run.displaySource.symbol)
            Text("Recorded with \(run.displaySource.label)")
            if let gear = run.gear, !gear.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Image(systemName: "shoe")
                Text(gear)
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }

    private var openInStrava: some View {
        Button {
            guard let id = run.stravaActivityID else { return }
            let appURL = URL(string: "strava://activities/\(id)")!
            let webURL = URL(string: "https://www.strava.com/activities/\(id)")!
            openURL(appURL) { accepted in
                if !accepted { openURL(webURL) }
            }
        } label: {
            Label("Open in Strava", systemImage: "arrow.up.right.square")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Reorders the run's photos as one is dragged over another. Moving reorders `photos`, whose
/// first element is the cover.
private struct PhotoReorderDropDelegate: DropDelegate {
    let item: String
    @Binding var photos: [String]
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = photos.firstIndex(of: dragging),
              let to = photos.firstIndex(of: item) else { return }
        if photos[to] != dragging {
            withAnimation {
                photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
