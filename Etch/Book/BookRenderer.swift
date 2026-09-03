import SwiftUI
import UIKit

/// Renders book pages — at preview scale for the pager, and at full 300-DPI print scale
/// into the single-PDF file Prodigi's layflat book takes (first page = front cover, last = back
/// cover, single pages, no bleed — per the print guide).
@MainActor
enum BookRenderer {

    /// One page as an image. `scale` 1 ≈ screen preview; `BookCatalog.renderScale` = print.
    ///
    /// Preview renders load photos at preview size. A big Collections book previews up to a
    /// hundred pages back to back, and pulling every photograph from the device library at
    /// its 1500px print size put hundreds of transient megabytes through that loop — the
    /// simulator's empty library never feels it, a phone's real one gets the app killed.
    /// Print export (`scale` ≥ 1) still asks full size; the proof and the product are exact.
    static func pageImage(plan: BookPlan, page index: Int, scale: CGFloat) async -> UIImage? {
        guard plan.pages.indices.contains(index) else { return nil }
        let spec = plan.pages[index]
        let preview = scale < 1
        let photo = await racePhoto(plan: plan, spec: spec, preview: preview)
        let photos = await pagePhotos(plan: plan, spec: spec, preview: preview)
        return autoreleasepool {
            let renderer = ImageRenderer(content: BookPageView(plan: plan, spec: spec,
                                                               photo: photo, photos: photos))
            renderer.scale = scale
            return renderer.uiImage
        }
    }

    /// The single hero photo a page leads with: a race page's cover shot, or the book cover's
    /// photograph when that treatment is chosen. Nil elsewhere.
    private static func racePhoto(plan: BookPlan, spec: BookPageSpec,
                                  preview: Bool) async -> UIImage? {
        let heroSide: CGFloat = preview ? 900 : 1800
        switch spec {
        case .race(let index):
            guard let run = plan.run(at: index),
                  let id = run.photoReferences.first(where: plan.curation.includes)
                        ?? run.photoReferences.first else { return nil }
            return await PhotoLibrary.image(for: id, targetSize: CGSize(width: heroSide, height: heroSide))
        case .cover where plan.curation.coverStyle == .photo:
            // The chosen cover shot; else the best candidate — a race's photo first, then the
            // first photograph the span has. Full-bleed on the cover, so ask big.
            let reference = plan.curation.coverPhotoRef
                ?? plan.runs.first(where: { $0.isRace && $0.photoReferences.contains(where: plan.curation.includes) })?
                    .photoReferences.first(where: plan.curation.includes)
                ?? plan.runs.flatMap(\.photoReferences).first(where: plan.curation.includes)
                ?? plan.curation.extraPhotoIDs.first
            guard let reference else { return nil }
            let side: CGFloat = preview ? 1000 : 2400
            return await PhotoLibrary.image(for: reference, targetSize: CGSize(width: side, height: side))
        default:
            return nil
        }
    }

    /// The photographs a picture page shows — the chapter spread's month, or the span-wide
    /// gallery — captioned and loaded at print-safe size. A reference the library no longer
    /// resolves keeps its slot with a nil image: the page draws the frame empty, and the proof
    /// gate shows the customer exactly what would print.
    private static func pagePhotos(plan: BookPlan, spec: BookPageSpec,
                                   preview: Bool) async -> [BookPagePhoto] {
        let picks: [(run: Run?, reference: String)]
        switch spec {
        case .chapterPhotos(let start):
            picks = photoPicks(from: plan.chapterRuns(start), cap: 6, curation: plan.curation)
        case .gallery:
            // The reader's own additions join the span-wide gallery after the activity
            // photographs — inside the same cap, thinning the activity picks to make room.
            let extras = plan.curation.extraPhotoIDs.map { (Run?.none, $0) }
            let activityCap = max(0, 12 - extras.count)
            picks = photoPicks(from: plan.runs, cap: activityCap, curation: plan.curation) + extras
        default:
            return []
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var photos: [BookPagePhoto] = []
        let side: CGFloat = preview ? 600 : 1500
        for pick in picks {
            let image = await PhotoLibrary.image(for: pick.reference,
                                                 targetSize: CGSize(width: side, height: side))
            let caption = pick.run.map { "\($0.name) · \(formatter.string(from: $0.startDate))" }
                ?? "From the library"
            photos.append(BookPagePhoto(image: image, caption: caption))
        }
        return photos
    }

    /// Which photographs a page shows: one per activity first, in date order, so the page
    /// tells the span rather than one afternoon; second and third photos join only when
    /// there's room, and an over-full pool is thinned evenly across time. Photos the reader
    /// excluded never enter the pool.
    static func photoPicks(from runs: [Run], cap: Int,
                           curation: BookCuration = BookCuration())
        -> [(run: Run?, reference: String)] {
        guard cap > 0 else { return [] }
        let carriers: [(run: Run, refs: [String])] = runs
            .map { ($0, $0.photoReferences.filter(curation.includes)) }
            .filter { !$0.1.isEmpty }
            .sorted { $0.0.startDate < $1.0.startDate }
        guard !carriers.isEmpty else { return [] }

        var picks: [(run: Run?, reference: String)] = carriers.map { ($0.run, $0.refs[0]) }
        var depth = 1
        while picks.count < cap {
            let more = carriers.filter { $0.refs.count > depth }
            guard !more.isEmpty else { break }
            for carrier in more where picks.count < cap {
                picks.append((carrier.run, carrier.refs[depth]))
            }
            depth += 1
        }
        if picks.count > cap {
            let step = Double(picks.count) / Double(cap)
            picks = (0..<cap).map { picks[min(picks.count - 1, Int(Double($0) * step))] }
        }
        return picks.sorted { ($0.run?.startDate ?? .distantPast) < ($1.run?.startDate ?? .distantPast) }
    }

    /// Renders the whole book to a print-ready PDF, reporting page progress. Pages are rendered
    /// one at a time to JPEG files on disk and streamed into the PDF inside autorelease pools —
    /// thirty A4 pages at 300 DPI never coexist in memory.
    static func exportPDF(plan: BookPlan, onProgress: @escaping (Int, Int) -> Void) async -> URL? {
        // The lab's envelope, enforced at the door (Prodigi layflat, verified live
        // 2026-08-26): 18–122 total pages, even counts only, first page front cover, last
        // page back cover. BookPlan.make holds all of this by construction — blank-leaf
        // padding to the minimum, parity fill, ceiling trim — so this guard should never
        // fire; if a future plan change breaks the contract, the failure is a refused
        // export here, not a rejected (or mis-bound) book at the lab.
        let total = plan.pages.count
        guard total >= BookCatalog.minPages, total <= BookCatalog.maxPages,
              total.isMultiple(of: 2) else {
            assertionFailure("Book plan out of the lab's envelope: \(total) pages")
            return nil
        }
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
