import SwiftUI

/// Which activity type the app is currently showing. `all` blends every imported type; the others
/// narrow to one. Drives the totals-pill selector and every run-consuming surface.
enum ActivityScope: String, CaseIterable, Identifiable {
    case all, runs, hikes, rides, walks
    var id: String { rawValue }

    /// The single type this scope narrows to; nil for `all`.
    var activityType: ActivityType? {
        switch self {
        case .all:   return nil
        case .runs:  return .run
        case .hikes: return .hike
        case .rides: return .ride
        case .walks: return .walk
        }
    }

    /// Menu / selector label.
    var label: String {
        switch self {
        case .all:   return "All Activities"
        case .runs:  return "Runs"
        case .hikes: return "Hikes"
        case .rides: return "Rides"
        case .walks: return "Walks"
        }
    }

    /// The word after a count — "886 runs", "42 hikes", "928 activities".
    var countNoun: String {
        switch self {
        case .all:   return "activities"
        case .runs:  return "runs"
        case .hikes: return "hikes"
        case .rides: return "rides"
        case .walks: return "walks"
        }
    }

    var icon: String {
        switch self {
        case .all:   return "figure.mixed.cardio"
        case .runs:  return "figure.run"
        case .hikes: return "figure.hiking"
        case .rides: return "figure.outdoor.cycle"
        case .walks: return "figure.walk"
        }
    }

    /// Pace / speed comparisons only make sense for runs — hikes, rides and walks are time /
    /// elevation / speed efforts, so run-style pace superlatives and PRs are hidden for them.
    var usesPace: Bool { self == .runs || self == .all }
}

/// Per-activity visibility. Runs are the base and always shown; hikes and walks can each be turned
/// off so someone who only cares about running never sees the rest. Hikes are on by default (a
/// deliberate import); walks are off by default because Apple Watch auto-logs many short walks.
enum ActivitySettings {
    /// Defaults to `true` when the key was never written — the positive default for runs, hikes & rides.
    static var includeRuns: Bool { UserDefaults.standard.object(forKey: "includeRuns") as? Bool ?? true }
    static var includeHikes: Bool { UserDefaults.standard.object(forKey: "includeHikes") as? Bool ?? true }
    static var includeRides: Bool { UserDefaults.standard.object(forKey: "includeRides") as? Bool ?? true }
    static var includeWalks: Bool { UserDefaults.standard.bool(forKey: "includeWalks") }

    /// True when every activity type is turned off — the app has nothing to show and prompts setup.
    static var allOff: Bool { !includeRuns && !includeHikes && !includeRides && !includeWalks }

    /// Whether a given scope is currently visible. `all` stays available as long as anything is on.
    static func isVisible(_ scope: ActivityScope) -> Bool {
        switch scope {
        case .all:   return !allOff
        case .runs:  return includeRuns
        case .hikes: return includeHikes
        case .rides: return includeRides
        case .walks: return includeWalks
        }
    }

    /// The scopes offered in every activity selector, in order — the disabled ones dropped.
    static var visibleScopes: [ActivityScope] {
        ActivityScope.allCases.filter(isVisible)
    }
}

extension Sequence where Element == Run {
    /// Narrows to the scope. Hidden activity types (hikes/walks the user turned off) are excluded
    /// everywhere, so a stray walk never pollutes the runs view and hikes vanish when hidden.
    func scoped(to scope: ActivityScope) -> [Run] {
        let includeRuns = ActivitySettings.includeRuns
        let includeHikes = ActivitySettings.includeHikes
        let includeRides = ActivitySettings.includeRides
        let includeWalks = ActivitySettings.includeWalks
        return filter { run in
            if run.isHidden { return false }
            let type = run.activityType
            if type == .run && !includeRuns { return false }
            if type == .hike && !includeHikes { return false }
            if type == .ride && !includeRides { return false }
            if type == .walk && !includeWalks { return false }
            switch scope {
            case .all:   return true
            case .runs:  return type == .run
            case .hikes: return type == .hike
            case .rides: return type == .ride
            case .walks: return type == .walk
            }
        }
    }
}
