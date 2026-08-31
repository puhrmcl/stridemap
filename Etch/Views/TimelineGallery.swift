import SwiftUI

/// Every photograph attached to every activity, indexed for the Timeline's Gallery scope.
///
/// Etch has always held these pictures and never had a place to look at them: they were reachable
/// one activity at a time, eight thumbnails behind a tap on a run — a filing cabinet, not a
/// gallery. Someone who has been running for six years has a few thousand photographs in here
/// taken at the far ends of their own map, and no way to see them as a body of work.
///
/// Gallery is a fourth arrangement of the same history, which is why it lives beside Years, Months
/// and All rather than behind a corner button. Apple Photos' own grouping: months oldest at the
/// top, the newest photograph as the last tile on the page.

/// One photograph, and the activity it belongs to.
struct GalleryPhoto: Identifiable {
    let photoID: String
    let run: Run
    /// The photo identifier alone is not unique across the library — an auto-matched picture can
    /// land on two activities that overlapped — so the row's identity carries both.
    var id: String { "\(run.id.uuidString)-\(photoID)" }
    var date: Date { run.startDate }
}

struct GalleryMonth: Identifiable {
    let start: Date
    let photos: [GalleryPhoto]
    var id: Date { start }
    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(start, equalTo: .now, toGranularity: .year)
            ? "MMMM" : "MMMM yyyy"
        return formatter.string(from: start)
    }
}

enum GalleryIndex {
    /// Every photograph in the given activities, oldest first, grouped into the month its
    /// activity happened in.
    static func months(in runs: [Run]) -> [GalleryMonth] {
        let calendar = Calendar.current
        var photos: [GalleryPhoto] = []
        for run in runs {
            for id in run.photoReferences { photos.append(GalleryPhoto(photoID: id, run: run)) }
        }
        photos.sort { $0.date < $1.date }
        let grouped = Dictionary(grouping: photos) { photo -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: photo.date)) ?? photo.date
        }
        return grouped.keys.sorted().map { GalleryMonth(start: $0, photos: grouped[$0] ?? []) }
    }
}

/// One square in the wall. A clear sizing container with the image in an overlay, so `scaledToFill`
/// can never push the grid around — the same construction the Timeline's run tiles use.
struct GalleryTile: View {
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
