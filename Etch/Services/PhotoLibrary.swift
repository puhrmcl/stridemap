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

    /// Requests read access, returning whether we ended up authorized (or limited).
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
                if isNear(location, run: run) { result.append(asset.localIdentifier) }
            } else {
                // No photo GPS, or route-less run → time-only match.
                result.append(asset.localIdentifier)
            }
        }
        return result
    }

    /// Whether a coordinate falls within the run's bounding box, expanded by ~600 m.
    private static func isNear(_ location: CLLocation, run: Run) -> Bool {
        let margin = 0.006
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        return lat >= run.minLatitude - margin && lat <= run.maxLatitude + margin
            && lon >= run.minLongitude - margin && lon <= run.maxLongitude + margin
    }

    // MARK: Image loading

    /// Loads an image for an asset identifier at (roughly) the target size. Returns nil if the
    /// asset no longer exists (e.g. deleted from the library).
    static func image(for identifier: String, targetSize: CGSize) async -> UIImage? {
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
}
