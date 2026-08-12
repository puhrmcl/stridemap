import SwiftUI
import PhotosUI

/// Details for a single run, shown as a sheet when a route is tapped.
struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoSelection: PhotoSelection?
    @State private var isFindingPhotos = false
    @State private var showPoster = false
    @State private var showRename = false
    @State private var draftName = ""

    private struct PhotoSelection: Identifiable { let id: String }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    RunPreviewMap(run: run, interactive: true)
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))

                    metrics

                    if run.hasRoute { posterButton }

                    photosSection

                    sourceFooter

                    if run.isStravaLinked {
                        openInStrava
                    }
                }
                .padding(20)
            }
            .sheet(isPresented: $showPoster) {
                RunPosterExportView(run: run)
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

    private var metrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metric("Distance", Format.distance(run.distance), "point.topleft.down.to.point.bottomright.curvepath")
                metric("Time", Format.duration(run.movingTime), "stopwatch")
            }
            HStack(spacing: 12) {
                metric("Pace", Format.pace(secondsPerKm: run.paceSecondsPerKm), "speedometer")
                metric("Elevation", Format.elevation(run.elevationGain), "mountain.2")
            }
            HStack(spacing: 12) {
                metric("Date", Format.date(run.startDate), "calendar")
                if let hr = run.averageHeartRate, hr > 0 {
                    metric("Avg HR", "\(Int(hr)) bpm", "heart")
                } else {
                    metric("Type", cleanSportType, "figure.run")
                }
            }
            // Optional rich metrics only appear when the source provided them.
            if hasSecondaryMetrics {
                HStack(spacing: 12) {
                    if let energy = run.activeEnergy, energy > 0 {
                        metric("Energy", "\(Int(energy)) kcal", "flame")
                    }
                    if let cadence = run.averageCadence, cadence > 0 {
                        metric("Cadence", "\(Int(cadence)) spm", "figure.run")
                    }
                }
            }
        }
    }

    private var hasSecondaryMetrics: Bool {
        (run.activeEnergy ?? 0) > 0 || (run.averageCadence ?? 0) > 0
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

    private var posterButton: some View {
        Button { showPoster = true } label: {
            Label("Create Route Poster", systemImage: "photo.artframe")
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
                                .onTapGesture { photoSelection = PhotoSelection(id: identifier) }
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
