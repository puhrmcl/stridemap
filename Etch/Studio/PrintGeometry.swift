import Foundation
import CoreGraphics

/// The print-side geometry contract for an Etch Studio piece.
///
/// Everything the lab needs to trim a sheet correctly lives here, in one place: the finished
/// (trim) size, the bleed that runs off the edge, the safe inset no type may cross, and the
/// resolution the artwork is rendered at. The app previously had none of this — artwork was
/// authored at an arbitrary 1:1.62 aspect that matched no size on sale, and print scale was
/// derived from a nominal point size whose height varied with content.
///
/// Two aspects are supported, deliberately. Authoring for two shapes means two compositions to
/// perfect and two proof cycles; supporting six means six of each, and every extra shape is a
/// crop decision someone has to make by hand.
enum PrintAspect: String, CaseIterable, Identifiable, Sendable {
    /// 2:3 — the primary. Serves 8×12, 12×18, 16×24, 24×36.
    case twoThree
    /// 4:5 — the secondary. Serves 8×10, 16×20.
    case fourFive

    var id: String { rawValue }

    /// Width ÷ height, always < 1 (these are portrait shapes; landscape inverts at render time).
    var ratio: CGFloat {
        switch self {
        case .twoThree: return 2.0 / 3.0
        case .fourFive: return 4.0 / 5.0
        }
    }

    var label: String {
        switch self {
        case .twoThree: return "2:3"
        case .fourFive: return "4:5"
        }
    }
}

/// A finished print's physical geometry, in inches, plus the resolution it renders at.
struct PrintGeometry: Equatable, Sendable {

    /// Finished size after trimming, in inches (portrait).
    var trimWidth: Double
    var trimHeight: Double
    /// Extra artwork carried beyond the trim on every edge, so a trimming error never exposes
    /// white paper. Industry standard is 0.125″; providers that print borderless still expect it.
    var bleed: Double = 0.125
    /// No type or essential mark may sit inside this distance of the trim edge.
    var safeInset: Double = 0.25
    /// Dots per inch at trim. 300 is the print standard; below ~200 a viewer sees it.
    var dpi: Double = 300

    static let printStandardDPI: Double = 300
    /// Below this, an order should be refused rather than shipped soft.
    static let minimumAcceptableDPI: Double = 200

    /// The nearest supported aspect for this trim size.
    var aspect: PrintAspect {
        let r = trimWidth / trimHeight
        return abs(r - Double(PrintAspect.twoThree.ratio)) <= abs(r - Double(PrintAspect.fourFive.ratio))
            ? .twoThree : .fourFive
    }

    /// Pixel size of the artwork at trim — what the composition is rendered to.
    var trimPixels: CGSize {
        CGSize(width: trimWidth * dpi, height: trimHeight * dpi)
    }

    /// Pixel size including bleed — what is uploaded to the print provider.
    var bleedPixels: CGSize {
        CGSize(width: (trimWidth + bleed * 2) * dpi, height: (trimHeight + bleed * 2) * dpi)
    }

    /// Bleed expressed in pixels, for insetting the trim box inside the uploaded canvas.
    var bleedPixelInset: CGFloat { CGFloat(bleed * dpi) }

    /// The safe box in pixels, relative to the bleed canvas origin.
    var safeRectInBleedCanvas: CGRect {
        let inset = CGFloat((bleed + safeInset) * dpi)
        let full = bleedPixels
        return CGRect(x: inset, y: inset,
                      width: full.width - inset * 2, height: full.height - inset * 2)
    }

    /// The DPI actually achieved if the artwork can only be rendered to `longEdgePixels`.
    /// Used to refuse an order rather than ship a soft print.
    func achievedDPI(longEdgePixels: CGFloat) -> Double {
        let longEdgeInches = max(trimWidth, trimHeight)
        guard longEdgeInches > 0 else { return 0 }
        return Double(longEdgePixels) / longEdgeInches
    }

    /// Whether a render of this pixel height clears the quality floor for this size.
    func isAcceptable(longEdgePixels: CGFloat) -> Bool {
        achievedDPI(longEdgePixels: longEdgePixels) >= Self.minimumAcceptableDPI
    }

    /// A human line for the order screen: `16 × 24″ · 300 DPI · 2:3`.
    var summary: String {
        "\(Int(trimWidth)) × \(Int(trimHeight))″ · \(Int(dpi)) DPI · \(aspect.label)"
    }
}
