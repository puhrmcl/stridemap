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
                        .font(.etch(compact ? .caption : .subheadline, weight: .semibold))
                        .lineLimit(1)
                    Text(Format.distance(run.distance))
                        .font(compact ? .caption2 : .caption)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .padding(compact ? 8 : 12)

                routeBadge(compact: compact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
            ZStack {
                LinearGradient(
                    colors: [Theme.Palette.stone, Theme.Palette.mist],
                    startPoint: .top, endPoint: .bottom
                )
                // Treadmill runs have no route to draw — mark them with a clean indoor glyph so
                // the tile reads as intentional, not as a missing map.
                if run.isIndoor {
                    Image(systemName: IndoorGlyph.symbol)
                        .font(.system(size: min(size.width, size.height) * 0.26, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.45))
                }
            }
        }
    }

    /// A small chip in the top-right showing the run's route — useful when a photo covers the
    /// tile and the map fallback (which already shows the route) isn't drawn.
    @ViewBuilder
    private func routeBadge(compact: Bool) -> some View {
        if !run.photoReferences.isEmpty, run.coordinates.count > 1 {
            let chip: CGFloat = compact ? 32 : 44
            RouteShape(coordinates: run.coordinates)
                .stroke(.white, style: StrokeStyle(lineWidth: compact ? 1.6 : 2, lineCap: .round, lineJoin: .round))
                .padding(compact ? 5 : 7)
                .frame(width: chip, height: chip)
                .background(.black.opacity(0.3), in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                .padding(compact ? 6 : 8)
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
