import UIKit
import ImageIO

/// The proofs behind the Bag: a small JPEG of the exact file each cart line uploaded for print.
///
/// A bag line was a title and a price, which asks the customer to pay for something they cannot
/// see. The proof is made from the *uploaded print file itself* — not from a preview render that
/// might drift from it — so what the Bag shows is what the lab receives. Keyed by the line's
/// asset id and swept with the cart, so a removed line's proof does not outlive it.
enum ProofStore {

    private static let maxPixel: CGFloat = 700

    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let url = base.appendingPathComponent("BagProofs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func url(for assetID: String) -> URL? {
        directory?.appendingPathComponent("\(assetID).jpg")
    }

    static func image(for assetID: String) -> UIImage? {
        guard let url = url(for: assetID) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func remove(_ assetID: String) {
        guard let url = url(for: assetID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes every proof whose asset is no longer in the bag — run at startup so a failed
    /// add or a crashed session cannot leak files.
    static func sweep(keeping assetIDs: Set<String>) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil)
        else { return }
        for file in files where !assetIDs.contains(file.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Makes and stores the proof from the print file, off the calling thread.
    ///
    /// The file can be a 78-megapixel PNG or a whole book as PDF, so nothing here materialises it
    /// at full size: images go through ImageIO's downsampling thumbnailer, PDFs render their
    /// cover page into a small context. A failure stores nothing — the Bag shows a quiet
    /// placeholder rather than the add failing over its own receipt.
    static func makeProof(from fileURL: URL, contentType: String, assetID: String) async {
        guard let destination = url(for: assetID) else { return }
        let proof: UIImage? = await Task.detached(priority: .utility) {
            contentType == "application/pdf"
                ? pdfCover(fileURL)
                : downsampled(fileURL)
        }.value
        guard let data = proof?.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: destination, options: .atomic)
    }

    private static func downsampled(_ fileURL: URL) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: thumb)
    }

    private static func pdfCover(_ fileURL: URL) -> UIImage? {
        guard let document = CGPDFDocument(fileURL as CFURL),
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = maxPixel / max(box.width, box.height)
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            context.cgContext.translateBy(x: -box.minX, y: -box.minY)
            context.cgContext.drawPDFPage(page)
        }
    }
}
