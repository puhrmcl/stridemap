import Foundation
import ImageIO
import PDFKit
import SwiftUI
import UIKit

/// The mockup sitting next to a bag line — the piece as Studio already draws it, frozen to disk
/// so a killed app still has something to show when the bag reopens.
///
/// The print file behind a line is tens of megabytes and is deleted after upload, so the bag
/// cannot reopen it. This keeps a small JPEG of the same object the print shop hung on the wall:
/// the composition itself for a Fine-Art sheet, inside `FramedPrintMockup` / `HangerPrintMockup`
/// / `MedalFrameMockup` when that is the product. Shopify's catalogue image is never consulted —
/// that would be a stock frame, not this artwork.
@MainActor
enum BagPreview {

    /// Long edge of the downsampled artwork fed into the mockup. Comfortably sharp in a 68pt
    /// slot at 3×, and small enough that ImageIO never materialises a 24×36 sheet.
    private static let rasterLongEdge: CGFloat = 720
    private static var memory: [String: UIImage] = [:]

    // MARK: Capture

    /// Dresses the uploaded file as the product the line is for. Nil only when the file cannot
    /// be read at all — a bagged line still checks out if this returns nil; it just stays text.
    static func make(from url: URL,
                     productHandle: String,
                     finishAttribute: String,
                     mountAttribute: String,
                     contentType: String,
                     pixels: CGSize) -> UIImage? {
        guard let artwork = raster(url, contentType: contentType) else { return nil }
        return mockup(artwork: artwork,
                      productHandle: productHandle,
                      finishAttribute: finishAttribute,
                      mountAttribute: mountAttribute,
                      pixels: pixels)
    }

    /// The Studio mockup for an already-rasterised composition. Shared with the preview harness,
    /// which has a screen-scale render rather than a print file.
    static func mockup(artwork: UIImage,
                       productHandle: String,
                       finishAttribute: String,
                       mountAttribute: String,
                       pixels: CGSize) -> UIImage {
        let kind = dressing(handle: productHandle, finish: finishAttribute, mount: mountAttribute)
        let strip = hangerStripHeight(pixels: pixels)
        let canvas = canvasSize(for: artwork, kind: kind, stripHeight: strip)
        let renderer = ImageRenderer(content:
            DressedPiece(artwork: artwork, kind: kind, stripHeight: strip)
                .padding(16)
                .frame(width: canvas.width, height: canvas.height)
                .background(Theme.Palette.bone)
        )
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: canvas.width, height: canvas.height)
        return renderer.uiImage ?? artwork
    }

    // MARK: Persistence

    static func store(_ image: UIImage, for assetID: String) {
        memory[assetID] = image
        guard let data = image.jpegData(compressionQuality: 0.84) else { return }
        try? data.write(to: fileURL(for: assetID), options: .atomic)
    }

    static func image(for assetID: String) -> UIImage? {
        if let cached = memory[assetID] { return cached }
        guard let image = UIImage(contentsOfFile: fileURL(for: assetID).path) else { return nil }
        memory[assetID] = image
        return image
    }

    static func remove(assetID: String) {
        memory.removeValue(forKey: assetID)
        try? FileManager.default.removeItem(at: fileURL(for: assetID))
    }

    static func removeAll() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Drops files that no longer belong to a live line — bags expire, and a crash between
    /// persist and cleanup must not leave orphan JPEGs accumulating.
    static func keep(_ assetIDs: Set<String>) {
        memory = memory.filter { assetIDs.contains($0.key) }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            let id = file.deletingPathExtension().lastPathComponent
            if !assetIDs.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: Raster

    /// A thumbnail of the print file. ImageIO decodes at the requested size, so a 10,800px PNG
    /// never lands in memory as one bitmap — which is the same constraint the banded writer
    /// exists to respect.
    private static func raster(_ url: URL, contentType: String) -> UIImage? {
        if contentType.contains("pdf") || url.pathExtension.lowercased() == "pdf" {
            return pdfCover(at: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: rasterLongEdge,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func pdfCover(at url: URL) -> UIImage? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let longest = max(bounds.width, bounds.height)
        guard longest > 0 else { return nil }
        let scale = rasterLongEdge / longest
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    // MARK: Dressing

    private static func dressing(handle: String, finish: String, mount: String) -> BagPreviewKind {
        switch handle {
        case PrintProduct.framed.shopifyHandle,
             MultiPhotoFrameCatalog.shopifyHandle:
            let frame = FrameFinish.allCases.first { $0.prodigiAttribute == finish } ?? .black
            return .framed(moulding: Color(hex: frame.mouldingHex) ?? .black,
                           grain: frame == .natural)
        case PrintProduct.hanger.shopifyHandle:
            let wood = HangerFinish.allCases.first { $0.prodigiAttribute == finish } ?? .natural
            return .hanger(wood: Color(hex: wood.woodHex) ?? .brown)
        case MedalFrameCatalog.shopifyHandle:
            return .medal(frame: finish.isEmpty ? "black" : finish,
                          mount: mount.isEmpty ? "Black" : mount)
        default:
            // Fine-Art Print, the year book cover, map prints sold as a sheet.
            return .sheet
        }
    }

    private static func hangerStripHeight(pixels: CGSize) -> CGFloat {
        let inches = pixels.height > 0 ? pixels.height / 300 : 36
        let cover = PosterHangerCatalog.hangerCoverMM / 25.4
        return max(3, 260 * (cover / max(inches, 1)))
    }

    private static func canvasSize(for artwork: UIImage, kind: BagPreviewKind, stripHeight: CGFloat) -> CGSize {
        let aspect = artwork.size.width / max(artwork.size.height, 1)
        let artHeight: CGFloat = 260
        let artWidth = artHeight * aspect
        let pad: CGFloat = 32
        switch kind {
        case .sheet:
            return CGSize(width: artWidth + pad, height: artHeight + pad)
        case .framed:
            return CGSize(width: artWidth + pad + 24, height: artHeight + pad + 24)
        case .hanger:
            return CGSize(width: artWidth + pad, height: artHeight + pad + stripHeight * 2)
        case .medal:
            return CGSize(width: 280, height: 220)
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("etch-bag-previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func fileURL(for assetID: String) -> URL {
        directory.appendingPathComponent("\(assetID).jpg")
    }
}

/// How the uploaded sheet is presented as an object. File-level so the snapshot view can
/// switch on it without reaching into `BagPreview`.
fileprivate enum BagPreviewKind {
    case sheet
    case framed(moulding: Color, grain: Bool)
    case hanger(wood: Color)
    case medal(frame: String, mount: String)
}

/// One piece, dressed as the object that ships. The same views the print shop hangs on the wall.
private struct DressedPiece: View {
    let artwork: UIImage
    let kind: BagPreviewKind
    let stripHeight: CGFloat

    var body: some View {
        switch kind {
        case .sheet:
            LooseSheetMockup {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit)
            }
        case .framed(let moulding, let grain):
            FramedPrintMockup(moulding: moulding, hasGrain: grain, mouldingWidth: 11) {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit)
            }
        case .hanger(let wood):
            HangerPrintMockup(wood: wood, stripHeight: stripHeight) {
                Image(uiImage: artwork).resizable().aspectRatio(contentMode: .fit)
            }
        case .medal(let frame, let mount):
            MedalFrameMockup(panel: artwork, frameColour: frame, mountColour: mount, scale: 0.85)
        }
    }
}
