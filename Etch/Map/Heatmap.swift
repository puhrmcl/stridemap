import UIKit
import MapKit

/// Renders an additive density heatmap image for a set of map points within a viewport.
///
/// Every point stamps a soft Gaussian blob of a *fixed screen radius*, so overlapping runs
/// accumulate into brighter areas — and crucially, a place you run stays visible even when
/// zoomed all the way out (its points collapse into one bright dot rather than vanishing, the
/// way thin polylines do). The result is colourised blue → cyan → white and returned as a
/// transparent image to lay over the base map.
enum Heatmap {

    /// - Parameters:
    ///   - points: projected map points to accumulate (already decimated by the caller).
    ///   - visible: the map's current `visibleMapRect`.
    ///   - size: the map view's size in points.
    ///   - downsample: buffer resolution divisor (2 = half-res, upscaled for a smooth glow).
    static func image(points: [MKMapPoint], visible: MKMapRect, size: CGSize, downsample: CGFloat = 2) -> UIImage? {
        guard size.width > 1, size.height > 1, !points.isEmpty,
              !visible.isNull, visible.size.width > 0, visible.size.height > 0 else { return nil }

        let width = max(1, Int(size.width / downsample))
        let height = max(1, Int(size.height / downsample))
        var buffer = [Float](repeating: 0, count: width * height)

        // Fixed-radius Gaussian stamp (in buffer pixels).
        let radius = 6
        let sigma = Float(radius) / 2
        let side = 2 * radius + 1
        var kernel = [Float](repeating: 0, count: side * side)
        for dy in -radius...radius {
            for dx in -radius...radius {
                kernel[(dy + radius) * side + (dx + radius)] =
                    exp(-Float(dx * dx + dy * dy) / (2 * sigma * sigma))
            }
        }

        let sx = Double(width) / visible.size.width
        let sy = Double(height) / visible.size.height

        for point in points {
            guard visible.contains(point) else { continue }
            let bx = Int((point.x - visible.minX) * sx)
            let by = Int((point.y - visible.minY) * sy)
            var ki = 0
            for dy in -radius...radius {
                let y = by + dy
                if y < 0 || y >= height { ki += side; continue }
                let rowBase = y * width
                for dx in -radius...radius {
                    let x = bx + dx
                    if x >= 0 && x < width { buffer[rowBase + x] += kernel[ki] }
                    ki += 1
                }
            }
        }

        let maxValue = buffer.max() ?? 0
        guard maxValue > 0 else { return nil }
        let invMax = 1 / maxValue

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let t = min(1, (buffer[i] * invMax).squareRoot())   // sqrt spreads the low end
            guard t > 0.001 else { continue }
            let (r, g, b) = rampColor(t)
            let alpha = min(1, t * 1.7)
            let o = i * 4
            pixels[o]     = UInt8(r * alpha)   // premultiplied
            pixels[o + 1] = UInt8(g * alpha)
            pixels[o + 2] = UInt8(b * alpha)
            pixels[o + 3] = UInt8(alpha * 255)
        }

        return pixels.withUnsafeMutableBytes { raw -> UIImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }
    }

    /// Blue → cyan → white ramp (0–255 components), matching the Etch palette's cool glow.
    private static func rampColor(_ t: Float) -> (Float, Float, Float) {
        if t < 0.5 {
            let f = t / 0.5
            return (20 + (60 - 20) * f, 90 + (200 - 90) * f, 230 + (255 - 230) * f)
        } else {
            let f = (t - 0.5) / 0.5
            return (60 + (255 - 60) * f, 200 + (255 - 200) * f, 255)
        }
    }
}
