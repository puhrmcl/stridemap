import SwiftUI

/// A gallery poster of your run cover photos — a contact-sheet "photo wall" for the runs that have
/// a picture. Filter by year/state/location, sort or shuffle, tap a photo to swap it out, dial the
/// count up or down, and share the text-free grid as an image.
struct PhotoWallView: View {
    /// The activity-scoped runs to draw from (Studio passes its current scope).
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss

    @State private var filter: Filter = .all
    @State private var sort: SortOrder = .newest
    /// Forty is the wall's default because it is what the frame it prints into wants: the L
    /// frame's 8×5, filled to the corner.
    @State private var count = MultiPhotoFrameCatalog.defaultPhotos
    /// Photos the user tapped away — the next unused photo fills their slot.
    @State private var excludedIDs: Set<UUID> = []
    /// A shuffled ordering of run ids, regenerated each time Shuffle is tapped.
    @State private var randomOrder: [UUID] = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var posterImage: UIImage?
    /// Runs whose cover photo is a screenshot — kept out of the wall so it reads as photography.
    @State private var screenshotRunIDs: Set<UUID> = []

    /// Hard ceiling on one wall — which is also the frame's own ceiling, so a wall that reads
    /// well on screen is always one that can actually be made.
    private let maxPhotos = MultiPhotoFrameCatalog.maxPhotos

    enum Filter: Hashable {
        case all
        case year(Int)
        case state(String)
        case place(String)
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case location = "By Location"
        case random = "Shuffled"
        var id: String { rawValue }
    }

    // MARK: Data

    /// Every scoped run that has a cover photo — excluding screenshots, so the wall stays to real
    /// photography rather than app captures.
    private var photoRuns: [Run] {
        runs.filter { !$0.photoReferences.isEmpty && !screenshotRunIDs.contains($0.id) }
    }

    /// Photo runs after the active filter.
    private var filtered: [Run] {
        switch filter {
        case .all:
            return photoRuns
        case .year(let y):
            let cal = Calendar.current
            return photoRuns.filter { cal.component(.year, from: $0.startDate) == y }
        case .state(let s):
            return photoRuns.filter { ($0.state ?? "") == s }
        case .place(let name):
            let places = RunStatistics(photoRuns).travelPlaces
            guard let place = places.first(where: { cityLabel($0) == name }) else { return photoRuns }
            let ids = Set(place.runs.map(\.id))
            return photoRuns.filter { ids.contains($0.id) }
        }
    }

    /// Filtered runs in the chosen order (or the current shuffle).
    private var ordered: [Run] {
        switch sort {
        case .newest: return filtered.sorted { $0.startDate > $1.startDate }
        case .oldest: return filtered.sorted { $0.startDate < $1.startDate }
        case .location:
            return filtered.sorted {
                let a = $0.placeLabel.isEmpty ? "~" : $0.placeLabel
                let b = $1.placeLabel.isEmpty ? "~" : $1.placeLabel
                return a == b ? $0.startDate > $1.startDate : a < b
            }
        case .random:
            let rank = Dictionary(uniqueKeysWithValues: randomOrder.enumerated().map { ($1, $0) })
            return filtered.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        }
    }

    /// The pool available to show — ordered, minus the ones tapped away.
    private var pool: [Run] { ordered.filter { !excludedIDs.contains($0.id) } }

    /// The runs actually on the wall.
    private var shown: [Run] { Array(pool.prefix(count)) }

    /// Upper bound for the count stepper.
    private var maxCount: Int { max(1, min(pool.count, maxPhotos)) }

    private func cityLabel(_ place: RunStatistics.TravelPlace) -> String {
        let parts = place.label.components(separatedBy: ", ")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ", ") : place.label
    }

    private var filterLabel: String {
        switch filter {
        case .all:             return "All Photos"
        case .year(let y):     return String(y)
        case .state(let s):    return s
        case .place(let name): return name
        }
    }

    /// Columns for the current wall.
    ///
    /// When the count is one the frame is actually cut for — 24, 40, 60 — the wall takes that
    /// frame's own arrangement, so what's on screen is a preview of the object rather than a
    /// picture of something else. Forty in eight columns is the L frame; the near-square rule
    /// would have made it six columns and seven rows with four photos rattling in the last one.
    ///
    /// Any other count falls back to near-square, capped so cells never get too small — the cap
    /// is the widest frame's ten, not six, or the exact grids couldn't be reached.
    private var columnCount: Int {
        let n = max(shown.count, 1)
        if let layout = MultiPhotoFrameCatalog.exactLayout(forPhotos: n) { return layout.columns }
        return min(10, max(1, Int(ceil(Double(n).squareRoot()))))
    }

    /// Signature that changes whenever the shown set changes — drives image loading + re-render.
    private var renderKey: String {
        "\(shown.map { $0.id.uuidString }.joined())-\(columnCount)"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if photoRuns.isEmpty {
                    ContentUnavailableView(
                        "No run photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Add photos to your runs — or let Etch find them from your library on a run's page — and they'll gather here as a photo wall.")
                    )
                } else {
                    VStack(spacing: 0) {
                        preview
                        controls
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Photo Wall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let posterImage {
                        ShareLink(
                            item: Image(uiImage: posterImage),
                            preview: SharePreview(filterLabel, image: Image(uiImage: posterImage))
                        ) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .onChange(of: filter) { excludedIDs = []; clampCount() }
            .onAppear { clampCount() }
            .task { detectScreenshots() }
            .task(id: renderKey) { await loadAndRender() }
        }
    }

    // MARK: Preview (interactive — tap a photo to swap it out)

    private var preview: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount),
                spacing: 4
            ) {
                ForEach(shown, id: \.id) { run in
                    cell(run)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { remove(run) } }
                }
            }
            .padding(16)
        }
    }

    /// A strictly square tile: a placeholder rectangle sets the 1:1 shape from the grid-cell width,
    /// and the photo fills it as an overlay that's clipped to the square — so images can never
    /// overflow and overlap their neighbours (the source of the "chaos").
    private func cell(_ run: Run) -> some View {
        Rectangle()
            .fill(Theme.Palette.stone)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = images[run.id] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(.rect(cornerRadius: 3))
            .contentShape(.rect)
    }

    @MainActor
    private func detectScreenshots() {
        let candidates = runs.filter { !$0.photoReferences.isEmpty }
        let coverByRun = candidates.compactMap { run in run.photoReferences.first.map { (run.id, $0) } }
        let shots = PhotoLibrary.screenshotIdentifiers(among: coverByRun.map(\.1))
        guard !shots.isEmpty else { return }
        screenshotRunIDs = Set(coverByRun.filter { shots.contains($0.1) }.map(\.0))
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                filterMenu
                sortMenu
                shuffleButton
            }
            HStack(spacing: 16) {
                Stepper("Photos: \(shown.count)", value: $count, in: 1...maxCount)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            .frame(maxWidth: 340)
            // Which frame this count would actually be made in, and whether it fills it. The
            // count is a choice about an object, so it says what the object would be.
            Text(MultiPhotoFrameCatalog.fitDescription(forPhotos: shown.count))
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.accent)
            if !excludedIDs.isEmpty {
                Button {
                    withAnimation { excludedIDs.removeAll() }
                } label: {
                    Label("Restore removed (\(excludedIDs.count))", systemImage: "arrow.uturn.backward")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            Text("Tap a photo to swap it out.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var filterMenu: some View {
        let stats = RunStatistics(photoRuns)
        let years = stats.years
        let grouped = Dictionary(grouping: photoRuns.filter { !($0.state ?? "").isEmpty }, by: { $0.state ?? "" })
        let states = grouped.map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        let places = stats.travelPlaces
        return Menu {
            Button { filter = .all } label: {
                Label("All Photos", systemImage: filter == .all ? "checkmark" : "square.grid.2x2")
            }
            if !years.isEmpty {
                Menu("Year") {
                    ForEach(years, id: \.self) { year in
                        Button(String(year)) { filter = .year(year) }
                    }
                }
            }
            if !states.isEmpty {
                Menu("State") {
                    ForEach(states, id: \.name) { state in
                        Button("\(state.name)  ·  \(state.count)") { filter = .state(state.name) }
                    }
                }
            }
            if !places.isEmpty {
                Menu("Location") {
                    ForEach(places) { place in
                        Button("\(cityLabel(place))  ·  \(place.runs.count)") {
                            filter = .place(cityLabel(place))
                        }
                    }
                }
            }
        } label: {
            menuChip(icon: "line.3.horizontal.decrease", text: filterLabel)
        }
    }

    private var sortMenu: some View {
        Menu {
            // Shuffle is its own button; the menu covers the ordered choices.
            ForEach([SortOrder.newest, .oldest, .location]) { option in
                Button(option.rawValue) { sort = option }
            }
        } label: {
            menuChip(icon: "arrow.up.arrow.down", text: sort == .random ? "Shuffled" : sort.rawValue)
        }
    }

    private var shuffleButton: some View {
        Button { shuffle() } label: {
            menuChip(icon: "shuffle", text: "Shuffle")
        }
        .buttonStyle(.plain)
    }

    private func menuChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.1), in: .capsule)
    }

    // MARK: Actions

    private func remove(_ run: Run) {
        excludedIDs.insert(run.id)
    }

    private func shuffle() {
        randomOrder = filtered.map(\.id).shuffled()
        sort = .random
    }

    private func clampCount() {
        count = min(count, maxCount)
        if count < 1 { count = 1 }
    }

    // MARK: Poster (text-free grid) + rendering

    private let posterWidth: CGFloat = 1000
    private let posterPadding: CGFloat = 28
    private let posterSpacing: CGFloat = 4

    private var posterCell: CGFloat {
        let cols = CGFloat(columnCount)
        return (posterWidth - posterPadding * 2 - posterSpacing * (cols - 1)) / cols
    }

    private var posterHeight: CGFloat {
        let rows = Int(ceil(Double(shown.count) / Double(columnCount)))
        return posterPadding * 2 + CGFloat(rows) * posterCell + CGFloat(max(0, rows - 1)) * posterSpacing
    }

    /// The exported wall: just the photos, no title or footer text.
    private var posterContent: some View {
        let cols = columnCount
        let rows = shown.chunked(into: cols)
        return VStack(spacing: posterSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: posterSpacing) {
                    ForEach(row, id: \.id) { run in
                        exportCell(run)
                    }
                    if row.count < cols {
                        ForEach(0..<(cols - row.count), id: \.self) { _ in
                            Color.clear.frame(width: posterCell, height: posterCell)
                        }
                    }
                }
            }
        }
        .padding(posterPadding)
        .frame(width: posterWidth, height: posterHeight)
        .background(Theme.Palette.bone)
    }

    private func exportCell(_ run: Run) -> some View {
        Group {
            if let image = images[run.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.Palette.stone)
            }
        }
        .frame(width: posterCell, height: posterCell)
        .clipped()
        .clipShape(.rect(cornerRadius: 3))
    }

    @MainActor
    private func loadAndRender() async {
        for run in shown {
            guard images[run.id] == nil, let id = run.photoReferences.first else { continue }
            if let img = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 600, height: 600)) {
                images[run.id] = img
            }
        }
        guard !shown.isEmpty else { posterImage = nil; return }
        let renderer = ImageRenderer(content: posterContent)
        renderer.scale = 3
        posterImage = renderer.uiImage
    }
}

private extension Array {
    /// Splits into consecutive chunks of at most `size`.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
