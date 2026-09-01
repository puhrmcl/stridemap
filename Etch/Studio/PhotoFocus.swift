import UIKit
import Vision

/// Finds the visual centre of a photo — where the subject actually is — so gallery cells crop
/// toward faces and subjects instead of the geometric middle. Attention-based saliency covers
/// people, pets, medals, and scenery alike; when Vision finds nothing salient the centre is the
/// honest fallback. Cached per photo id, so each photo is analysed once, ever.
@MainActor
enum PhotoFocus {
    private static var cache: [String: CGPoint] = [:]
    private static let center = CGPoint(x: 0.5, y: 0.5)

    /// The focus point for a photo, normalized to the image with a top-left origin.
    static func focusPoint(id: String, image: UIImage) async -> CGPoint {
        if let cached = cache[id] { return cached }
        guard let cg = image.cgImage else { return center }
        let point = await Task.detached(priority: .utility) { () -> CGPoint in
            let fallback = CGPoint(x: 0.5, y: 0.5)
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { return fallback }
            guard let observation = request.results?.first,
                  let salient = observation.salientObjects, !salient.isEmpty else {
                return fallback
            }
            // One box around everything salient — a group photo focuses on the group.
            var box = salient[0].boundingBox
            for object in salient.dropFirst() { box = box.union(object.boundingBox) }
            // Vision's normalized rects use a bottom-left origin; the composition wants top-left.
            return CGPoint(x: box.midX, y: 1 - box.midY)
        }.value
        cache[id] = point
        return point
    }
}
