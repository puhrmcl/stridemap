import Foundation

/// What the reader chose about their book's pictures and cover — the curation layer.
/// **Users curate, Etch designs**: nothing here moves a layout; it only says which
/// photographs the book may use, which one leads the cover, and which cover treatment
/// the object wears.
///
/// Keyed by the plan's slug (subject + lens), because "2026" and "2026, just the rides"
/// are different books and must remember different choices. Stored as JSON in
/// UserDefaults — the data is a handful of identifiers, not a library.
struct BookCuration: Codable, Equatable {

    /// Photo references the reader took OUT of the book. Everything an activity carries is
    /// in by default; exclusion is the choice that needs remembering.
    var excludedRefs: Set<String> = []

    /// Library photos the reader added IN — photos that aren't attached to any activity
    /// (the finish-line shot a friend took). They join the span-wide gallery.
    var extraPhotoIDs: [String] = []

    /// Which treatment the cover wears.
    var coverStyle: CoverStyle = .route

    /// The photograph a `.photo` cover leads with; nil falls back to the book's best
    /// candidate (a race's photo first).
    var coverPhotoRef: String?

    enum CoverStyle: String, Codable, CaseIterable, Identifiable {
        /// The year's longest line, drawn in bone on ink — the statement cover.
        case route
        /// A photograph full-bleed under an ink scrim, the type over it.
        case photo
        /// Every route of the span as a grid of bone lines — the anthology cover.
        case grid

        var id: String { rawValue }
        var label: String {
            switch self {
            case .route: return "Featured Route"
            case .photo: return "Cover Photo"
            case .grid:  return "The Grid"
            }
        }
    }

    /// Whether a reference survived curation.
    func includes(_ reference: String) -> Bool { !excludedRefs.contains(reference) }

    // MARK: Storage

    private static func key(_ slug: String) -> String { "etch.book.curation.\(slug)" }

    static func load(slug: String) -> BookCuration {
        guard let data = UserDefaults.standard.data(forKey: key(slug)),
              let curation = try? JSONDecoder().decode(BookCuration.self, from: data) else {
            return BookCuration()
        }
        return curation
    }

    func save(slug: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(slug))
    }
}
