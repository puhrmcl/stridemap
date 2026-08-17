import SwiftUI

/// A gallery poster of every run's cover photo — a contact-sheet "photo wall" of your history,
/// for the runs that have a picture. Filterable by year, state, or location and sortable, then
/// rendered to a shareable poster image. Only runs with at least one photo take part.
struct PhotoWallView: View {
    /// The activity-scoped runs to draw from (Studio passes its current scope).
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss

    @State private var filter: Filter = .all
    @State private var sort: SortOrder = .newest
    @State private var images: [UUID: UIImage] = [:]
    @State private var posterImage: UIImage?

    /// At most this many photos on one wall — a full-bleed poster, newest kept when there are more.
    private let maxPhotos = 48

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
        var id: String { rawValue }
    }

    // MARK: Data

    /// Every scoped run that has a cover photo.
    private var photoRuns: [Run] { runs.filter { !$0.photoReferences.isEmpty } }

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

    /// The runs shown, sorted then capped to the wall size.
    private var displayRuns: [Run] {
        let sorted: [Run]
        switch sort {
        case .newest: sorted = filtered.sorted { $0.startDate > $1.startDate }
        case .oldest: sorted = filtered.sorted { $0.startDate < $1.startDate }
        case .location:
            sorted = filtered.sorted {
                let a = $0.placeLabel.isEmpty ? "~" : $0.placeLabel
                let b = $1.placeLabel.isEmpty ? "~" : $1.placeLabel
                return a == b ? $0.startDate > $1.startDate : a < b
            }
        }
        return Array(sorted.prefix(maxPhotos))
    }

    private func cityLabel(_ place: RunStatistics.TravelPlace) -> String {
        let parts = place.label.components(separatedBy: ", ")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ", ") : place.label
    }

    private var filterLabel: String {
        switch filter {
        case .all:            return "All Photos"
        case .year(let y):    return String(y)
        case .state(let s):   return s
        case .place(let name): return name
        }
    }

    /// Cache key so images/poster re-render when the shown set or order changes.
    private var renderKey: String {
        "\(filterLabel)-\(sort.rawValue)-\(displayRuns.map { $0.id.uuidString }.joined())"
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
            .task(id: renderKey) { await loadAndRender() }
        }
    }

    // MARK: Preview

    private var preview: some View {
        ScrollView {
            Group {
                if let posterImage {
                    Image(uiImage: posterImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Palette.bone)
                        .aspectRatio(posterAspect, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                ProgressView().tint(Theme.accent)
                                Text("Composing your wall…")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                filterMenu
                sortMenu
            }
            Text("\(displayRuns.count) \(displayRuns.count == 1 ? "photo" : "photos")"
                 + (filtered.count > maxPhotos ? " · newest \(maxPhotos) of \(filtered.count)" : ""))
                .font(.subheadline)
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
            Picker("Sort", selection: $sort) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            menuChip(icon: "arrow.up.arrow.down", text: sort.rawValue)
        }
    }

    private func menuChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.1), in: .capsule)
    }

    // MARK: Poster composition

    private let posterSize = CGSize(width: 1000, height: 1400)
    private var posterAspect: CGFloat { posterSize.width / posterSize.height }

    /// Near-square column count that caps at 4, so few photos still read as a tidy wall.
    private var columnCount: Int {
        let n = displayRuns.count
        return max(1, min(4, Int(ceil(Double(n).squareRoot()))))
    }

    private var dateRangeText: String {
        let dates = displayRuns.map(\.startDate)
        guard let first = dates.min(), let last = dates.max() else { return "" }
        let cal = Calendar.current
        let y0 = cal.component(.year, from: first), y1 = cal.component(.year, from: last)
        return y0 == y1 ? String(y0) : "\(y0)–\(y1)"
    }

    /// The fixed-size poster used both for on-screen preview (rendered) and export.
    private var posterContent: some View {
        let spacing: CGFloat = 8
        let padding: CGFloat = 56
        let cols = columnCount
        let contentWidth = posterSize.width - padding * 2
        let cellSize = (contentWidth - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        let rows = displayRuns.chunked(into: cols)

        return VStack(spacing: 26) {
            VStack(spacing: 6) {
                Text("PHOTO WALL")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(Theme.accent)
                Text(filterLabel)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.ink)
            }

            VStack(spacing: spacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: spacing) {
                        ForEach(row, id: \.id) { run in
                            cell(run, size: cellSize)
                        }
                        if row.count < cols {
                            ForEach(0..<(cols - row.count), id: \.self) { _ in
                                Color.clear.frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack {
                Text("\(displayRuns.count) \(displayRuns.count == 1 ? "photo" : "photos")")
                Spacer()
                Text(dateRangeText)
            }
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Palette.ink.opacity(0.6))
        }
        .padding(padding)
        .frame(width: posterSize.width, height: posterSize.height, alignment: .top)
        .background(Theme.Palette.bone)
    }

    private func cell(_ run: Run, size: CGFloat) -> some View {
        Group {
            if let image = images[run.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.Palette.stone)
                    .overlay { Image(systemName: "photo").foregroundStyle(Theme.Palette.ink.opacity(0.3)) }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(.rect(cornerRadius: 6))
    }

    // MARK: Loading & rendering

    /// Loads any missing cover images, then renders the poster to a UIImage for preview & export.
    @MainActor
    private func loadAndRender() async {
        for run in displayRuns {
            guard images[run.id] == nil, let id = run.photoReferences.first else { continue }
            if let img = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 600, height: 600)) {
                images[run.id] = img
            }
        }
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
