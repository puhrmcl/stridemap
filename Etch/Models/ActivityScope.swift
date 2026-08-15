import SwiftUI

/// Which activity type the app is currently showing. `all` blends every imported type; the others
/// narrow to one. Drives the totals-pill selector and every run-consuming surface.
enum ActivityScope: String, CaseIterable, Identifiable {
    case all, runs, hikes, walks
    var id: String { rawValue }

    /// The single type this scope narrows to; nil for `all`.
    var activityType: ActivityType? {
        switch self {
        case .all:   return nil
        case .runs:  return .run
        case .hikes: return .hike
        case .walks: return .walk
        }
    }

    /// Menu / selector label.
    var label: String {
        switch self {
        case .all:   return "All Activities"
        case .runs:  return "Runs"
        case .hikes: return "Hikes"
        case .walks: return "Walks"
        }
    }

    /// The word after a count — "886 runs", "42 hikes", "928 activities".
    var countNoun: String {
        switch self {
        case .all:   return "activities"
        case .runs:  return "runs"
        case .hikes: return "hikes"
        case .walks: return "walks"
        }
    }

    var icon: String {
        switch self {
        case .all:   return "figure.mixed.cardio"
        case .runs:  return "figure.run"
        case .hikes: return "figure.hiking"
        case .walks: return "figure.walk"
        }
    }

    /// Pace / speed comparisons only make sense for runs — hikes and walks are time/elevation
    /// efforts, so pace superlatives and PRs are hidden for them.
    var usesPace: Bool { self == .runs || self == .all }
}

/// Whether walks are shown anywhere. Off by default — Apple Watch auto-logs many short walks.
enum ActivitySettings {
    static var includeWalks: Bool { UserDefaults.standard.bool(forKey: "includeWalks") }
}

extension Sequence where Element == Run {
    /// Narrows to the scope. Walks are excluded everywhere unless the user opted in, so a stray
    /// walk never pollutes the runs/hikes views.
    func scoped(to scope: ActivityScope) -> [Run] {
        let includeWalks = ActivitySettings.includeWalks
        return filter { run in
            let type = run.activityType
            if type == .walk && !includeWalks { return false }
            switch scope {
            case .all:   return true
            case .runs:  return type == .run
            case .hikes: return type == .hike
            case .walks: return type == .walk
            }
        }
    }
}
