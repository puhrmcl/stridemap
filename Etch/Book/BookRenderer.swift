import SwiftUI
import UIKit

/// Renders book pages — at preview scale for the pager, and at full 300-DPI print scale
/// into the single-PDF file Prodigi's layflat book takes (first page = front cover, last = back
/// cover, single pages, no bleed — per the print guide).
@MainActor
enum BookRenderer {

    /// One page as an image. `scale` 1 ≈ screen preview; `BookCatalog.renderScale` = print.
    static func pageImage(plan: BookPlan, page index: Int, scale: CGFloat) async -> UIImage? {
        guard plan.pages.indices.contains(index) else { return nil }
        let spec = plan.pages[index]
        let photo = await racePhoto(plan: plan, spec: spec)
        let renderer = ImageRenderer(content: BookPageView(plan: plan, spec: spec, photo: photo))
        renderer.scale = scale
        return renderer.uiImage
    }

    /// A race page's cover photo (the run's first photo), sized for its panel; nil elsewhere.
    private static func racePhoto(plan: BookPlan, spec: BookPageSpec) async -> UIImage? {
        guard case .race(let index) = spec,
              let run = plan.run(at: index),
              let id = run.photoReferences.first else { return nil }
        return await PhotoLibrary.image(for: id, targetSize: CGSize(width: 1800, height: 1800))
    }

    /// Renders the whole book to a print-ready PDF, reporting page progress. Pages are rendered
    /// one at a time to JPEG files on disk and streamed into the PDF inside autorelease pools —
    /// thirty A4 pages at 300 DPI never coexist in memory.
    static func exportPDF(plan: BookPlan, onProgress: @escaping (Int, Int) -> Void) async -> URL? {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-\(plan.subject.slug)-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var pageFiles: [URL] = []
        for index in plan.pages.indices {
            onProgress(index + 1, plan.pages.count)
            guard let image = await pageImage(plan: plan, page: index,
                                              scale: BookCatalog.renderScale) else { return nil }
            let file = workDirectory.appendingPathComponent("page-\(index).jpg")
            guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
            do { try data.write(to: file) } catch { return nil }
            pageFiles.append(file)
            // Yield so the progress UI can draw between heavyweight renders.
            await Task.yield()
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("Etch-Book-\(plan.subject.slug).pdf")
        let format = UIGraphicsPDFRendererFormat()
        let pdf = UIGraphicsPDFRenderer(bounds: BookCatalog.pdfPageRect, format: format)
        do {
            try pdf.writePDF(to: output) { context in
                for file in pageFiles {
                    autoreleasepool {
                        context.beginPage()
                        if let image = UIImage(contentsOfFile: file.path) {
                            image.draw(in: BookCatalog.pdfPageRect)
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return output
    }
}
