import Foundation

/// A print size, in inches, portrait orientation. Prodigi SKUs are mapped server-side at order
/// time; the app only needs the human-facing dimensions to present a curated size choice.
struct PrintSize: Identifiable, Hashable {
    let width: Int
    let height: Int
    var id: String { "\(width)x\(height)" }
    var label: String { "\(width) × \(height)″" }
}

/// The Etch Studio print catalogue — Canvas, Framed Print, Poster, and Fine-Art Print — matched
/// to Prodigi's white-label products. Deliberately curated: a few beautiful formats, not a
/// configurator. Fulfilment (quote → checkout → Prodigi order) is wired server-side once the
/// backend lands; this layer is the customer-facing choice.
enum PrintProduct: String, CaseIterable, Identifiable {
    case print, poster, framed, canvas
    var id: String { rawValue }

    var name: String {
        switch self {
        case .print: return "Fine-Art Print"
        case .poster: return "Poster"
        case .framed: return "Framed Print"
        case .canvas: return "Canvas"
        }
    }

    /// A short, editorial line — what the object is, not a spec sheet.
    var tagline: String {
        switch self {
        case .print: return "Museum-grade archival paper. The route, unframed."
        case .poster: return "Large-format matte poster. Bold on a wall."
        case .framed: return "Classic frame, ready to hang out of the box."
        case .canvas: return "Gallery-wrapped canvas. Tactile and warm."
        }
    }

    var material: String {
        switch self {
        case .print: return "Giclée archival paper"
        case .poster: return "Premium matte poster paper"
        case .framed: return "Archival print · hardwood frame · glazing"
        case .canvas: return "Poly-cotton canvas · wood stretcher"
        }
    }

    var symbol: String {
        switch self {
        case .print: return "doc.richtext"
        case .poster: return "rectangle.portrait"
        case .framed: return "photo.artframe"
        case .canvas: return "photo"
        }
    }

    /// Curated portrait sizes for this product.
    var sizes: [PrintSize] {
        switch self {
        case .print:
            return [.init(width: 8, height: 10), .init(width: 11, height: 14),
                    .init(width: 12, height: 18), .init(width: 16, height: 20),
                    .init(width: 18, height: 24), .init(width: 24, height: 36)]
        case .poster:
            return [.init(width: 12, height: 18), .init(width: 18, height: 24),
                    .init(width: 24, height: 36)]
        case .framed:
            return [.init(width: 8, height: 10), .init(width: 11, height: 14),
                    .init(width: 16, height: 20), .init(width: 18, height: 24)]
        case .canvas:
            return [.init(width: 12, height: 16), .init(width: 16, height: 20),
                    .init(width: 18, height: 24), .init(width: 24, height: 36)]
        }
    }
}
