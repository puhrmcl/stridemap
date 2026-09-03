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
        let photos = await pagePhotos(plan: plan, spec: spec)
        let renderer = ImageRenderer(content: BookPageView(plan: plan, spec: spec,
                                                           photo: photo, photos: photos))
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

    /// The photographs a picture page shows — the chapter spread's month, or the span-wide
    /// gallery — captioned and loaded at print-safe size. A reference the library no longer
    /// resolves keeps its slot with a nil image: the page draws the frame empty, and the proof
    /// gate shows the customer exactly what would print.
    private static func pagePhotos(plan: BookPlan, spec: BookPageSpec) async -> [BookPagePhoto] {
        let picks: [(run: Run, reference: String)]
        switch spec {
        case .chapterPhotos(let start): picks = photoPicks(from: plan.chapterRuns(start), cap: 6)
        case .gallery:                  picks = photoPicks(from: plan.runs, cap: 12)
        default:                        return []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var photos: [BookPagePhoto] = []
        for pick in picks {
            let image = await PhotoLibrary.image(for: pick.reference,
                                                 targetSize: CGSize(width: 1500, height: 1500))
            photos.append(BookPagePhoto(
                image: image,
                caption: "\(pick.run.name) · \(formatter.string(from: pick.run.startDate))"
            ))
        }
        return photos
    }

    /// Which photographs a page shows: one per activity first, in date order, so the page
    /// tells the span rather than one afternoon; second and third photos join only when
    /// there's room, and an over-full pool is thinned evenly across time.
    static func photoPicks(from runs: [Run], cap: Int) -> [(run: Run, reference: String)] {
        let carriers = runs.filter { !$0.photoReferences.isEmpty }
            .sorted { $0.startDate < $1.startDate }
        guard !carriers.isEmpty else { return [] }

        var picks: [(run: Run, reference: String)] = carriers.map { ($0, $0.photoReferences[0]) }
        var depth = 1
        while picks.count < cap {
            let more = carriers.filter { $0.photoReferences.count > depth }
            guard !more.isEmpty else { break }
            for run in more where picks.count < cap {
                picks.append((run, run.photoReferences[depth]))
            }
            depth += 1
        }
        if picks.count > cap {
            let step = Double(picks.count) / Double(cap)
            picks = (0..<cap).map { picks[min(picks.count - 1, Int(Double($0) * step))] }
        }
        return picks.sorted { $0.run.startDate < $1.run.startDate }
    }

    /// Renders the whole book to a print-ready PDF, reporting page progress. Pages are rendered
    /// one at a time to JPEG files on disk and streamed into the PDF inside autorelease pools —
    /// thirty A4 pages at 300 DPI never coexist in memory.
    static func exportPDF(plan: BookPlan, onProgress: @escaping (Int, Int) -> Void) async -> URL? {
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("book-\(plan.slug)-\(UUID().uuidString.prefix(6))")
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
            .appendingPathComponent("Etch-Book-\(plan.slug).pdf")
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
