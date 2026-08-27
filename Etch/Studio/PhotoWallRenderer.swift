import UIKit
import SwiftUI

/// Draws the Photo Wall as the object it becomes: photographs behind a snow-white mount whose
/// windows are cut one per picture, inside a classic frame.
///
/// The bare grid the wall view shows is the *artwork*; this is the *product*. A storefront tile
/// showing the artwork promises a print, and what arrives is a framed object — so the tile draws
/// what ships. Every dimension here comes from `MultiPhotoFrameCatalog`, which comes from the
/// live catalog, so the mockup is a scale drawing of the frame rather than an impression of one.
enum PhotoWallRenderer {

    /// Where each window sits, in a unit square over the frame's glaze. Shared by the mockup and
    /// by anything that later composes the real print file, so the two can never disagree about
    /// where a photograph goes.
    struct Aperture {
        /// Normalised rect within the glaze (top-left origin), 0…1 on both axes.
        let unit: CGRect
        let column: Int
        let row: Int
    }

    /// The window grid for a layout, in normalised coordinates.
    ///
    /// The catalog's numbers don't quite close on their own: eight 60mm cells with 20mm between
    /// them span 660mm of a 750mm glaze, so 45mm is left over at each end. Rather than assume a
    /// uniform border, the leftover is split evenly as the outer margin and the inner gaps stay at
    /// the stated 20mm. That reproduces the templates — a mount with a wider margin than gutter,
    /// which is how mounts are actually cut — and the margins come out different top-to-bottom
    /// versus side-to-side on every size, which is the frame's own asymmetry, not an error here.
    static func apertures(for layout: MultiPhotoFrameCatalog.Layout,
                          landscape: Bool = true) -> [Aperture] {
        let cell = MultiPhotoFrameCatalog.cellMM
        let gap = MultiPhotoFrameCatalog.borderMM
        let cols = layout.columns, rows = layout.rows
        let sheetW = landscape ? layout.widthMM : layout.heightMM
        let sheetH = landscape ? layout.heightMM : layout.widthMM
        let gridW = CGFloat(cols) * cell + CGFloat(cols - 1) * gap
        let gridH = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
        let marginX = max(0, (sheetW - gridW) / 2)
        let marginY = max(0, (sheetH - gridH) / 2)

        var out: [Aperture] = []
        out.reserveCapacity(cols * rows)
        for row in 0..<rows {
            for column in 0..<cols {
                let x = marginX + CGFloat(column) * (cell + gap)
                let y = marginY + CGFloat(row) * (cell + gap)
                out.append(Aperture(
                    unit: CGRect(x: x / sheetW, y: y / sheetH,
                                 width: cell / sheetW, height: cell / sheetH),
                    column: column, row: row
                ))
            }
        }
        return out
    }

    /// Renders the framed wall.
    ///
    /// - Parameters:
    ///   - photos: images in reading order; fewer than the layout's capacity leaves the remaining
    ///     windows empty, which is exactly what the buyer would receive.
    ///   - layout: the frame being drawn.
    ///   - moulding: frame colour.
    ///   - longEdge: output pixels on the long edge.
    static func image(photos: [UIImage],
                      layout: MultiPhotoFrameCatalog.Layout,
                      moulding: FrameFinish = .black,
                      longEdge: CGFloat = 900) -> UIImage? {
        // Portrait when the grid is taller than it is wide — the same SKU, turned. The catalog
        // reports portrait print areas; the artwork templates are drawn landscape.
        let landscape = layout.columns >= layout.rows
        let sheetW = landscape ? layout.widthMM : layout.heightMM
        let sheetH = landscape ? layout.heightMM : layout.widthMM
        let scale = longEdge / max(sheetW, sheetH)
        let glaze = CGSize(width: sheetW * scale, height: sheetH * scale)

        // Classic moulding is ~20mm face — drawn to scale like everything else.
        let mouldingPx = 20 * scale
        let canvas = CGSize(width: glaze.width + mouldingPx * 2,
                            height: glaze.height + mouldingPx * 2)
        guard canvas.width > 1, canvas.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)

        return renderer.image { context in
            let cg = context.cgContext

            // Moulding.
            UIColor(Color(hex: moulding.mouldingHex) ?? .black).setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))

            // Mount. One colour, snow white, because the catalog reports exactly one.
            let glazeRect = CGRect(x: mouldingPx, y: mouldingPx,
                                   width: glaze.width, height: glaze.height)
            UIColor(white: 0.976, alpha: 1).setFill()
            cg.fill(glazeRect)

            // Windows, and the photographs behind them.
            for (index, aperture) in apertures(for: layout, landscape: landscape).enumerated() {
                let window = CGRect(
                    x: glazeRect.minX + aperture.unit.minX * glazeRect.width,
                    y: glazeRect.minY + aperture.unit.minY * glazeRect.height,
                    width: aperture.unit.width * glazeRect.width,
                    height: aperture.unit.height * glazeRect.height
                )
                if index < photos.count {
                    cg.saveGState()
                    cg.clip(to: window)
                    draw(photos[index], filling: window)
                    cg.restoreGState()
                } else {
                    // An uncut window shows the backing board, not white — an empty slot should
                    // look empty, so a count that doesn't fill the frame reads as one.
                    UIColor(white: 0.90, alpha: 1).setFill()
                    cg.fill(window)
                }
                // The bevel: mounts are cut at an angle, and that pale edge is most of why a
                // mounted print looks mounted.
                UIColor(white: 1.0, alpha: 0.85).setStroke()
                let bevel = UIBezierPath(rect: window.insetBy(dx: -0.5, dy: -0.5))
                bevel.lineWidth = max(0.5, 2.4 * scale)
                bevel.stroke()
            }

            // The rebate: a thin shadow where the moulding lips over the glaze.
            UIColor.black.withAlphaComponent(0.22).setStroke()
            let edge = UIBezierPath(rect: glazeRect)
            edge.lineWidth = max(1, mouldingPx * 0.12)
            edge.stroke()
        }
    }

    /// Aspect-fill an image into a rect — the same crop the real mount makes, since a square
    /// window over a rectangular photograph takes the middle.
    private static func draw(_ image: UIImage, filling rect: CGRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        image.draw(in: CGRect(x: rect.midX - drawn.width / 2,
                              y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height))
    }
}
