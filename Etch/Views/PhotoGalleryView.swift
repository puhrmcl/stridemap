import SwiftUI
import SwiftData

/// Every photograph attached to every activity, on Apple Photos' model.
///
/// Etch has always held these pictures and never had a place to look at them. They were reachable
/// one activity at a time, eight thumbnails behind a tap on a run — which is a filing cabinet, not
/// a gallery. Someone who has been running for six years has a few thousand photographs in here
/// taken at the far ends of their own map, and no way to see them as a body of work.
///
/// It follows the Timeline's arrangement rather than inventing a second one: months oldest at the
/// top, the newest photograph as the last tile on the page, and the page opens at the foot.
struct PhotoGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    /// The photo the full-screen viewer is opened on.
    @State private var opened: OpenedPhoto?
    @State private var landed = false

    /// One photograph, and the activity it belongs to.
    private struct Entry: Identifiable {
        let photoID: String
        let run: Run
        /// The photo identifier alone is not unique across the library — an auto-matched picture
        /// can land on two activities that overlapped — so the row's identity carries both.
        var id: String { "\(run.id.uuidString)-\(photoID)" }
        var date: Date { run.startDate }
    }

    private struct Month: Identifiable {
        let start: Date
        let entries: [Entry]
        var id: Date { start }
        var title: String {
            let formatter = DateFormatter()
            formatter.dateFormat = Calendar.current.isDate(start, equalTo: .now, toGranularity: .year)
                ? "MMMM" : "MMMM yyyy"
            return formatter.string(from: start)
        }
    }

    /// Every photograph, oldest first, grouped into the month its activity happened in.
    private var months: [Month] {
        let calendar = Calendar.current
        var entries: [Entry] = []
        for run in runs {
            for id in run.photoReferences { entries.append(Entry(photoID: id, run: run)) }
        }
        entries.sort { $0.date < $1.date }
        let grouped = Dictionary(grouping: entries) { entry -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }
        return grouped.keys.sorted().map { Month(start: $0, entries: grouped[$0] ?? []) }
    }

    private var all: [Entry] { months.flatMap(\.entries) }
    private var total: Int { all.count }

    /// The activity a photograph belongs to. First match wins on the rare shared picture — the
    /// cover it would set is that activity's, which is the one the reader tapped through from.
    private func owner(of photoID: String) -> Run? {
        runs.first { $0.photoReferences.contains(photoID) }
    }

    /// Five across, hairline gutters, edge to edge — the Timeline's All scope, and Photos' own
    /// density. The point of a wall of pictures is that the page stops being a container.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        NavigationStack {
            Group {
                if total == 0 {
                    ContentUnavailableView(
                        "No photos yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Photos you attach to an activity — or that Etch matches from your library — collect here.")
                    )
                } else {
                    gallery
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                if total > 0 {
                    ToolbarItem(placement: .principal) {
                        Text("\(total.formatted()) \(total == 1 ? "photo" : "photos")")
                            .font(.etch(.footnote, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(item: $opened) { selection in
                // The viewer walks the whole gallery rather than one activity's photos: this is a
                // gallery, and stopping the swipe at an activity boundary would be the filing
                // cabinet again. The cover action still resolves per photo, to whichever activity
                // owns the one on screen.
                RunPhotoViewer(
                    identifiers: all.map(\.photoID),
                    selection: selection.id,
                    isCoverPhoto: { id in owner(of: id)?.photoReferences.first == id },
                    onDelete: delete,
                    onSetCover: setCover
                )
            }
        }
    }

    private var gallery: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                    ForEach(months) { month in
                        Section {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(month.entries) { entry in
                                    Button { opened = OpenedPhoto(id: entry.photoID) } label: {
                                        GalleryTile(identifier: entry.photoID)
                                    }
                                    .buttonStyle(.plain)
                                    .id(entry.id)
                                }
                            }
                        } header: {
                            header(month)
                        }
                    }
                }
                .padding(.top, 2)
            }
            .task {
                // Opens on the newest photograph, at the foot — the Timeline's arrangement, and
                // the same reason: history runs upward from what you did last.
                guard !landed, let last = all.last else { return }
                landed = true
                try? await Task.sleep(nanoseconds: 60_000_000)
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func header(_ month: Month) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.title)
                .font(.etch(.headline, weight: .semibold))
            Spacer(minLength: 0)
            Text("\(month.entries.count)")
                .font(.etch(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func delete(_ photoID: String) {
        guard let run = owner(of: photoID) else { return }
        run.photoReferences.removeAll { $0 == photoID }
        run.updatedAt = Date()
        try? context.save()
    }

    /// Makes a photograph its activity's cover, from here as much as from the activity itself —
    /// the gallery is where you see a picture big enough to decide.
    private func setCover(_ photoID: String) {
        guard let run = owner(of: photoID),
              let index = run.photoReferences.firstIndex(of: photoID), index != 0 else { return }
        var refs = run.photoReferences
        refs.remove(at: index)
        refs.insert(photoID, at: 0)
        run.photoReferences = refs
        run.updatedAt = Date()
        try? context.save()
    }
}

/// The photo a full-screen viewer is opened on. File-local: `RunDetailView` has its own, and one
/// shared type in the global namespace for two call sites is not an abstraction, it is a name.
private struct OpenedPhoto: Identifiable { let id: String }

/// One square in the wall. A clear sizing container with the image in an overlay, so `scaledToFill`
/// can never push the grid around — the same construction the Timeline's tiles use.
private struct GalleryTile: View {
    let identifier: String
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.Brand.inkWell)
                }
            }
            .clipShape(.rect(cornerRadius: 3))
            .contentShape(.rect)
            .task(id: identifier) {
                image = await PhotoLibrary.image(
                    for: identifier,
                    targetSize: CGSize(width: 240, height: 240)
                )
            }
    }
}
