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
    ///
    /// ✓ VERIFIED against the live Prodigi catalogue (Verify Prodigi SKUs workflow, 2026-08-23):
    /// every SKU resolves, print areas are exactly 300 DPI at trim in true 2:3, and the framed
    /// line is the *unmounted* Classic Frame (full-bleed; the mounted CFPM line's mat crops to
    /// ~1:1.74 and was rejected for it). The fulfilment worker still re-validates at boot —
    /// Prodigi retires SKUs.
    let prodigiSKU: String
    /// Retail price in USD cents. Held here so the size list can show a price without a round trip;
    /// Shopify's price is authoritative at checkout and the backend re-validates before charging.
    ///
    /// Set against live Prodigi quotes (US, Standard shipping, 2026-08-23). Landed costs:
    /// prints $26.95 / $27.95 / $37.90; framed (CFP) $69.90 / $75.90 — giving 45–62% contribution
    /// before payment fees. Framed 12×18 sits at $139 (not $129) to keep its margin above 45%
    /// once fees and a replacement reserve come out.
    let priceCents: Int

    var id: String { "\(width)x\(height)-\(prodigiSKU)" }
    var label: String { "\(width) × \(height)″" }

    /// The price actually charged: the served configuration's value for this SKU when there is
    /// one, else the compiled default above. Lets a cost change or a promotion ship without an
    /// App Store release. Shopify remains authoritative at checkout.
    var resolvedPriceCents: Int {
        EtchConfig.priceCents(sku: prodigiSKU, default: priceCents)
    }

    var price: String {
        let dollars = Double(resolvedPriceCents) / 100
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    /// The print geometry for this size — trim, bleed, safe zone and DPI.
    var geometry: PrintGeometry {
        PrintGeometry(trimWidth: Double(width), trimHeight: Double(height))
    }

    /// Whether this device can render the print file at acceptable quality. 24×36 needs a
    /// 10,800px long edge — beyond the on-device ceiling — so it stays visible but unorderable
    /// until the server renderer exists.
    var deviceRenderable: Bool {
        geometry.isAcceptable(longEdgePixels: PrintGeometry.deviceRenderLongEdge)
    }

    /// The variant SKU as entered in Shopify — the join key between this catalogue and the
    /// store. Unframed sizes use the Prodigi SKU verbatim; framed sizes append the finish,
    /// because in Shopify each finish is its own variant.
    func shopifySKU(finish: FrameFinish?) -> String {
        guard let finish else { return prodigiSKU }
        return "\(prodigiSKU)-\(finish.skuSuffix)"
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
        case .print:  return "Giclée on Hahnemühle German Etching, 310gsm mould-made paper"
        case .framed: return "Giclée archival print · solid hardwood frame · shatterproof glazing"
        }
    }

    var symbol: String {
        switch self {
        case .print:  return "doc.richtext"
        case .framed: return "photo.artframe"
        }
    }

    /// The product's URL handle in Shopify, used to look up its variants at order time. Must
    /// match the handle on the store's product page exactly.
    var shopifyHandle: String {
        switch self {
        case .print:  return "fine-art-print"
        case .framed: return "framed-print"
        }
    }

    /// Curated 2:3 sizes. SKUs are Prodigi's German Etching / Classic Frame lines.
    var sizes: [PrintSize] {
        switch self {
        case .print:
            // HGE = Hahnemühle German Etching, the decided premium unframed paper (verified
            // drop-in for FAP: identical 300-DPI 2:3 print areas; landed $29.95/$32.95/$56.90).
            return [
                PrintSize(width: 12, height: 18, prodigiSKU: "GLOBAL-HGE-12X18", priceCents: 5900),
                PrintSize(width: 16, height: 24, prodigiSKU: "GLOBAL-HGE-16X24", priceCents: 7900),
                PrintSize(width: 24, height: 36, prodigiSKU: "GLOBAL-HGE-24X36", priceCents: 10900)
            ]
        case .framed:
            // CFP = Classic Frame, no mount: the full-bleed 2:3 framed product. (CFP-24X36 is
            // also verified, gated on the server renderer like the unframed 24×36.)
            return [
                PrintSize(width: 12, height: 18, prodigiSKU: "GLOBAL-CFP-12X18", priceCents: 13900),
                PrintSize(width: 16, height: 24, prodigiSKU: "GLOBAL-CFP-16X24", priceCents: 17900)
            ]
        }
    }

    /// Frame finishes, for the framed product only. These map to Prodigi frame attributes at
    /// order time; the app shows them as a finish choice, not as a SKU.
    var frameFinishes: [FrameFinish] {
        self == .framed ? FrameFinish.allCases : []
    }
}

/// The frame finishes offered on a Framed Print. Four of Prodigi's eight, curated: Black for
/// the dark editions, Natural for bone grounds and everything warm, White for light/minimal
/// walls, Dark Grey for the modern-industrial buyer. Gold, silver, brown, and light grey were
/// cut — period-decor undertones that fight a modern map aesthetic, or too close to White.
/// Colours cost no new print files (same artwork, a frame attribute at order time); the
/// attribute values below are ✓ VERIFIED against the live catalog (2026-08-25).
enum FrameFinish: String, CaseIterable, Identifiable {
    case natural, black, white, darkGrey
    var id: String { rawValue }

    var name: String {
        switch self {
        case .natural:  return "Natural"
        case .black:    return "Black"
        case .white:    return "White"
        case .darkGrey: return "Dark Grey"
        }
    }

    /// Prodigi's frame colour attribute value (exact strings from the live catalog).
    var prodigiAttribute: String {
        switch self {
        case .natural:  return "natural"
        case .black:    return "black"
        case .white:    return "white"
        case .darkGrey: return "dark grey"
        }
    }

    /// The finish's suffix in the Shopify variant SKU (no spaces — SKUs stay machine-safe).
    var skuSuffix: String {
        switch self {
        case .natural:  return "NATURAL"
        case .black:    return "BLACK"
        case .white:    return "WHITE"
        case .darkGrey: return "DARKGREY"
        }
    }

    /// Approximate moulding colour, for drawing the on-device mockup.
    var mouldingHex: String {
        switch self {
        case .natural:  return "#B58A54"
        case .black:    return "#1A1A1C"
        case .white:    return "#F1EEE8"
        case .darkGrey: return "#4A4C50"
        }
    }
}
