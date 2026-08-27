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

    /// Whether the device can produce this size's print file at acceptable quality.
    ///
    /// It always can now. This used to test the trim against a 6,000px ceiling, which is the
    /// largest *single bitmap* a phone will hold — and it made 24×36 permanently unorderable at
    /// 10,800px, waiting on a server renderer that would have meant a second implementation of
    /// the composition. `PrintFileWriter` streams the sheet to disk a band at a time instead, so
    /// the ceiling is on one band rather than on the print, and every size renders at the full
    /// 300 DPI its geometry asks for. Kept as a property because a future size could still be
    /// out of reach, and a call site that asks the question is better than one that assumes.
    var deviceRenderable: Bool {
        geometry.isAcceptable(longEdgePixels: max(geometry.trimPixels.width,
                                                  geometry.trimPixels.height))
    }

    /// The variant SKU as entered in Shopify — the join key between this catalogue and the
    /// store. Unframed sizes use the Prodigi SKU verbatim; finished sizes append the finish,
    /// because in Shopify each finish is its own variant.
    func shopifySKU(finish: PrintFinish) -> String {
        guard let suffix = finish.skuSuffix else { return prodigiSKU }
        return "\(prodigiSKU)-\(suffix)"
    }
}

/// What a print is finished with. Two products take a finish and they take different ones — a
/// moulding colour or a wood colour — so the order path carries the choice as one value rather
/// than as a pair of optionals that must never both be set.
enum PrintFinish: Hashable {
    case none
    case frame(FrameFinish)
    case hanger(HangerFinish)

    /// The Shopify variant suffix, or nil for an unfinished sheet.
    var skuSuffix: String? {
        switch self {
        case .none:              return nil
        case .frame(let f):      return f.skuSuffix
        case .hanger(let h):     return h.skuSuffix
        }
    }

    /// Prodigi's colour attribute value, empty when there's nothing to send.
    var prodigiAttribute: String {
        switch self {
        case .none:              return ""
        case .frame(let f):      return f.prodigiAttribute
        case .hanger(let h):     return h.prodigiAttribute
        }
    }
}

/// The Etch Studio print catalogue.
///
/// Deliberately few SKUs. The audit's reasoning: every extra SKU is a print profile, a mockup, a
/// margin, a damage policy and a support case, and none of that is worth carrying before one
/// framed print has shipped and come back undamaged. Poster was cut (it competes with Fine-Art
/// Print and reads cheaper), canvas deferred (different look, different quality risk), stickers
/// cut (inconsistent with "museum-grade archival paper").
enum PrintProduct: String, CaseIterable, Identifiable {
    /// Case order is the order the shop presents them, and it climbs: bare sheet, then wood, then
    /// glass and a hardwood frame — $59 to $109, then $129, then $139 to $179. A buyer reading
    /// down the list is reading a price ladder, and each rung adds something physical to the one
    /// above it. The hanger sitting last put the cheapest finish in the range beneath the dearest
    /// product, which read as an afterthought rather than as the step it is.
    ///
    /// The raw values are the case names and are unchanged by the reordering, so nothing already
    /// stored against them moves.
    case print, hanger, framed
    var id: String { rawValue }

    /// The formats the shop currently shows. The hanger is built but withheld while its only
    /// confirmed portrait size needs a render the device can't produce — see
    /// `PosterHangerCatalog.isAvailable`, whose gate resolves on its own.
    static var offered: [PrintProduct] {
        allCases.filter { $0 != .hanger || PosterHangerCatalog.isAvailable }
    }

    var name: String {
        switch self {
        case .print:  return "Fine-Art Print"
        case .hanger: return "Print with Hanger"
        case .framed: return "Framed Print"
        }
    }

    /// A short, editorial line — what the object is, not a spec sheet.
    var tagline: String {
        switch self {
        case .print:  return "Museum-grade archival paper. Unframed, ready for your own frame."
        case .hanger: return "Archival print in solid wood hangers. Hangs from a nail, no glass."
        case .framed: return "Archival print in a hardwood frame. Ready to hang out of the box."
        }
    }

    var material: String {
        switch self {
        case .print:  return "Giclée on Hahnemühle German Etching, 310gsm mould-made paper"
        case .hanger: return "Archival print on 200gsm enhanced matte art paper · solid wood magnetic hangers"
        case .framed: return "Giclée archival print · solid hardwood frame · shatterproof glazing"
        }
    }

    /// What actually arrives in the box.
    ///
    /// Every product page answers this question whether or not it prints it; the ones that don't
    /// answer it get the question by email instead. Each line is a property of the verified
    /// Prodigi product, not a marketing claim: the Classic Frame ships assembled and glazed with
    /// its hanging hardware fitted, the hanger line is two magnetic wood battens and a cord, and
    /// the fine-art line is a single loose sheet with nothing else in the tube.
    var whatShips: String {
        switch self {
        case .print:
            return "One print, unframed and unmounted, rolled in a protective tube."
        case .hanger:
            return "One print with a pair of solid wood magnetic hangers and a hanging cord."
        case .framed:
            return "One framed print, assembled and glazed, with hanging hardware fitted."
        }
    }

    var symbol: String {
        switch self {
        case .print:  return "doc.richtext"
        case .hanger: return "scroll"
        case .framed: return "photo.artframe"
        }
    }

    /// A two-word name for the storefront strip, where the full one wraps.
    var shortName: String {
        switch self {
        case .print:  return "Fine-Art Print"
        case .hanger: return "With Hanger"
        case .framed: return "Framed"
        }
    }

    /// The cheapest this format can be had for — what the storefront quotes before a size is
    /// chosen. Derived from the sizes rather than written down, so it cannot drift from them.
    var entryPrice: String {
        guard let lowest = sizes.map(\.resolvedPriceCents).min() else { return "—" }
        let formatted = (Double(lowest) / 100)
            .formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return sizes.count > 1 ? "From \(formatted)" : formatted
    }

    /// The product's URL handle in Shopify, used to look up its variants at order time. Must
    /// match the handle on the store's product page exactly.
    var shopifyHandle: String {
        switch self {
        case .print:  return "fine-art-print"
        case .hanger: return "print-with-hanger"
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
        case .hanger:
            // Read off the product page and confirmed live. The 24×36 hanger's print area is
            // 7200 × 10800 — identical to GLOBAL-HGE-24X36 and GLOBAL-CFP-24X36 — so the finish
            // needs no new geometry, only the covered bands kept clear. Priced between the
            // unframed and framed lines: £7 wholesale is the cheapest finish in the range, and
            // the paper is the 200gsm EMA stock rather than the 310gsm mould-made.
            return PosterHangerCatalog.portraitSizes.map {
                PrintSize(width: $0.width, height: $0.height, prodigiSKU: $0.sku, priceCents: 12900)
            }
        case .framed:
            // CFP = Classic Frame, no mount: the full-bleed 2:3 framed product.
            //
            // GLOBAL-CFP-24X36 is verified and now renderable — the banded writer removed the
            // ceiling that used to gate it. It stays unlisted for a different reason: no live
            // quote has come back for it, and a framed 24×36 is the dearest thing in the range,
            // so a guessed rung would be a guess at a loss. Add it when the quote lands.
            return [
                PrintSize(width: 12, height: 18, prodigiSKU: "GLOBAL-CFP-12X18", priceCents: 13900),
                PrintSize(width: 16, height: 24, prodigiSKU: "GLOBAL-CFP-16X24", priceCents: 17900)
            ]
        }
    }

    /// Whether choosing this format asks for a colour, and which kind.
    var takesFrameFinish: Bool { self == .framed }
    var takesHangerFinish: Bool { self == .hanger }
}

/// The wood colours a hanger comes in — all three Prodigi offers, because unlike frame mouldings
/// there is no colour here that fights a map: black, natural and white are the only options and
/// each reads as a deliberate choice. The attribute values are the catalog's exact strings; the
/// range sheet's "natural oak" is rejected on a quote.
enum HangerFinish: String, CaseIterable, Identifiable {
    case natural, black, white
    var id: String { rawValue }

    var name: String {
        switch self {
        case .natural: return "Natural"
        case .black:   return "Black"
        case .white:   return "White"
        }
    }

    var prodigiAttribute: String { rawValue }

    var skuSuffix: String { rawValue.uppercased() }

    /// Approximate wood colour, for drawing the on-device mockup.
    var woodHex: String {
        switch self {
        case .natural: return "#C99B62"
        case .black:   return "#1A1A1C"
        case .white:   return "#F1EEE8"
        }
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
