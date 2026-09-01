import SwiftUI

/// A framed print, drawn as an object rather than as a coloured rectangle.
///
/// The old mockup was the artwork inside a flat fill with one drop shadow. Beside the photographed
/// mockups every competitor in this category uses, it read as a diagram of a frame — and a buyer
/// deciding whether to spend $139 on a physical object is reading the object, not the artwork. This
/// draws the things that actually make a frame look like a frame in a photograph:
///
/// - **Depth in the moulding.** Light falls from the upper left, so the top and left faces catch it
///   and the bottom and right fall away. A single flat colour has no faces at all.
/// - **The rebate.** Where the moulding lips over the sheet there is a hard, dark line — the frame
///   is in front of the paper, and this is the only cue that says so.
/// - **Grain**, on the timbers that have it. Natural and brown mouldings are wood; black, white and
///   grey are painted, and drawing grain on them would be inventing a material.
/// - **Glazing.** The Classic Frame ships with shatterproof glazing and the medal frame with
///   Perspex, so a soft raking reflection across the upper left is what the object does in a room.
/// - **Two shadows.** A tight contact shadow where the frame meets the wall, and a wide ambient one
///   beneath it. One shadow reads as a sticker; two read as a hanging object.
///
/// Everything is drawn, not photographed: a photographic mockup would need one plate per moulding
/// colour per size, and the artwork inside still has to be the buyer's own.
struct FramedPrintMockup<Art: View>: View {
    /// The moulding colour.
    var moulding: Color
    /// Whether this timber shows grain. Painted finishes do not.
    var hasGrain: Bool = false
    /// Moulding width in points, at the size this is being drawn.
    var mouldingWidth: CGFloat = 13
    /// Perspex or glass over the artwork.
    var showsGlazing: Bool = true
    @ViewBuilder var art: () -> Art

    var body: some View {
        art()
            // The rebate: the moulding lips over the paper, and this hard inner line is what puts
            // the frame in front of the print rather than around it.
            .overlay {
                Rectangle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.black.opacity(0.42), .black.opacity(0.16)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1, mouldingWidth * 0.09)
                    )
            }
            .padding(mouldingWidth)
            .background {
                ZStack {
                    // The moulding's own faces. The gradient runs across the corner so the top and
                    // left read lit and the bottom and right read shaded.
                    LinearGradient(
                        stops: [
                            .init(color: lighten(moulding, 0.20), location: 0),
                            .init(color: moulding, location: 0.42),
                            .init(color: darken(moulding, 0.22), location: 1)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    if hasGrain { grain }
                }
            }
            // The outer arris — a fine highlight along the top-left edge and a shadow along the
            // bottom-right, which is what stops a rectangle of colour reading as flat.
            .overlay {
                Rectangle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.30), .black.opacity(0.28)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay { if showsGlazing { glazing } }
            // Contact shadow: tight, close, directly under the object.
            .shadow(color: .black.opacity(0.34), radius: mouldingWidth * 0.30,
                    x: 0, y: mouldingWidth * 0.20)
            // Ambient shadow: wide and soft, the light the room throws back.
            .shadow(color: .black.opacity(0.18), radius: mouldingWidth * 1.5,
                    x: 0, y: mouldingWidth * 0.9)
    }

    /// Timber grain: fine, irregular striations along the length of each rail. Deterministic, so a
    /// mockup does not shimmer between renders.
    private var grain: some View {
        Canvas { context, size in
            var seed: UInt64 = 20_260_829
            func random() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat((seed >> 33) % 1_000) / 1_000
            }
            let count = Int(size.height / 3)
            for i in 0..<max(count, 1) {
                let y = size.height * CGFloat(i) / CGFloat(max(count, 1)) + random() * 2
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                // A slight wander, so the lines read as grain rather than as ruling.
                path.addCurve(
                    to: CGPoint(x: size.width, y: y + (random() - 0.5) * 3),
                    control1: CGPoint(x: size.width * 0.35, y: y + (random() - 0.5) * 4),
                    control2: CGPoint(x: size.width * 0.7, y: y + (random() - 0.5) * 4)
                )
                context.stroke(
                    path,
                    with: .color(.black.opacity(0.03 + random() * 0.05)),
                    lineWidth: 0.4 + random() * 0.8
                )
            }
        }
        .blendMode(.multiply)
    }

    /// A raking reflection across the glazing — a broad soft band from the upper left, the way a
    /// window falls across glass. Kept faint: the artwork has to stay the thing being looked at.
    private var glazing: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.16), location: 0),
                    .init(color: .white.opacity(0.05), location: 0.28),
                    .init(color: .clear, location: 0.52),
                    .init(color: .white.opacity(0.035), location: 0.72),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(width: w, height: h)
            .allowsHitTesting(false)
        }
    }

    private func lighten(_ color: Color, _ amount: CGFloat) -> Color {
        color.mixed(with: .white, amount: amount)
    }
    private func darken(_ color: Color, _ amount: CGFloat) -> Color {
        color.mixed(with: .black, amount: amount)
    }
}

/// A loose sheet, unframed and unmounted. Two shadows so it reads as paper on a wall rather than
/// a sticker — the same drawing the print shop uses for Fine-Art.
struct LooseSheetMockup<Art: View>: View {
    @ViewBuilder var art: () -> Art

    var body: some View {
        art()
            .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
            .shadow(color: .black.opacity(0.15), radius: 16, y: 11)
    }
}

/// A print hung from magnetic wood battens. The strips sit *over* the sheet — the same geometry
/// the order path reserves — so the mockup cannot promise a bigger image than ships.
struct HangerPrintMockup<Art: View>: View {
    var wood: Color
    /// Strip thickness in the view's coordinate space. Honest to the 15mm cover: on a 36″ sheet
    /// that is a thin band, not a decorative batten.
    var stripHeight: CGFloat
    @ViewBuilder var art: () -> Art

    var body: some View {
        art()
            .padding(.vertical, stripHeight)
            .background(Theme.Palette.bone)
            .overlay(alignment: .top) { strip }
            .overlay(alignment: .bottom) { strip }
            .shadow(color: .black.opacity(0.24), radius: 14, y: 9)
    }

    /// A solid timber has a lit face and a shaded one, and the edge where it meets the paper
    /// casts a line — without those it reads as a printed band rather than wood clamped over
    /// the sheet.
    private var strip: some View {
        LinearGradient(
            stops: [
                .init(color: wood.mixed(with: .white, amount: 0.16), location: 0),
                .init(color: wood, location: 0.55),
                .init(color: wood.mixed(with: .black, amount: 0.18), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: stripHeight)
        .overlay(Rectangle().fill(.black.opacity(0.22)).frame(height: 0.75), alignment: .bottom)
        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
    }
}

/// The wall a framed print hangs on: a warm neutral with the light falling from the upper left and
/// the corners drawing down, rather than a flat grey card.
struct MockupWall: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.Artwork.mockupWallLight, Theme.Artwork.mockupWallShade],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // The vignette. A wall photographed in a room is never evenly lit, and an even one is
            // the single clearest tell that a mockup was generated.
            RadialGradient(
                colors: [.clear, .black.opacity(0.10)],
                center: .init(x: 0.42, y: 0.34), startRadius: 40, endRadius: 320
            )
        }
    }
}

extension Color {
    /// Blends toward another colour. Used for the moulding's lit and shaded faces, so one catalog
    /// colour produces a whole timber rather than a flat fill.
    func mixed(with other: Color, amount: CGFloat) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return Color(red: Double(r1 + (r2 - r1) * t),
                     green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t))
    }
}
