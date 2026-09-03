import SwiftUI

/// One photograph on a book page, loaded by the renderer: the image (nil when the library no
/// longer resolves the reference — the tile then draws its quiet frame so the proof shows the
/// gap honestly) and the caption that anchors it to an activity.
struct BookPagePhoto: Identifiable {
    let id = UUID()
    let image: UIImage?
    let caption: String
}

/// The photograph pages — the month's picture side of its spread, and the span-wide gallery.
/// Photos are the book's memory; the routes say what happened, the pictures say what it felt
/// like, and the two never share a page: a month with photographs becomes a two-page spread,
/// routes and numbers on one side, pictures on the other.
extension BookPageView {

    // MARK: The month's pictures — the second page of a chapter spread

    /// Faces the chapter page: same header vocabulary, the month named again so the spread
    /// reads as one piece, and the month's photographs in a collage sized to their count.
    func chapterPhotosPage(_ start: Date, photos: [BookPagePhoto]) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chapterName(start).uppercased())
                        .font(.etchSerif(size: 44, weight: .regular)).tracking(2)
                        .foregroundStyle(ink)
                    Spacer()
                    Text("IN PICTURES")
                        .font(.etch(size: 13, weight: .semibold)).tracking(4)
                        .foregroundStyle(accent)
                }
                Rectangle().fill(subtle.opacity(0.35)).frame(height: 1.5)
            }
            photoCollage(photos, columns: photos.count <= 1 ? 1 : photos.count <= 4 ? 2 : 3)
        }
        .padding(margin)
    }

    // MARK: The gallery — the whole span in pictures

    var galleryPage: some View {
        VStack(spacing: 34) {
            pageHeader(plan.subject.kind == .year ? "WHAT THE YEAR LOOKED LIKE"
                                                  : "WHAT IT LOOKED LIKE",
                       subtitle: "IN PICTURES")
            photoCollage(photos, columns: photos.count <= 4 ? 2 : photos.count <= 9 ? 3 : 4)
        }
        .padding(margin)
    }

    // MARK: The collage

    /// Equal-height rows that fill the page — deterministic, print-stable, no masonry
    /// surprises. Every photograph sits in a hairline frame with its activity named beneath;
    /// a reference the library can't resolve any more draws the frame empty, so what the
    /// proof shows is exactly what would print.
    func photoCollage(_ photos: [BookPagePhoto], columns: Int) -> some View {
        let rows = stride(from: 0, to: photos.count, by: columns).map {
            Array(photos[$0..<min($0 + columns, photos.count)])
        }
        return VStack(spacing: 24) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(row) { item in
                        photoTile(item)
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func photoTile(_ item: BookPagePhoto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ink.opacity(0.045)
                if let image = item.image {
                    Color.clear.overlay(
                        Image(uiImage: image).resizable().scaledToFill()
                    )
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(subtle.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(Rectangle().strokeBorder(ink.opacity(0.14), lineWidth: 1))
            Text(item.caption.uppercased())
                .font(.etch(size: 10.5, weight: .semibold)).tracking(1.4)
                .foregroundStyle(subtle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
