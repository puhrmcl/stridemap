import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import MapKit

/// Details for a single run, shown as a sheet when a route is tapped.
struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query private var allRuns: [Run]

    /// Statistics across peers of the same activity type, so records are compared like-for-like
    /// (a hike isn't a milestone because it beats a run).
    private var peerStats: RunStatistics {
        RunStatistics(allRuns.filter { $0.activityType == run.activityType })
    }

    /// Whether this run is a milestone — a record or superlative among activities of its type, so it
    /// gets the same gold-trophy treatment as its map pin.
    private var isMilestone: Bool { peerStats.milestoneRunIDs.contains(run.id) }

    /// What, specifically, makes this run a milestone — shown on the badge.
    private var milestoneDescriptors: [String] { peerStats.milestoneLabels(for: run) }

    /// Elevation is the headline metric for hikes and rides, so their detail leads with a route
    /// elevation profile. Runs/walks keep the elevation-gain figure in the metric grid.
    private var showsElevationProfile: Bool {
        run.hasRoute && !run.isIndoor && (run.activityType == .hike || run.activityType == .ride)
    }

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoSelection: PhotoSelection?
    @State private var draggingPhoto: String?
    @State private var isFindingPhotos = false
    @State private var showStudio = false
    /// The recipe Studio opens on when entered from the moment card; nil = the plain default.
    @State private var studioPreset: PosterConfig?
    /// Local mirror of the persisted moment dismissal, so the card animates out immediately.
    @State private var momentDismissed = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showLocationPicker = false
    /// Presents the route-file picker from the "No map data" card.
    @State private var showRouteImporter = false
    /// Notes start folded; expand to read or edit them.
    @State private var notesExpanded = false
    /// Local draft of the notes field — committed to the model when typing pauses, not per keystroke.
    @State private var notesDraft = ""
    /// A rendered PNG of the run's route over a map, prepared in the background so "Share Activity"
    /// can attach it alongside the text summary. Nil until ready (or for a route-less run).
    @State private var routeShareImage: UIImage?

    private struct PhotoSelection: Identifiable { let id: String }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if run.hasRoute {
                        RunPreviewMap(run: run, interactive: true)
                            .frame(height: 240)
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    } else if run.startCoordinate != nil {
                        placedLocationMap
                    } else {
                        unmappedCard
                    }

                    // Apple Look Around (street-level imagery) at the run's start, where covered.
                    if let coordinate = run.startCoordinate {
                        LookAroundButton(coordinate: coordinate)
                    }

                    if showsElevationProfile {
                        ElevationProfileView(run: run)
                    }

                    metrics

                    // The moment of meaning: a race or a bucket-list trail earns a quiet,
                    // dismissible invitation into its Studio collection — celebration, not upsell.
                    if let moment = collectionMoment { momentCard(moment) }

                    raceToggle

                    notesSection

                    if run.isRace { shareRaceButton }

                    // The plain Studio button yields to the moment card when one is showing — one
                    // door into Studio per page, never two competing ones.
                    if run.hasRoute && collectionMoment == nil { studioButton }

                    photosSection

                    sourceFooter

                    if run.isStravaLinked {
                        openInStrava
                    }

                    VStack(spacing: 4) {
                        hideButton
                        deleteButton
                        Text("Hiding keeps an activity in Etch but off your map, timeline, and totals — handy for a synced activity you don't want counted. Manage hidden activities in Settings.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .confirmationDialog("Delete this activity? This can't be undone.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Run", role: .destructive) { deleteRun() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showStudio) {
                StudioView(run: run, preset: studioPreset)
            }
            .sheet(isPresented: $showEdit) {
                EditRunSheet(run: run)
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerView(title: run.name, start: run.startCoordinate ?? suggestedLocation) { coordinate in
                    run.setManualLocation(coordinate)
                    try? context.save()
                }
            }
            .task { await autoMatchPhotosIfNeeded() }
            .onChange(of: pickerItems) { _, items in addPicked(items) }
            .fullScreenCover(item: $photoSelection) { selection in
                RunPhotoViewer(
                    identifiers: run.photoReferences,
                    selection: selection.id,
                    isCoverPhoto: { $0 == run.photoReferences.first },
                    onDelete: deletePhoto,
                    onSetCover: setDefaultPhoto
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { showEdit = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Menu {
                            Button {
                                // Share the text summary, a PNG of the map (the route when there is
                                // one, otherwise the place), and an Apple Maps link the recipient can
                                // tap to open the location — all in one share.
                                //
                                // The PNG is rendered here if the background pass hasn't finished —
                                // it used to be skipped silently when Share was tapped inside the
                                // first couple of seconds, so the one attachment the share is really
                                // about arrived only sometimes.
                                Task {
                                    if routeShareImage == nil,
                                       run.hasMapLocation || run.coordinates.count > 1 {
                                        routeShareImage = await PosterMap.sharePanel(
                                            for: run, size: CGSize(width: 1000, height: 1000))
                                    }
                                    var items: [Any] = [run.shareSummary]
                                    if let routeShareImage { items.append(routeShareImage) }
                                    if let url = run.appleMapsURL { items.append(url) }
                                    AppShare.present(items)
                                }
                            } label: {
                                Label("Share Activity", systemImage: "square.and.arrow.up")
                            }
                            Button { studioPreset = nil; showStudio = true } label: {
                                Label("Create in Studio", systemImage: "photo.artframe")
                            }
                            if run.hasMapLocation {
                                Button { run.openInAppleMaps() } label: {
                                    Label("Open in Maps", systemImage: "map")
                                }
                                Button { run.openInAppleMaps(directions: true) } label: {
                                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("More")

                        Button {
                            run.isFavorite.toggle()
                            // Bumped because surfaces that cache their derived lists key off it:
                            // the Favorites filter is one of them, so a heart that did not touch
                            // this would leave the map and Timeline showing the old set.
                            run.updatedAt = Date()
                            try? context.save()
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
        // Render the map PNG in the background so it's ready to attach when the user shares — the
        // route over a map when there's a track, otherwise a map of the place it happened. Only an
        // activity with no location at all (an unplaced indoor run) shares without a picture.
        .task(id: run.id) {
            guard routeShareImage == nil, run.hasMapLocation || run.coordinates.count > 1 else { return }
            routeShareImage = await PosterMap.sharePanel(for: run, size: CGSize(width: 1000, height: 1000))
        }
    }

    /// Stands in for the map on a route-less run (indoor/treadmill, or a GPS-less import) that
    /// hasn't been placed yet — offering both recoveries: drop it onto the map by hand, or
    /// attach the route from a file the runner has (e.g. a Strava GPX export).
    private var unmappedCard: some View {
        ZStack {
            LinearGradient(colors: [Theme.Palette.stone, Theme.Palette.mist],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 10) {
                Image(systemName: run.isIndoor ? IndoorGlyph.symbol : "mappin.slash")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                Text(run.isIndoor ? "Indoor Run" : "No map data")
                    .font(.etch(.headline))
                    .foregroundStyle(Theme.Palette.ink.opacity(0.7))
                unmappedAction("Add location on map", symbol: "mappin.and.ellipse") {
                    showLocationPicker = true
                }
                .padding(.top, 2)
                if !run.isIndoor {
                    unmappedAction("Import route file", symbol: "square.and.arrow.down") {
                        showRouteImporter = true
                    }
                }
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .routeFileAttacher(run: run, isPresented: $showRouteImporter)
    }

    /// Both capsules are the same width.
    ///
    /// Sized to their own text, "Add location on map" and "Import route file" came out visibly
    /// different lengths and stacked into a ragged pair. They are two ways of answering one
    /// question — where was this? — and equal weight is the honest presentation of a choice
    /// between equals. A fixed width also stops the pair reflowing when the labels are localised.
    private static let unmappedActionWidth: CGFloat = 230

    private func unmappedAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.vertical, 8)
                .frame(width: Self.unmappedActionWidth)
                .background(.regularMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// A hand-placed run's location: a small map with a treadmill pin, tappable to move it.
    private var placedLocationMap: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: run.startCoordinate ?? .init(),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )), interactionModes: []) {
                if let coordinate = run.startCoordinate {
                    Annotation("", coordinate: coordinate) {
                        Image(systemName: run.isIndoor ? IndoorGlyph.symbol : "mappin")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent, in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3, y: 1)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .allowsHitTesting(false)

            Label("Move", systemImage: "mappin.and.ellipse")
                .font(.etch(.caption, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(10)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .contentShape(.rect)
        .onTapGesture { showLocationPicker = true }
    }

    /// The most recent located run to seed the pin near — the user's likely gym/home.
    private var suggestedLocation: CLLocationCoordinate2D? {
        allRuns
            .filter { $0.id != run.id && $0.startCoordinate != nil }
            .min { abs($0.startDate.timeIntervalSince(run.startDate)) < abs($1.startDate.timeIntervalSince(run.startDate)) }?
            .startCoordinate
    }

    /// Full-width title block at the top of the sheet. Lives in the scroll content (not the
    /// nav bar) so the run name and place have room to be read instead of truncating to
    /// "Ni…/Brec…" in the cramped leading toolbar slot.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isMilestone { milestoneBadge }
            Text(run.name)
                .font(.etch(.title2, weight: .bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !run.placeLabel.isEmpty {
                Text(run.placeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A gold badge mirroring the map's trophy pin, naming *which* records this run holds —
    /// "Furthest run", "Fastest pace", "5K best" — so the milestone means something concrete.
    private var milestoneBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("MILESTONE")
                    .font(.etch(size: 12, weight: .bold))
                    .tracking(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.Palette.brass, in: .capsule)

            if !milestoneDescriptors.isEmpty {
                Text(milestoneDescriptors.joined(separator: " · "))
                    .font(.etch(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.Palette.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Hide keeps the run in the store but out of every browsing surface — reversible, unlike
    /// delete, and it stops a synced run from simply re-importing. Hiding dismisses the sheet.
    private var hideButton: some View {
        Button {
            run.isHidden.toggle()
            run.updatedAt = Date()
            try? context.save()
            if run.isHidden { dismiss() }
        } label: {
            Label(run.isHidden ? "Unhide Run" : "Hide Run",
                  systemImage: run.isHidden ? "eye" : "eye.slash")
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    /// Destructive delete at the foot of the sheet. Removes the run from Etch entirely — it will
    /// re-import on the next sync if it still exists in a connected source (Apple Health / Strava),
    /// but hand-added races and imported files are gone for good.
    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete Run", systemImage: "trash")
                .font(.etch(.subheadline, weight: .semibold))
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
            // Physiological metrics (Calories, Avg HR, Cadence), two per row, as available.
            // An odd last tile spans the whole row — a lone card beside an empty hole read as
            // something missing, and a workout without heart rate is not missing anything.
            ForEach(Array(stride(from: 0, to: physioMetrics.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    let a = physioMetrics[i]
                    metric(a.label, a.value, a.icon)
                    if i + 1 < physioMetrics.count {
                        let b = physioMetrics[i + 1]
                        metric(b.label, b.value, b.icon)
                    }
                }
            }
            // Weather — the recorded or backfilled conditions, two per row like the physio
            // metrics. The Strava-style full panel: conditions, feels-like, humidity, wind.
            ForEach(Array(stride(from: 0, to: weatherMetrics.count, by: 2)), id: \.self) { i in
                HStack(spacing: 12) {
                    let a = weatherMetrics[i]
                    metric(a.label, a.value, a.icon)
                    if i + 1 < weatherMetrics.count {
                        let b = weatherMetrics[i + 1]
                        metric(b.label, b.value, b.icon)
                    }
                }
            }
        }
        // Backfill this run's weather on first view if the sweep hasn't reached it yet — the
        // panel fills in as soon as WeatherKit answers.
        .task {
            guard !run.weatherBackfilled else { return }
            if await WeatherBackfill.backfill(run) { try? context.save() }
        }
    }

    /// The available weather metrics, conditions first.
    private var weatherMetrics: [(label: String, value: String, icon: String)] {
        var items: [(label: String, value: String, icon: String)] = []
        if let line = run.weatherLine() {
            items.append(("Weather", line, run.weatherCondition?.symbol ?? "cloud.sun"))
        }
        if let feels = run.weatherFeelsLikeC {
            items.append(("Feels Like", WeatherFormat.temperature(celsius: feels), "thermometer.medium"))
        }
        if let humidity = run.weatherHumidity {
            items.append(("Humidity", WeatherFormat.humidity(humidity), "humidity"))
        }
        if let speed = run.weatherWindSpeedMS {
            items.append(("Wind", WeatherFormat.wind(speedMS: speed, directionDeg: run.weatherWindDirectionDeg), "wind"))
        }
        return items
    }

    /// The available physiological metrics, ordered so heart rate sits next to energy.
    private var physioMetrics: [(label: String, value: String, icon: String)] {
        var items: [(label: String, value: String, icon: String)] = []
        // "Calories", not "Energy" — the word people actually use, and the number is kcal anyway.
        if let energy = run.activeEnergy, energy > 0 {
            items.append((label: "Calories", value: "\(Int(energy)) kcal", icon: "flame"))
        }
        if let hr = run.averageHeartRate, hr > 0 {
            items.append((label: "Avg HR", value: "\(Int(hr)) bpm", icon: "heart"))
        }
        if let cadence = run.averageCadence, cadence > 0 {
            items.append((label: "Cadence", value: "\(Int(cadence)) spm", icon: "figure.run"))
        }
        return items
    }

    /// What the Type card says.
    ///
    /// It used to print `sportType` alone, which is a free-text label from whichever source wrote
    /// the activity and is not what anything in the app acts on. When the two disagreed the card
    /// stated the wrong one, silently: a summit added from the library read "Hike" here while the
    /// records, the totals and every scope filed it as a run, so the one screen that could have
    /// revealed the mismatch was the screen that hid it.
    ///
    /// The classification wins. The provider's wording is kept only when it agrees and says more
    /// — "Trail Run" over a plain "Run" — so the extra detail is not lost to the correction.
    private var cleanSportType: String {
        let classified = run.activityType.detailLabel
        let provider = run.sportType
            .replacingOccurrences(of: "Run", with: " Run")
            .trimmingCharacters(in: .whitespaces)
        guard ActivityType.parse(run.sportType) == run.activityType, !provider.isEmpty else {
            return classified
        }
        return provider
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.etch(.title3, weight: .bold))
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
                .font(.etch(.subheadline, weight: .medium))
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

    /// A foldable Notes section: collapsed it shows a one-line preview (or a prompt to add one);
    /// expanded it reveals an editable field. Notes come from Strava/TCX imports or your own edits.
    ///
    /// Edits land in a local draft and commit ~1s after typing stops (and when leaving the page) —
    /// the field used to write to the model and `context.save()` on every keystroke, which also
    /// bumped `updatedAt` per character and invalidated every cache keyed on it.
    private var notesSection: some View {
        DisclosureGroup(isExpanded: $notesExpanded) {
            TextField("Add a note…", text: $notesDraft, axis: .vertical)
                .lineLimit(3...10)
                .font(.etch(.subheadline))
                .textFieldStyle(.plain)
                .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.etch(.subheadline, weight: .medium))
                Spacer(minLength: 8)
                if !notesExpanded {
                    Text((run.notes?.isEmpty == false) ? run.notes! : "Add")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .task(id: run.id) { notesDraft = run.notes ?? "" }
        .task(id: notesDraft) {
            guard notesDraft != (run.notes ?? "") else { return }
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            commitNotes()
        }
        .onDisappear { commitNotes() }
    }

    /// Writes the notes draft to the model, once, if it actually changed.
    private func commitNotes() {
        guard notesDraft != (run.notes ?? "") else { return }
        let trimmed = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        run.notes = trimmed.isEmpty ? nil : notesDraft
        run.updatedAt = Date()
        try? context.save()
    }

    /// Share a race's key details as a tidy text summary (times, pace, place) via the system share
    /// sheet — offered on runs marked as a race.
    private var shareRaceButton: some View {
        ShareLink(item: raceShareText) {
            Label("Share Race Details", systemImage: "square.and.arrow.up")
                .font(.etch(.headline))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var raceShareText: String {
        var lines: [String] = ["🏁 \(run.name)", Format.dateTime(run.startDate)]
        if !run.placeLabel.isEmpty { lines.append(run.placeLabel) }
        lines.append("")
        lines.append("Distance  \(Format.distance(run.distance, decimals: 2))")
        lines.append("Time  \(Format.duration(run.movingTime))")
        if run.distance > 0 {
            let secondsPerKm = Double(run.movingTime) / (run.distance / 1000)
            lines.append("Pace  \(Format.pace(secondsPerKm: secondsPerKm))")
        }
        if run.elevationGain > 0 {
            lines.append("Elevation  \(Format.elevationGain(run.elevationGain))")
        }
        lines.append("")
        lines.append("Tracked with Etch")
        return lines.joined(separator: "\n")
    }

    // MARK: The moment card — "Make it permanent."

    /// What this activity qualifies for: a finisher piece (any race) or a summit piece (a route
    /// matched to a curated bucket-list trail). Nil once dismissed for this run.
    private enum CollectionMoment {
        case course(title: String)
        case summit(StudioCollections.IconicSummit)
    }

    private static let momentDismissedKey = "collectionMomentDismissed"

    private var collectionMoment: CollectionMoment? {
        guard !momentDismissed else { return nil }
        let dismissed = UserDefaults.standard.stringArray(forKey: Self.momentDismissedKey) ?? []
        guard !dismissed.contains(run.id.uuidString) else { return nil }
        if run.isRace { return .course(title: StudioCollections.artworkTitle(for: run)) }
        if run.hasRoute, let summit = StudioCollections.iconicSummit(for: run) {
            return .summit(summit)
        }
        return nil
    }

    private func momentCard(_ moment: CollectionMoment) -> some View {
        let eyebrow: String
        let line: String
        let accent: Color
        let preset: PosterConfig
        switch moment {
        case .course(let title):
            eyebrow = "THE COURSE COLLECTION"
            line = "\(title), as a finisher piece."
            accent = Theme.Palette.blueBright
            preset = StudioCollections.coursePreset(for: run)
        case .summit(let summit):
            eyebrow = "THE SUMMIT COLLECTION"
            line = "\(summit.name), in gold contour on ink."
            accent = Theme.Palette.brass
            preset = StudioCollections.summitPreset(for: run, iconic: summit)
        }

        return Button {
            studioPreset = preset
            showStudio = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow)
                        .font(.etch(size: 11, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(accent)
                    Text("Make it permanent.")
                        .font(.etch(.headline))
                        .foregroundStyle(Theme.Palette.bone)
                    Text(line)
                        .font(.etch(.subheadline))
                        .foregroundStyle(Theme.Palette.bone.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.Palette.bone.opacity(0.35))
                    .padding(.top, 22)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.ink, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.3), lineWidth: 0.75))
            // A quiet dismiss that remembers — offered once, never nagging.
            .overlay(alignment: .topTrailing) {
                Button {
                    var dismissed = UserDefaults.standard.stringArray(forKey: Self.momentDismissedKey) ?? []
                    dismissed.append(run.id.uuidString)
                    UserDefaults.standard.set(dismissed, forKey: Self.momentDismissedKey)
                    withAnimation(Theme.gentle) { momentDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.bone.opacity(0.4))
                        .frame(width: 34, height: 34)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }

    private var studioButton: some View {
        Button { studioPreset = nil; showStudio = true } label: {
            Label("Create in Etch Studio", systemImage: "photo.artframe")
                .font(.etch(.headline))
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
                Text("Photos").font(.etch(.headline))
                Spacer()
                if isFindingPhotos { ProgressView().controlSize(.small) }
            }

            if run.photoReferences.isEmpty {
                HStack(spacing: 10) {
                    addPhotosButton {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                            .font(.etch(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Button {
                        Task { await findPhotos() }
                    } label: {
                        Label("Find from Library", systemImage: "sparkles")
                            .font(.etch(.subheadline, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isFindingPhotos)
                }
                Text("Etch can find photos you took during this activity.")
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
                                            .accessibilityLabel("Cover photo")
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
                                            Label("Make Cover Photo", systemImage: "star")
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
                                RoundedRectangle(cornerRadius: 12).fill(Theme.Brand.inkWell)
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

    /// Makes a photo the run's cover by moving it to the front of `photoReferences`.
    ///
    /// First-is-cover is the whole mechanism, and it is why this is a reorder rather than a flag:
    /// eight places already read `photoReferences.first` — the route thumbnail, the month tile,
    /// the Photo Wall, a book's race page, the Studio storefront — and every one of them picks up
    /// a new cover without knowing the concept exists.
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
                .font(.etch(.headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Edit the core facts of an activity — its title, when it happened, and what kind it is.
/// Presented from the run-detail "Edit" button. Changes are staged locally and only committed
/// on Save, so Cancel discards. Correcting the type is handy when an import (e.g. an AllTrails
/// GPX with no `<type>`) came in as the wrong kind.
private struct EditRunSheet: View {
    @Bindable var run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var title: String
    @State private var date: Date
    @State private var type: ActivityType
    @State private var bib: String
    @State private var finishPlace: String

    // Route attachment: add or replace this activity's map from a GPX/TCX/FIT file. The whole
    // flow lives in RouteFileAttacher, shared with the detail page's "No map data" card.
    @State private var routePickerPresented = false
    @State private var routeAttached = false

    init(run: Run) {
        self.run = run
        _title = State(initialValue: run.name)
        _date = State(initialValue: run.startDate)
        _type = State(initialValue: run.activityType)
        _bib = State(initialValue: run.bibNumber)
        _finishPlace = State(initialValue: run.finishPlace)
    }

    /// Run/Hike/Ride/Walk, plus the current type if it's something else (Ski, Swim, …) so the
    /// picker always shows a valid selection.
    private var typeChoices: [ActivityType] {
        var base: [ActivityType] = [.run, .hike, .ride, .walk]
        if !base.contains(type) { base.append(type) }
        return base
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Date") {
                    DatePicker("Date & time", selection: $date,
                               displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Picker(selection: $type) {
                        ForEach(typeChoices, id: \.self) { t in
                            Label(t.detailLabel, systemImage: t.detailIcon).tag(t)
                        }
                    } label: {
                        Label("Activity", systemImage: type.detailIcon)
                    }
                } header: {
                    Text("Activity type")
                }
                Section {
                    HStack {
                        Text("Bib")
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        TextField("e.g. 9478", text: $bib)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Finish")
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        TextField("e.g. 127, or 3rd F35-39", text: $finishPlace)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Race details")
                } footer: {
                    Text("Both appear as Studio poster data points — the way race prints carry the runner's number and finish. A bare number shows as an ordinal (127 → 127th).")
                }
                Section {
                    Button {
                        routePickerPresented = true
                    } label: {
                        HStack {
                            Label(run.hasRoute ? "Replace Route from File" : "Add Route from File",
                                  systemImage: "map")
                            Spacer()
                            if routeAttached {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    Text("Route")
                } footer: {
                    Text("Attach a GPX, TCX, or FIT file — for example, exported from Strava — to add or replace this activity's map. Recorded stats stay unchanged.")
                }
            }
            .routeFileAttacher(run: run, isPresented: $routePickerPresented) {
                routeAttached = true
            }
            .navigationTitle("Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func save() {
        if trimmedTitle != run.name {
            run.name = trimmedTitle
            run.nameIsCustom = true
        }
        run.startDate = date
        run.activityType = type
        // Keep the free-text label in step with the type. They are two fields saying one thing —
        // `activityType` is what the app scopes and ranks by, `sportType` is what gets displayed
        // — so writing one without the other leaves a card that reads "Run" on an activity the
        // app has filed under hikes. Only rewritten when it no longer describes the type, so a
        // provider's more specific wording ("Trail Run", "Virtual Run") survives an unrelated edit.
        if ActivityType.parse(run.sportType) != type {
            run.sportType = type.detailLabel
        }
        run.bibNumber = bib.trimmingCharacters(in: .whitespacesAndNewlines)
        run.finishPlace = finishPlace.trimmingCharacters(in: .whitespacesAndNewlines)
        run.updatedAt = Date()
        try? context.save()
        dismiss()
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
