import UIKit
import SwiftUI
import CoreLocation
import MapLibre

/// Renders the map panel from Etch's own basemap instead of Apple's.
///
/// `MKMapSnapshotter` produces a beautiful image the business cannot sell. This produces the same
/// shape of image — a `UIImage` at a size, framed on a route — from OpenStreetMap data served by
/// the fulfilment worker and styled by `EtchCartography`, which Etch may print.
///
/// One honest limit, stated here because it decides what the catalogue can offer: **the Satellite
/// edition cannot be replaced this way.** OpenStreetMap is vector data — roads, water, buildings —
/// and carries no aerial imagery. Replacing Satellite means licensing imagery from someone, which
/// is a separate purchase and a separate decision. The four street and standard kinds are covered;
/// Satellite stays display-only until that decision is made.
@MainActor
enum EtchMapSnapshotter {

    /// Whether the basemap is live.
    ///
    /// Served rather than compiled, because the gate is an *operational* fact — whether the
    /// archive is in the bucket — not a property of the build. Until it flips, map editions keep
    /// rendering from Apple and keep their honest "display only" mark in the shop. The alternative
    /// is worse than waiting: a style pointed at a missing archive renders a blank coloured
    /// rectangle, and a poster that silently loses its city is a defect a customer finds, not one
    /// we do.
    static var isAvailable: Bool {
        EtchConfig.current.basemapReady
            // CI's screenshot harness forces the basemap on so the previews photograph Etch's
            // own cartography deterministically, instead of racing the config fetch. A missing
            // or broken archive still falls back — the blank-detection below owns that.
            || ProcessInfo.processInfo.environment["ETCH_PREVIEW_BASEMAP"] == "1"
    }

    /// Whether this edition's panel can come from our own cartography.
    static func canRender(_ edition: StudioEdition) -> Bool {
        guard isAvailable, !isTripped, let kind = edition.mapKind else { return false }
        return kind != .satellite
    }

    // MARK: The blank-map circuit breaker

    /// Consecutive renders that came back with nothing on them.
    private static var blankRuns = 0

    /// After this many, stop trying for the rest of the session.
    ///
    /// One blank render is ambiguous — a route across open water or featureless desert genuinely
    /// has no features to draw, and falling back to Apple for that single poster is the right
    /// answer anyway. Three different routes coming back blank is not terrain, it is the archive:
    /// missing, mis-keyed, or a worker that is down. At that point every further attempt is a
    /// MapLibre snapshot that will time out before failing, and the editor would crawl.
    private static let blankLimit = 3

    private static var isTripped: Bool { blankRuns >= blankLimit }

    /// Whether a snapshot has nothing on it but its own background.
    ///
    /// This is the guard that was missing, and its absence was a real defect: MapLibre renders the
    /// style's background layer and returns a **successful** image when every tile request fails,
    /// so a nil-check never fires and the poster silently loses its city. A customer would find
    /// that, not us.
    ///
    /// The test is exact uniformity. The image is averaged down to a small grid — averaging rather
    /// than nearest-neighbour sampling, so a single hairline road still perturbs the cell it
    /// crosses instead of being stepped over — and if every cell is byte-identical then nothing
    /// but the background drew. Any real content at all, one road or one lake edge, breaks it.
    /// Exact comparison is the conservative direction: it errs toward *trusting* the render, and
    /// the cost of a wrong "blank" is only a fallback to Apple.
    private static func isBlank(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        let side = 96
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return true }

        let first = (pixels[0], pixels[1], pixels[2])
        for index in stride(from: 4, to: pixels.count, by: 4) {
            if pixels[index] != first.0 || pixels[index + 1] != first.1
                || pixels[index + 2] != first.2 { return false }
        }
        return true
    }

    /// A snapshot and the frame it was taken in.
    ///
    /// The frame travels with the image because the caller has to draw the route on top, and a
    /// route drawn through a *different* projection than the map beneath it is off by metres at
    /// the edges — the single most visible way this could go wrong. `MKMapSnapshotter` solves it
    /// by handing back a `point(for:)`; MapLibre does not, so Etch computes the frame itself and
    /// both the camera and the overlay read from that one answer.
    struct Snapshot {
        let image: UIImage
        let frame: Frame
    }

    /// A Web Mercator window, already fitted to the panel's shape.
    ///
    /// Fitting happens *here* rather than inside MapLibre. Handing MapLibre a bounding box of a
    /// different aspect than the image makes it add margin on one axis to fit — a reasonable
    /// thing to do, and it would silently invalidate any projection computed from the box we
    /// passed in. Expanding the box to the panel's aspect first means the map fills the frame
    /// exactly and a plain linear projection is then correct.
    struct Frame {
        let minX: Double, maxX: Double
        let minY: Double, maxY: Double

        var bounds: MLNCoordinateBounds {
            MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: Frame.latitude(y: maxY),
                                           longitude: Frame.longitude(x: minX)),
                ne: CLLocationCoordinate2D(latitude: Frame.latitude(y: minY),
                                           longitude: Frame.longitude(x: maxX))
            )
        }

        /// Where a coordinate lands in an image of this size.
        func point(for coordinate: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
            let x = Frame.x(longitude: coordinate.longitude)
            let y = Frame.y(latitude: coordinate.latitude)
            return CGPoint(x: (x - minX) / (maxX - minX) * size.width,
                           y: (y - minY) / (maxY - minY) * size.height)
        }

        // Web Mercator, normalised to the unit square. y grows downward, as image rows do.
        static func x(longitude: Double) -> Double { (longitude + 180) / 360 }
        static func y(latitude: Double) -> Double {
            let clamped = min(max(latitude, -85.05112878), 85.05112878)
            let radians = clamped * .pi / 180
            return (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
        }
        static func longitude(x: Double) -> Double { x * 360 - 180 }
        static func latitude(y: Double) -> Double {
            let n = .pi - 2 * .pi * y
            return 180 / .pi * atan(0.5 * (exp(n) - exp(-n)))
        }

        /// The frame a route sits in: its Mercator extent, padded, then grown to the panel's
        /// aspect ratio.
        ///
        /// Padding is proportional rather than a fixed degree count — a 3 km loop and a marathon
        /// want the same *visual* margin, and a constant would swallow one and hairline the
        /// other. The floor keeps an out-and-back along a single street from framing to a few
        /// metres of tarmac.
        static func fitting(_ coordinates: [CLLocationCoordinate2D],
                            aspect: Double, padding: Double = 0.16) -> Frame {
            var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0
            for coordinate in coordinates {
                let px = x(longitude: coordinate.longitude)
                let py = y(latitude: coordinate.latitude)
                minX = min(minX, px); maxX = max(maxX, px)
                minY = min(minY, py); maxY = max(maxY, py)
            }
            var width = max(maxX - minX, 1e-6)
            var height = max(maxY - minY, 1e-6)
            let centreX = (minX + maxX) / 2
            let centreY = (minY + maxY) / 2

            width *= (1 + padding * 2)
            height *= (1 + padding * 2)
            // A tiny route would otherwise frame to a car park.
            width = max(width, 1.0 / Double(1 << 17))
            height = max(height, 1.0 / Double(1 << 17))

            // Grow the short axis so the window matches the panel; never shrink, or the route
            // would be cropped by the fitting itself.
            if width / height < aspect {
                width = height * aspect
            } else {
                height = width / aspect
            }
            return Frame(minX: centreX - width / 2, maxX: centreX + width / 2,
                         minY: centreY - height / 2, maxY: centreY + height / 2)
        }
    }

    /// Snapshots the basemap for a route.
    ///
    /// - Returns: the image and its frame, or nil if the snapshot failed — callers fall back to
    ///   Apple's snapshotter, so a tile outage costs a poster its *printability*, never its
    ///   existence.
    /// - Parameter ground: the poster's paper. It becomes the style's land colour, so the panel
    ///   comes back already on the sheet rather than on a tone of its own.
    static func snapshot(for coordinates: [CLLocationCoordinate2D],
                         size: CGSize, scale: CGFloat,
                         edition: StudioEdition, ground: Color? = nil) async -> Snapshot? {
        guard canRender(edition), coordinates.count > 1, size.width > 0, size.height > 0 else {
            return nil
        }
        guard let styleURL = styleFile(for: edition, ground: ground) else { return nil }

        let frame = Frame.fitting(coordinates, aspect: Double(size.width / size.height))
        let options = MLNMapSnapshotOptions(styleURL: styleURL,
                                            camera: MLNMapCamera(),
                                            size: size)
        options.scale = scale
        options.coordinateBounds = frame.bounds

        let snapshotter = MLNMapSnapshotter(options: options)
        let image: UIImage? = await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, error in
                if let error { print("basemap snapshot failed: \(error.localizedDescription)") }
                continuation.resume(returning: snapshot?.image)
            }
        }
        guard let image else {
            blankRuns += 1
            return nil
        }
        // A returned image is not yet a map. Prove something drew on it before handing back a
        // panel this poster could be *sold* on the strength of.
        guard !isBlank(image) else {
            blankRuns += 1
            if isTripped {
                print("basemap: \(blankLimit) blank renders — falling back to Apple for this session")
            }
            return nil
        }
        blankRuns = 0
        return Snapshot(image: image, frame: frame)
    }

    // MARK: The style on disk

    /// MapLibre takes a style by URL, so the generated document is written to a file.
    ///
    /// Cached per edition *and paper*: the Studio editor re-renders on every option change,
    /// including every keystroke in a title field, and serialising the same JSON on each of those
    /// would be work nobody asked for. The paper is part of the key because it is part of the
    /// style — the same edition on two grounds is two different maps, and keying on the edition
    /// alone would serve the first paper's map for the second one's poster.
    private static var styleFiles: [String: URL] = [:]

    private static func styleFile(for edition: StudioEdition, ground: Color?) -> URL? {
        let key = "\(edition.id.rawValue)-\(ground?.hexString ?? "authored")"
        if let existing = styleFiles[key],
           FileManager.default.fileExists(atPath: existing.path) { return existing }
        guard let data = EtchCartography.styleJSON(for: edition, ground: ground) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("etch-style-\(key).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        styleFiles[key] = url
        return url
    }
}
