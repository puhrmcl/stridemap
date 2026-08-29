import Foundation
import CoreGraphics

/// The book product of record — Prodigi's A4-landscape layflat photo book, verified live
/// (product + US quote) on 2026-08-26: $28.50 production + $7.60 shipping at the default page
/// count. Gloss 190gsm pages, matte-laminate hard cover, true layflat binding, white-label.
enum BookCatalog {

    static let prodigiSKU = "BOOK-FE-A4-L-LF-G"
    static let name = "Etch Year in Review"
    /// The same object, bound around a place or a shelf of races rather than a calendar year.
    /// One SKU, one price, one production file — two products on the storefront, because "the
    /// year I ran" and "everything I ran in Colorado" are two different things to want.
    static let collectionName = "Etch Collection"
    static let material = "Layflat hardcover, A4 landscape (11.7 × 8.3″). Gloss 190gsm pages, matte-laminate cover."

    /// Verified content print area: 297×210mm at 300 DPI.
    static let pagePixelSize = CGSize(width: 3507, height: 2480)

    /// Authoring canvas in points — pages are composed at this size and rendered at
    /// `renderScale` to land exactly on the print pixel size.
    static let pageSize = CGSize(width: 1169, height: 826.67)
    static let renderScale: CGFloat = 3

    /// The print guide's 10mm safety margin on outside edges, in authoring points. The inside
    /// (gutter) edge needs none — layflat binding loses nothing to the gutter.
    static let safetyMargin: CGFloat = 40

    /// Prodigi's page-count envelope (even counts only; the lab adds its own blank leaves).
    static let minPages = 18
    static let maxPages = 122

    /// The PDF page rect in PDF points (297×210mm) — the file Prodigi receives.
    static let pdfPageRect = CGRect(x: 0, y: 0, width: 841.89, height: 595.28)

    /// Retail (locked): standard to ~30 pages; extended tier held until the per-page cost
    /// schedule is confirmed. Served remotely so a cost change or a seasonal price ships
    /// without an App Store release.
    static var priceCents: Int { EtchConfig.current.prices.yearBookCents }

    static var price: String {
        (Double(priceCents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// The product's URL handle in Shopify, whose variant carries the retail price at checkout.
    /// Must match the handle on the store's product page exactly — which is why it did not follow
    /// the rename to Year in Review. Both books check out against this one handle.
    static let shopifyHandle = "year-book"

    /// What the book is uploaded as. Every other product in the range is a single PNG sheet;
    /// this one is a multi-page PDF, and the lab rasterises it from the declared type.
    static let contentType = "application/pdf"
}
