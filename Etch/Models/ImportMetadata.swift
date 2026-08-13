import Foundation

/// *How* an activity reached Etch, distinct from *which ecosystem* it came from
/// (`ActivitySource`). A Nike run imported from a TCX file has `provider = .nikeRunClub`
/// and `importMethod = .tcxFile`; the same run synced live from Apple Health has
/// `importMethod = .healthKit`. Kept for provenance, debugging, and future "manage sources".
enum ImportMethod: String {
    case healthKit
    case stravaAPI
    case gpxFile
    case tcxFile
    case fitFile
    case zipArchive
    case manual

    /// Short human label for the run detail / import summary.
    var label: String {
        switch self {
        case .healthKit: return "Apple Health"
        case .stravaAPI: return "Strava"
        case .gpxFile: return "GPX file"
        case .tcxFile: return "TCX file"
        case .fitFile: return "FIT file"
        case .zipArchive: return "Archive"
        case .manual: return "Manual"
        }
    }
}

/// The normalized kind of activity, parsed from every source even while the UI filters to
/// running. Keeps the importer honest about future walking/hiking/cycling support without
/// hard-coding "run" into the parsers.
enum ActivityType: String {
    case run
    case walk
    case hike
    case ride      // cycling
    case ski
    case swim
    case row
    case other

    /// Fuzzy-maps a provider's free-text sport label (GPX `<type>`, TCX `Sport=`, Strava
    /// `sport_type`, …) to a normalized type. Unknown labels fall back to `.other`.
    static func parse(_ raw: String?) -> ActivityType {
        guard let s = raw?.lowercased(), !s.isEmpty else { return .run }
        if s.contains("run") || s.contains("jog") { return .run }
        if s.contains("hik") { return .hike }
        if s.contains("walk") { return .walk }
        if s.contains("bik") || s.contains("cycl") || s.contains("ride") { return .ride }
        if s.contains("ski") { return .ski }
        if s.contains("swim") { return .swim }
        if s.contains("row") { return .row }
        return .other
    }

    var isRunning: Bool { self == .run }
}
