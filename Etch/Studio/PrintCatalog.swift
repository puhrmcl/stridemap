import Foundation

/// A print size, with the geometry the lab actually needs and the Prodigi SKU that produces it.
///
/// Every size here is 2:3 — the aspect Studio authors natively. 4:5 sizes (8×10, 16×20) are held
/// back deliberately until 2:3 is proven end to end: one aspect means one composition to perfect
/// and one proof cycle, not two of each.
struct PrintSize: Identifiable, Hashable {
    let width: Int
    let height: Int
    /// Prodigi's product SKU. The app never calls Prodigi directly — this travels with the order to
    /// the Etch backend, which holds the credentials and creates the order server-side.
    let prodigiSKU: String
    /// Retail price in USD cents. Held here so the size list can show a price without a round trip;
    /// the backend re-validates before charging, and its number is authoritative.
    let priceCents: Int

    var id: String { "\(width)x\(height)-\(prodigiSKU)" }
    var label: String { "\(width) × \(height)″" }

    var price: String {
        let dollars = Double(priceCents) / 100
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// The print geometry for this size — trim, bleed, safe zone and DPI.
    var geometry: PrintGeometry {
        PrintGeometry(trimWidth: Double(width), trimHeight: Double(height))
    }
}

/// The Etch Studio print catalogue.
///
/// Deliberately two products and five SKUs. The audit's reasoning: every extra SKU is a print
/// profile, a mockup, a margin, a damage policy and a support case, and none of that is worth
/// carrying before one framed print has shipped and come back undamaged. Poster was cut (it
/// competes with Fine-Art Print and reads cheaper), canvas deferred (different look, different
/// quality risk), stickers cut (inconsistent with "museum-grade archival paper").
enum PrintProduct: String, CaseIterable, Identifiable {
    case print, framed
    var id: String { rawValue }

    var name: String {
        switch self {
        case .print:  return "Fine-Art Print"
        case .framed: return "Framed Print"
        }
    }

    /// A short, editorial line — what the object is, not a spec sheet.
    var tagline: String {
        switch self {
        case .print:  return "Museum-grade archival paper. Unframed, ready for your own frame."
        case .framed: return "Archival print in a hardwood frame. Ready to hang out of the box."
        }
    }

    var material: String {
        switch self {
        case .print:  return "Giclée on 200gsm archival fine-art paper"
        case .framed: return "Giclée archival print · solid hardwood frame · shatterproof glazing"
        }
    }

    var symbol: String {
        switch self {
        case .print:  return "doc.richtext"
        case .framed: return "photo.artframe"
        }
    }

    /// Curated 2:3 sizes. SKUs are Prodigi's Global Fine Art / Classic Frame lines.
    var sizes: [PrintSize] {
        switch self {
        case .print:
            return [
                PrintSize(width: 12, height: 18, prodigiSKU: "GLOBAL-FAP-12X18", priceCents: 4900),
                PrintSize(width: 16, height: 24, prodigiSKU: "GLOBAL-FAP-16X24", priceCents: 6900),
                PrintSize(width: 24, height: 36, prodigiSKU: "GLOBAL-FAP-24X36", priceCents: 9900)
            ]
        case .framed:
            return [
                PrintSize(width: 12, height: 18, prodigiSKU: "GLOBAL-CFPM-12X18", priceCents: 12900),
                PrintSize(width: 16, height: 24, prodigiSKU: "GLOBAL-CFPM-16X24", priceCents: 17900)
            ]
        }
    }

    /// Frame finishes, for the framed product only. These map to Prodigi frame attributes at
    /// order time; the app shows them as a finish choice, not as a SKU.
    var frameFinishes: [FrameFinish] {
        self == .framed ? FrameFinish.allCases : []
    }
}

/// The frame finishes offered on a Framed Print. Three, chosen to sit under any edition: black for
/// the dark editions, white for bone grounds, oak as the warm middle.
enum FrameFinish: String, CaseIterable, Identifiable {
    case black, white, oak
    var id: String { rawValue }

    var name: String {
        switch self {
        case .black: return "Black"
        case .white: return "White"
        case .oak:   return "Oak"
        }
    }

    /// Prodigi's frame colour attribute value.
    var prodigiAttribute: String {
        switch self {
        case .black: return "black"
        case .white: return "white"
        case .oak:   return "natural"
        }
    }

    /// Approximate moulding colour, for drawing the on-device mockup.
    var mouldingHex: String {
        switch self {
        case .black: return "#1A1A1C"
        case .white: return "#F2F0EC"
        case .oak:   return "#B58A54"
        }
    }
}
