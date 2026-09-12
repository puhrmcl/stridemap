import SwiftUI

/// Every photograph attached to every activity, indexed for the Timeline's Gallery scope.
///
/// Groups follow activity chronology, oldest first, opening at the newest activity.
/// Each activity keeps its own cover/photo order and its own identity, even when names repeat.

/// One photograph, and the activity it belongs to.
struct GalleryPhoto: Identifiable {
    let photoID: String
    let run: Run
    /// The photo identifier alone is not unique across the library — an auto-matched picture can
    /// land on two activities that overlapped — so the row's identity carries both.
    var id: String { "\(run.id.uuidString)-\(photoID)" }
    var date: Date { run.startDate }
}

struct GalleryActivity: Identifiable {
    let run: Run
    let photos: [GalleryPhoto]
    var id: UUID { run.id }
}

enum GalleryIndex {
    static func activities(in runs: [Run]) -> [GalleryActivity] {
        runs.sorted {
            if $0.startDate == $1.startDate { return $0.id.uuidString < $1.id.uuidString }
            return $0.startDate < $1.startDate
        }.compactMap { run in
            let photos = run.photoReferences.map { GalleryPhoto(photoID: $0, run: run) }
            return photos.isEmpty ? nil : GalleryActivity(run: run, photos: photos)
        }
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
                    // Sunken, not ink. A run tile's placeholder is a dark square because one of
                    // them sits in a row of route drawings; a wall of five-across photographs
                    // that have not loaded yet is two hundred of them, and in the light
                    // appearance that is a page of black holes rather than a page waiting.
                    Rectangle().fill(Theme.Surface.sunken)
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
