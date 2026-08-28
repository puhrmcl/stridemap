import SwiftUI

/// The medal display frame as an object: the moulding, the snow-white top mount, the medal's
/// aperture on the left, and the printed panel on the right.
///
/// One drawing, two callers — the product screen and the storefront tile. The storefront used to
/// show a plain poster render for this product, which promised the wrong object: the thing that
/// ships is a frame with a window cut in it, and a tile showing a poster is a tile for a different
/// product. Sharing the view also means the two can never disagree about a colour, which they
/// already had begun to.
///
/// The aperture is drawn as an empty well rather than with a stock medal in it. What hangs there is
/// the buyer's own, and a mockup that supplies one would be showing them something they are not
/// being sent.
struct MedalFrameMockup: View {
    /// The composed print that sits beside the medal. Nil renders the bare panel stock.
    var panel: UIImage?
    var frameColour: String = "black"
    var mountColour: String = "Black"
    /// Multiplier on the drawn geometry, so the same object can be a storefront thumbnail or a
    /// full-width mockup on the product screen.
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 14 * scale) {
            RoundedRectangle(cornerRadius: 6 * scale)
                .fill(Color(hex: MedalFrameCatalog.mountHex(mountColour)) ?? .black)
                .frame(width: 92 * scale, height: 126 * scale)
                .overlay {
                    Image(systemName: "medal")
                        .font(.system(size: 26 * scale, weight: .light))
                        .foregroundStyle(.white.opacity(0.22))
                }
            Group {
                if let panel {
                    Image(uiImage: panel).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Theme.Palette.bone)
                }
            }
            .frame(width: 92 * scale, height: 126 * scale)
            .clipped()
        }
        .padding(18 * scale)
        .background(Color(white: 0.97))            // the snow-white top mount
        .padding(14 * scale)                       // the moulding
        .background(Color(hex: MedalFrameCatalog.mouldingHex(frameColour)) ?? .black)
    }

    /// The mockup as a flat image, for surfaces that need a `UIImage` rather than a view — the
    /// storefront tile renders its products to images so the grid can cross-fade them in.
    @MainActor
    static func image(panel: UIImage?, frameColour: String = "black",
                      mountColour: String = "Black", scale: CGFloat = 2) -> UIImage? {
        let renderer = ImageRenderer(
            content: MedalFrameMockup(panel: panel, frameColour: frameColour,
                                      mountColour: mountColour, scale: scale)
        )
        renderer.scale = 2
        return renderer.uiImage
    }
}
