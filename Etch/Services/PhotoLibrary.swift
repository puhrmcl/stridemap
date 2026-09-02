import Photos
import UIKit
import CoreLocation

/// Bridges the Photos library for run photos: permission, auto-matching photos to a run by
/// time + location, and loading images by asset identifier. Photo references are stored on
/// `Run.photoReferences` as `PHAsset.localIdentifier` strings.
@MainActor
enum PhotoLibrary {

    // MARK: Authorization

    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var isAuthorized: Bool {
        status == .authorized || status == .limited
    }

    /// Requests library access. Photos only offers `.addOnly` or `.readWrite` — there is
    /// no read-only level — so we request `.readWrite` and never write. The Add usage
    /// string in Info.plist is required for that request even though Etch does not save.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return granted == .authorized || granted == .limited
        }
        return isAuthorized
    }

    // MARK: Auto-match

    /// Photos taken during the run (± a few minutes) and near its route. Runs without a route
    /// fall back to a time-only match — a win for route-less Nike runs, which otherwise have
    /// no imagery at all.
    static func matchingIdentifiers(for run: Run) -> [String] {
        guard isAuthorized else { return [] }

        let pad: TimeInterval = 5 * 60
        let start = run.startDate.addingTimeInterval(-pad)
        let end = run.startDate.addingTimeInterval(TimeInterval(run.elapsedTime) + pad)

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: options)
        let hasRoute = run.summaryPolyline.isEmpty == false
        var result: [String] = []
        assets.enumerateObjects { asset, _, _ in
            if let location = asset.location, hasRoute {
                if isNear(location.coordinate, run: run) { result.append(asset.localIdentifier) }
            } else {
                // No photo GPS, or route-less run → time-only match.
                result.append(asset.localIdentifier)
            }
        }
        return result
    }

    /// Whether a coordinate falls within the run's bounding box, expanded by ~600 m.
    private static func isNear(_ coordinate: CLLocationCoordinate2D, run: Run) -> Bool {
        let margin = 0.006
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        return lat >= run.minLatitude - margin && lat <= run.maxLatitude + margin
            && lon >= run.minLongitude - margin && lon <= run.maxLongitude + margin
    }

    // MARK: Bulk match (all runs)

    /// Lightweight snapshot of a library image: identifier, capture date, and location.
    struct AssetInfo {
        let id: String
        let date: Date
        let coordinate: CLLocationCoordinate2D?
    }

    /// One pass over the library's images (metadata only), sorted by capture date — the input
    /// to `match(run:in:)` so a bulk scan does a single library read instead of one per run.
    static func allImageAssets() -> [AssetInfo] {
        guard isAuthorized else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        var result: [AssetInfo] = []
        result.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            result.append(AssetInfo(id: asset.localIdentifier, date: date, coordinate: asset.location?.coordinate))
        }
        return result
    }

    /// Of the given asset identifiers, which are screenshots (UI captures) — so a photo wall or
    /// print can skip them and stay to real photography. One batched metadata fetch.
    static func screenshotIdentifiers(among identifiers: [String]) -> Set<String> {
        // Unguarded, this was the one PHAsset fetch left that could put the permission sheet
        // over a CI screenshot — the Photo Wall calls it on appear.
        guard !identifiers.isEmpty, !isPreview else { return [] }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var out: Set<String> = []
        assets.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) { out.insert(asset.localIdentifier) }
        }
        return out
    }

    /// Matches one run against a pre-sorted asset snapshot via binary search on the time
    /// window, then the same location/time rules as the single-run match.
    static func match(run: Run, in assets: [AssetInfo]) -> [String] {
        guard !assets.isEmpty else { return [] }
        let pad: TimeInterval = 5 * 60
        let start = run.startDate.addingTimeInterval(-pad)
        let end = run.startDate.addingTimeInterval(TimeInterval(run.elapsedTime) + pad)

        // First index with date >= start.
        var lo = 0, hi = assets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if assets[mid].date < start { lo = mid + 1 } else { hi = mid }
        }

        let hasRoute = run.summaryPolyline.isEmpty == false
        var result: [String] = []
        var i = lo
        while i < assets.count, assets[i].date <= end {
            let asset = assets[i]
            if let coordinate = asset.coordinate, hasRoute {
                if isNear(coordinate, run: run) { result.append(asset.id) }
            } else {
                result.append(asset.id)
            }
            i += 1
        }
        return result
    }

    // MARK: Image loading

    /// True while CI is photographing a screen. The harness seeds photo references that point at
    /// nothing, and the first `PHAsset` fetch against an undetermined authorization puts the
    /// system's "would like full access to your Photo Library" sheet over whatever was being
    /// photographed — which is how b507's first pair of screenshots came back. Nothing is being
    /// suppressed here that a simulator could have loaded: its library is empty either way.
    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["ETCH_PREVIEW"]?.isEmpty == false
    }

    /// The photograph CI sees: a muted tone with a soft highlight, derived from the identifier
    /// so every seeded reference keeps its own stable "photo" across runs.
    private static func previewStandIn(for identifier: String, size: CGSize) -> UIImage {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in identifier.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        let hue = CGFloat(hash % 360) / 360
        let side = CGSize(width: max(size.width, 60), height: max(size.height, 60))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: side, format: format).image { context in
            UIColor(hue: hue, saturation: 0.22, brightness: 0.74, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: side))
            UIColor(hue: hue, saturation: 0.30, brightness: 0.88, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: side.width * 0.58, y: side.height * 0.10,
                                        width: side.width * 0.26, height: side.width * 0.26)).fill()
            UIColor(hue: hue, saturation: 0.34, brightness: 0.52, alpha: 1).setFill()
            let ridge = UIBezierPath()
            ridge.move(to: CGPoint(x: 0, y: side.height))
            ridge.addLine(to: CGPoint(x: side.width * 0.38, y: side.height * 0.55))
            ridge.addLine(to: CGPoint(x: side.width * 0.62, y: side.height * 0.78))
            ridge.addLine(to: CGPoint(x: side.width, y: side.height * 0.45))
            ridge.addLine(to: CGPoint(x: side.width, y: side.height))
            ridge.close()
            ridge.fill()
        }
    }

    /// Loads an image for an asset identifier at (roughly) the target size. Returns nil if the
    /// asset no longer exists (e.g. deleted from the library).
    static func image(for identifier: String, targetSize: CGSize) async -> UIImage? {
        // A stand-in rather than nil: the screens being photographed lay out photography, and a
        // grid of spinners can't be judged. Deterministic per identifier, so shots are stable.
        guard !isPreview else { return previewStandIn(for: identifier, size: targetSize) }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat   // single callback
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast
            PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Loads the full-resolution image for an asset, for sharing. Nil if the asset is gone.
    static func fullImage(for identifier: String) async -> UIImage? {
        guard !isPreview else { return nil }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true    // fetch from iCloud if needed
            options.resizeMode = .none
            PHImageManager.default().requestImage(
                for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .default, options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
