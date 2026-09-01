import CoreGraphics

/// Traces topographic contour lines through an `ElevationField` using marching squares. Output
/// segments are in normalized space — x and y each in 0…1, where (0,0) is the field's
/// north-west corner — so the caller scales them to any panel size.
enum ContourExtractor {

    /// A single line segment of a contour, in normalized 0…1 space.
    struct Segment { let a: CGPoint; let b: CGPoint }

    /// Extracts `levelCount` evenly spaced contour levels between the field's min and max
    /// elevation. Returns all segments flattened; density naturally follows the terrain's relief.
    static func segments(for field: ElevationField, levelCount: Int = 22) -> [Segment] {
        let span = field.maxElevation - field.minElevation
        guard span > 1, field.rows > 1, field.cols > 1 else { return [] }

        var result: [Segment] = []
        let stepX = 1.0 / Double(field.cols - 1)
        let stepY = 1.0 / Double(field.rows - 1)

        for l in 1..<levelCount {
            let level = field.minElevation + span * Double(l) / Double(levelCount)
            for r in 0..<(field.rows - 1) {
                for c in 0..<(field.cols - 1) {
                    let tl = field.value(row: r, col: c)
                    let tr = field.value(row: r, col: c + 1)
                    let br = field.value(row: r + 1, col: c + 1)
                    let bl = field.value(row: r + 1, col: c)

                    var idx = 0
                    if tl >= level { idx |= 8 }
                    if tr >= level { idx |= 4 }
                    if br >= level { idx |= 2 }
                    if bl >= level { idx |= 1 }
                    if idx == 0 || idx == 15 { continue }

                    // Edge crossing points, interpolated, in normalized space.
                    let cx = Double(c) * stepX, cy = Double(r) * stepY
                    func lerp(_ a: Double, _ b: Double) -> Double {
                        let d = b - a
                        return abs(d) < 1e-9 ? 0.5 : (level - a) / d
                    }
                    let top = CGPoint(x: cx + lerp(tl, tr) * stepX, y: cy)
                    let bottom = CGPoint(x: cx + lerp(bl, br) * stepX, y: cy + stepY)
                    let left = CGPoint(x: cx, y: cy + lerp(tl, bl) * stepY)
                    let right = CGPoint(x: cx + stepX, y: cy + lerp(tr, br) * stepY)

                    switch idx {
                    case 1, 14: result.append(Segment(a: left, b: bottom))
                    case 2, 13: result.append(Segment(a: bottom, b: right))
                    case 3, 12: result.append(Segment(a: left, b: right))
                    case 4, 11: result.append(Segment(a: top, b: right))
                    case 6, 9:  result.append(Segment(a: top, b: bottom))
                    case 7, 8:  result.append(Segment(a: top, b: left))
                    case 5:     // saddle
                        result.append(Segment(a: top, b: left))
                        result.append(Segment(a: bottom, b: right))
                    case 10:    // saddle
                        result.append(Segment(a: top, b: right))
                        result.append(Segment(a: bottom, b: left))
                    default: break
                    }
                }
            }
        }
        return result
    }
}
