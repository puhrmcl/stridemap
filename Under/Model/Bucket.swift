import Foundation

/// The only four answers Under ever stores for a day.
///
/// `none` and `low` are both *quiet* days — together they feed the personal streak.
/// The raw values are the on-disk contract; the UI labels live in `label`.
enum Bucket: String, Codable, CaseIterable, Identifiable, Hashable {
    /// No discretionary spend at all.
    case none
    /// $25 or less. Exactly $25 is low.
    case low
    /// More than $25, up to $100. Exactly $100 is mid.
    case mid
    /// More than $100.
    case high

    var id: String { rawValue }

    /// The word shown anywhere a bucket is named. Never good/bad, never win/fail.
    var label: String {
        switch self {
        case .none: return "Quiet"
        case .low: return "Low"
        case .mid: return "Mid"
        case .high: return "High"
        }
    }

    /// A quiet day is nothing spent, or under $25.
    var isQuiet: Bool {
        switch self {
        case .none, .low: return true
        case .mid, .high: return false
        }
    }
}
