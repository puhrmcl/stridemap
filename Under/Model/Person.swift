import Foundation

/// One person with a first name and their own daily log.
/// v1 holds one or exactly two of these; a check-in always belongs to one person.
struct Person: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
