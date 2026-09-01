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
        FramedPrintMockup(
            moulding: Color(hex: MedalFrameCatalog.mouldingHex(frameColour)) ?? .black,
            hasGrain: frameColour == "natural" || frameColour == "brown",
            mouldingWidth: 14 * scale
        ) {
            HStack(spacing: 14 * scale) {
                // The aperture is a window cut through the mount, so it sits *below* the board —
                // the inner shadow is what makes it read as a well rather than a dark rectangle
                // printed on the card.
                RoundedRectangle(cornerRadius: 6 * scale)
                    .fill(Color(hex: MedalFrameCatalog.mountHex(mountColour)) ?? .black)
                    .frame(width: 92 * scale, height: 126 * scale)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6 * scale)
                            .strokeBorder(
                                LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.10)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 2 * scale
                            )
                    }
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
                // The print sits under the mount's bevel too.
                .overlay {
                    Rectangle().strokeBorder(.black.opacity(0.18), lineWidth: 1 * scale)
                }
            }
            .padding(18 * scale)
            .background(Theme.Artwork.mountBoard)  // the snow-white top mount
        }
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
