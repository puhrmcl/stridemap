import UIKit
import SwiftUI

/// Draws the Photo Wall as the object it becomes: the contact sheet printed edge to edge, behind
/// glass, in a classic frame.
///
/// An earlier version of this drew a snow-white mount with a window cut per photograph and a bevel
/// around each one. That was wrong, and the live catalog said so: `GLOBAL-MPF-*` is **No Mount /
/// No Mat**, one continuous print. The mounted line whose windows are actually cut exists only at
/// sizes this product does not use. A mockup showing a bevelled mount would have promised an
/// object nobody would receive — the exact failure a mockup exists to prevent.
///
/// What it means for the design is better than what it cost: the grid, the gutters and the margins
/// are all ours, and nothing has to register against a physical aperture.
enum PhotoWallRenderer {

    /// Renders the framed wall.
    ///
    /// - Parameters:
    ///   - photos: images in reading order; fewer than the grid holds leaves paper showing, which
    ///     is exactly what a buyer would receive.
    ///   - size: the frame being drawn.
    ///   - moulding: frame colour.
    ///   - ground: the paper between and around the photographs.
    ///   - longEdge: output pixels on the long edge.
    static func image(photos: [UIImage],
                      size: MultiPhotoFrameCatalog.Size,
                      moulding: FrameFinish = .black,
                      ground: Color = Theme.Palette.bone,
                      longEdge: CGFloat = 900) -> UIImage? {
        let aspect = size.printPixels.width / size.printPixels.height
        let sheet = aspect >= 1
            ? CGSize(width: longEdge, height: longEdge / aspect)
            : CGSize(width: longEdge * aspect, height: longEdge)
        guard sheet.width > 1, sheet.height > 1 else { return nil }

        // Classic moulding is a 20mm face on a frame whose glaze is 500mm across — 4% of the
        // sheet, drawn to that proportion rather than to a number that looked right.
        let moulder = min(sheet.width, sheet.height) * 0.04
        let canvas = CGSize(width: sheet.width + moulder * 2, height: sheet.height + moulder * 2)

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 2

        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cg = context.cgContext

            UIColor(Color(hex: moulding.mouldingHex) ?? .black).setFill()
            cg.fill(CGRect(origin: .zero, size: canvas))

            let sheetRect = CGRect(x: moulder, y: moulder, width: sheet.width, height: sheet.height)
            UIColor(ground).setFill()
            cg.fill(sheetRect)

            for (index, cell) in cells(for: size, in: sheetRect).enumerated() {
                guard index < photos.count else { continue }
                cg.saveGState()
                cg.clip(to: cell)
                draw(photos[index], filling: cell)
                cg.restoreGState()
            }

            // The rebate: a thin shadow where the moulding lips over the glass.
            UIColor.black.withAlphaComponent(0.22).setStroke()
            let edge = UIBezierPath(rect: sheetRect)
            edge.lineWidth = max(1, moulder * 0.12)
            edge.stroke()
        }
    }

    /// Where each photograph sits on the sheet.
    ///
    /// The outer margin is drawn at twice the gutter. A contact sheet whose edge photographs run
    /// to the paper's edge reads as a crop rather than a composition, and the frame's rebate would
    /// eat into them besides.
    static func cells(for size: MultiPhotoFrameCatalog.Size, in sheet: CGRect) -> [CGRect] {
        let columns = CGFloat(size.columns)
        let rows = CGFloat(size.rows)
        let gutter = min(sheet.width / columns, sheet.height / rows)
            * MultiPhotoFrameCatalog.gutterFraction
        let margin = gutter * 2

        let cellWidth = (sheet.width - margin * 2 - gutter * (columns - 1)) / columns
        let cellHeight = (sheet.height - margin * 2 - gutter * (rows - 1)) / rows
        guard cellWidth > 0, cellHeight > 0 else { return [] }

        var out: [CGRect] = []
        out.reserveCapacity(size.capacity)
        for row in 0..<size.rows {
            for column in 0..<size.columns {
                out.append(CGRect(
                    x: sheet.minX + margin + CGFloat(column) * (cellWidth + gutter),
                    y: sheet.minY + margin + CGFloat(row) * (cellHeight + gutter),
                    width: cellWidth, height: cellHeight
                ))
            }
        }
        return out
    }

    /// Aspect-fill into a cell — a near-square cell over a rectangular photograph takes the middle,
    /// which is the same crop the print makes.
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
