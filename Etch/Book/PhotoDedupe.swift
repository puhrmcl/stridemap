import UIKit

/// Perceptual near-duplicate detection for the book's photo curation — ten finish-line
/// burst shots should not become ten book tiles. Difference-hash over a 9×8 grayscale
/// thumbnail: each bit records "this pixel is brighter than its right neighbour", which
/// survives resizing, mild exposure shifts and JPEG noise while separating genuinely
/// different pictures. Nothing here decides anything: the photo sheet reports what it
/// found and the reader keeps the last word.
enum PhotoDedupe {

    /// The 64-bit difference-hash of an image; nil when it can't be rasterised.
    static func hash(_ image: UIImage) -> UInt64? {
        let width = 9, height = 8
        guard let cgImage = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }

        var bits: UInt64 = 0
        var bit: UInt64 = 0
        for row in 0..<height {
            for col in 0..<(width - 1) {
                if pixels[row * width + col] > pixels[row * width + col + 1] {
                    bits |= 1 << bit
                }
                bit += 1
            }
        }
        return bits
    }

    static func distance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    /// Groups of near-identical references (Hamming distance ≤ `threshold`), in input order,
    /// each group led by the photo that appeared first. Only real groups — two or more —
    /// come back.
    static func clusters(references: [String], threshold: Int = 10) async -> [[String]] {
        var hashes: [(reference: String, hash: UInt64)] = []
        for reference in references {
            guard let image = await PhotoLibrary.image(for: reference,
                                                       targetSize: CGSize(width: 96, height: 96)),
                  let value = hash(image) else { continue }
            hashes.append((reference, value))
        }

        var used = Set<Int>()
        var groups: [[String]] = []
        for i in hashes.indices where !used.contains(i) {
            var group = [hashes[i].reference]
            for j in hashes.indices where j > i && !used.contains(j) {
                if distance(hashes[i].hash, hashes[j].hash) <= threshold {
                    group.append(hashes[j].reference)
                    used.insert(j)
                }
            }
            if group.count > 1 {
                used.insert(i)
                groups.append(group)
            }
        }
        return groups
    }
}
