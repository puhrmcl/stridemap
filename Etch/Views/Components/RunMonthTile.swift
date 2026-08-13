import SwiftUI

/// A Timeline month tile: the run's photo, or a brand-tinted map of its route when there's no
/// photo, with the run title + distance captioned over the bottom. Loads its image lazily and
/// sizes it to the tile.
struct RunMonthTile: View {
    let run: Run
    var corner: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 220
            ZStack(alignment: .bottomLeading) {
                background(geo.size)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(run.name)
                        .font(.system(compact ? .caption : .subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text(Format.distance(run.distance))
                        .font(compact ? .caption2 : .caption)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .padding(compact ? 8 : 12)
            }
            .task(id: sizeKey(geo.size)) { await load(size: geo.size) }
        }
        .clipShape(.rect(cornerRadius: corner))
        .contentShape(.rect)
    }

    /// The photo (or brand-map fallback), pinned to the tile's exact size so a large photo
    /// can't grow the ZStack and push the title/distance caption out of the clipped frame.
    @ViewBuilder
    private func background(_ size: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            LinearGradient(
                colors: [Theme.Palette.stone, Theme.Palette.mist],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func sizeKey(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    private func load(size: CGSize) async {
        guard size.width > 1, size.height > 1 else { return }
        // Prefer the run's photo; otherwise fall back to a brand-tinted map of the route.
        if let id = run.photoReferences.first,
           let photo = await PhotoLibrary.image(
                for: id, targetSize: CGSize(width: size.width * 3, height: size.height * 3)) {
            image = photo
            return
        }
        image = await PosterMap.tileImage(for: run, size: size)
    }
}
