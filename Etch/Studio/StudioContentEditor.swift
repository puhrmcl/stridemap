import SwiftUI

/// **Content** — what the poster actually says.
///
/// The old Data tab asked the user to think in the renderer's vocabulary: a "headline slot", four
/// "data points" drawn as empty dashed boxes whether or not they held anything, and three lines
/// named Text 1, Text 2 and Text 3. None of those are things a person wants; they are things the
/// composition has. This section names each line by what it *is* and shows the value that will be
/// printed, so the list reads as the poster's content rather than as the form that produces it.
///
/// Empty placeholder boxes are gone. A slot that holds nothing is simply not a row — adding one is
/// a single explicit action at the foot of the list.
struct StudioContentEditor: View {
    let run: Run
    @Binding var config: PosterConfig

    /// Editing targets handed back up to the editor, which owns the sheets.
    var onEditMetric: (StudioContentTarget) -> Void
    var onAddPhoto: () -> Void
    var onPickFramePhoto: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    /// Presenting the Files importer — the second door for photos that never joined the library.
    @State private var showFileImporter = false

    /// Which text line is expanded for inline editing. Only one at a time — the tray is short and
    /// two open keyboards would push the poster off screen.
    @State private var editingLine: TextLine?
    /// Reorder mode for the data rows. Explicit rather than drag-always-on: this list lives inside
    /// a panel the user can also drag to resize, and two live drag gestures in one surface is how
    /// you get a list that rubber-bands when someone meant to resize the tray.
    @State private var isReordering = false

    enum TextLine: String, Identifiable {
        case title, location, date, athlete
        var id: String { rawValue }
        var name: String {
            switch self {
            case .title:    return "Title"
            case .location: return "Location"
            case .date:     return "Date"
            case .athlete:  return "Name"
            }
        }
        var icon: String {
            switch self {
            case .title:    return "textformat"
            case .location: return "mappin.and.ellipse"
            case .date:     return "calendar"
            case .athlete:  return "person"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            included
            if config.family == .gallery { frames }
            if config.family == .map && config.mapLayout == .photo { photos }
            optionalElements
        }
    }

    // MARK: Included on poster

    private var included: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StudioGroupLabel(text: "Included on poster")
                if config.dataSlots.count > 1 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isReordering.toggle() }
                    } label: {
                        Text(isReordering ? "Done" : "Reorder")
                            .font(.etch(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            textRow(.title, show: $config.showTitle, text: $config.title, placeholder: run.name)
            textRow(.location, show: $config.showLocation, text: $config.location,
                    placeholder: derivedPlace)
            // The Gallery masthead carries only a title and a place — no date line — so the row is
            // offered where the composition can actually draw it.
            if config.family == .map {
                textRow(.date, show: $config.showDate, text: $config.date,
                        placeholder: Format.date(run.startDate))
            }

            // Whose miles these are. A line, not a signature block: name (and the pinned number,
            // when the race carries one) set a register under the place and date.
            textRow(.athlete, show: $config.showAthlete, text: $config.athleteName,
                    placeholder: "Your name")
            if config.showAthlete && !run.bibNumber.isEmpty {
                Toggle("Show bib \(run.bibNumber)", isOn: $config.showBib)
                    .font(.etch(.subheadline))
            }

            // The headline metric is a text line as far as the reader is concerned: it is the
            // biggest thing on the poster. Map only — a Gallery sheet has no headline block.
            if config.family == .map {
                metricRow(config.heroMetric, label: "Headline", isHeadline: true) {
                    onEditMetric(.hero)
                }
            }

            ForEach(Array(config.dataSlots.enumerated()), id: \.offset) { index, metric in
                metricRow(metric, label: metric.label.capitalized, isHeadline: false,
                          index: index) {
                    onEditMetric(.slot(index))
                }
            }

            if config.dataSlots.count < 4 {
                Button { onEditMetric(.add) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Add detail")
                            .font(.etch(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One editable line: a switch, its name, the value that will print, and — when tapped open —
    /// the field that overrides it.
    @ViewBuilder
    private func textRow(_ line: TextLine, show: Binding<Bool>, text: Binding<String>,
                         placeholder: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: line.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(show.wrappedValue ? Theme.accent : Color.secondary.opacity(0.5))
                    .frame(width: 22)

                Text(line.name)
                    .font(.etch(.subheadline))
                    .foregroundStyle(show.wrappedValue ? Color.primary : Color.secondary)

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        editingLine = editingLine == line ? nil : line
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                            .font(.etch(.subheadline))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!show.wrappedValue)
                .opacity(show.wrappedValue ? 1 : 0.4)

                Toggle("", isOn: show)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .scaleEffect(0.85)
            }
            .padding(.vertical, 7)

            if editingLine == line {
                HStack(spacing: 8) {
                    TextField(placeholder, text: text)
                        .font(.etch(.subheadline))
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { editingLine = nil }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
                    if !text.wrappedValue.isEmpty {
                        Button { text.wrappedValue = "" } label: {
                            Text("Reset")
                                .font(.etch(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 34)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// A data row: what it is, what it currently reads, and the controls to retune, reorder or
    /// remove it.
    @ViewBuilder
    private func metricRow(_ metric: StatMetric, label: String, isHeadline: Bool,
                           index: Int? = nil, edit: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: metric.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isHeadline ? Theme.accent : Theme.accent.opacity(0.75))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(isHeadline ? "Headline" : (metric == .none ? "Blank" : label))
                    .font(.etch(.subheadline))
                if isHeadline {
                    Text(metric == .none ? "None" : metric.label.capitalized)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }

            Spacer(minLength: 8)

            if isReordering, let index {
                HStack(spacing: 2) {
                    Button { move(index, by: -1) } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    Button { move(index, by: 1) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == config.dataSlots.count - 1)
                }
                .foregroundStyle(Theme.accent)
            } else {
                Button(action: edit) {
                    HStack(spacing: 4) {
                        Text(metric == .none ? "None" : (metric.value(for: run) ?? "—"))
                            .font(.etch(.subheadline))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }
                }
                .buttonStyle(.plain)

                if let index {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            guard config.dataSlots.indices.contains(index) else { return }
                            config.dataSlots.remove(at: index)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(label)")
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard config.dataSlots.indices.contains(index),
              config.dataSlots.indices.contains(target) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            config.dataSlots.swapAt(index, target)
        }
    }

    // MARK: Gallery frames

    /// What each Gallery frame shows. Content, not style: the frames are the poster's subject
    /// matter, which is why they moved out of the old Style tab.
    private var frames: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Frames")
            HStack(spacing: 8) {
                ForEach(0..<config.galleryDesign.frameCount, id: \.self) { i in
                    Menu {
                        Picker("Frame", selection: frameBinding(i)) {
                            ForEach(GalleryTileKind.allCases) { kind in
                                Label(kind.name, systemImage: kind.icon).tag(kind)
                            }
                        }
                        if frameKind(i) == .photo {
                            Button { onPickFramePhoto(i) } label: {
                                Label("Choose Photo…", systemImage: "photo.on.rectangle.angled")
                            }
                        }
                    } label: {
                        let kind = frameKind(i)
                        VStack(spacing: 3) {
                            Image(systemName: kind.icon).font(.system(size: 15, weight: .semibold))
                            Text(frameLabel(i, kind)).font(.etch(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Theme.accent.opacity(0.1), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            addPhotoButton
        }
    }

    private var photos: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(text: "Photos")
            Stepper("Photos on poster: \(config.mapPhotoCount)",
                    value: $config.mapPhotoCount, in: 1...3)
                .font(.etch(.subheadline))
            addPhotoButton
        }
    }

    /// Two doors to the same place: the camera roll, and Files — a race photo often arrives as a
    /// download or an AirDrop that never joined the library. A file import is saved *into* the
    /// library and referenced like any other photo, so downstream nothing knows the difference.
    private var addPhotoButton: some View {
        HStack(spacing: 10) {
            Button(action: onAddPhoto) {
                Label(run.photoReferences.isEmpty
                        ? "Camera Roll"
                        : "Camera Roll · \(run.photoReferences.count) on run",
                      systemImage: "photo.badge.plus")
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Theme.accent.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
            Button { showFileImporter = true } label: {
                Label("Files", systemImage: "folder.badge.plus")
                    .font(.etch(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Theme.accent.opacity(0.12), in: .capsule)
            }
            .buttonStyle(.plain)
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.image],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                Task { await importPhotoFiles(urls) }
            }
        }
    }

    private func importPhotoFiles(_ urls: [URL]) async {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let identifier = await PhotoLibrary.importImage(data: data) else { continue }
            if !run.photoReferences.contains(identifier) {
                run.photoReferences.append(identifier)
            }
        }
        run.updatedAt = Date()
        try? modelContext.save()
    }

    private func frameKind(_ i: Int) -> GalleryTileKind {
        let frames = config.resolvedFrames
        return i < frames.count ? frames[i] : .photo
    }

    private func frameLabel(_ i: Int, _ kind: GalleryTileKind) -> String {
        guard kind == .photo, run.photoReferences.count > 1 else { return kind.name }
        return "Photo \(effectivePhotoPick(i) + 1)"
    }

    private func effectivePhotoPick(_ i: Int) -> Int {
        let picks = config.resolvedPhotoPicks
        if i < picks.count, picks[i] >= 0 { return picks[i] }
        return config.resolvedFrames.prefix(i).filter { $0 == .photo }.count
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

    // MARK: Optional elements

    /// The extras the composition can draw. Each is offered only when this activity actually
    /// carries the data behind it — a pace band with no per-point timing is a promise the
    /// renderer cannot keep.
    private var optionalElements: some View {
        VStack(alignment: .leading, spacing: 4) {
            StudioGroupLabel(text: "Optional elements")
            elementToggle("Elevation profile", "mountain.2", $config.showElevation)
            if run.hasPaceSeries {
                elementToggle("Pace profile", "speedometer", $config.showPace)
            }
            if run.hasWeather {
                elementToggle("Weather", "cloud.sun", $config.includeWeather)
            }
            elementToggle("Data labels", "textformat.abc", $config.showStatLabels)
        }
    }

    private func elementToggle(_ title: String, _ icon: String, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(value.wrappedValue ? Theme.accent : Color.secondary.opacity(0.5))
                .frame(width: 22)
            Text(title)
                .font(.etch(.subheadline))
            Spacer(minLength: 8)
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(Theme.accent)
                .scaleEffect(0.85)
        }
        .padding(.vertical, 5)
    }

    private var derivedPlace: String {
        [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Which data element the metric picker is being opened for.
enum StudioContentTarget: Identifiable {
    case hero
    case slot(Int)
    case add
    var id: String {
        switch self {
        case .hero: return "hero"
        case .slot(let i): return "slot-\(i)"
        case .add: return "add"
        }
    }
}
