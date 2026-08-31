import Foundation
import SwiftData

/// A composable description of which runs should be visible on the map / timeline.
///
/// Kept as a plain value type so it can drive SwiftUI state and be diffed cheaply
/// for animated map transitions.
struct RunFilter: Equatable {

    enum DateRange: Equatable {
        case all
        case last7Days
        case last30Days
        case thisMonth
        case thisYear
        case year(Int)
        case custom(start: Date, end: Date)
    }

    /// Mutually-exclusive "map mode" quick toggles from the design brief.
    enum Mode: String, CaseIterable, Identifiable {
        case all = "All Runs"
        case recent = "Recent"
        case prs = "PRs"
        case races = "Races"
        case favorites = "Favorites"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: return "map"
            case .recent: return "sparkles"
            case .prs: return "trophy"
            case .races: return "flag.checkered"
            case .favorites: return "heart.fill"
            }
        }

        /// Decodes a stored raw value, mapping the retired `Long Runs` (Distance) view — which an
        /// older install may have persisted — safely back to `All` rather than an invalid state.
        static func fromStored(_ raw: String?) -> Mode {
            guard let raw, let mode = Mode(rawValue: raw) else { return .all }
            return mode
        }
    }

    enum Surface: String, CaseIterable, Identifiable {
        case any = "Any"
        case road = "Road"
        case trail = "Trail"
        var id: String { rawValue }
    }

    var dateRange: DateRange = .all
    var mode: Mode = .all
    var surface: Surface = .any
    var city: String?
    var state: String?
    var country: String?

    /// Distance bounds (metres); nil means no bound on that end.
    var minDistance: Double?
    var maxDistance: Double?
    /// Moving-time bounds (seconds); nil means no bound on that end.
    var minDuration: Int?
    var maxDuration: Int?

    var isActive: Bool {
        dateRange != .all || mode != .all || surface != .any
            || city != nil || state != nil || country != nil
            || minDistance != nil || maxDistance != nil
            || minDuration != nil || maxDuration != nil
    }

    /// Evaluates a run against this filter. `isPR` is supplied by the caller because
    /// PR status is a property of the whole collection, not a single run.
    func matches(_ run: Run, isPR: Bool) -> Bool {
        if !matchesDate(run.startDate) { return false }

        switch mode {
        case .all: break
        case .recent: if run.ageInDays > 30 { return false }
        case .prs: if !isPR { return false }
        case .races: if !run.isRace { return false }
        case .favorites: if !run.isFavorite { return false }
        }

        switch surface {
        case .any: break
        case .road: if run.isTrail { return false }
        case .trail: if !run.isTrail { return false }
        }

        // States and countries compare canonically, because the geocoder does not.
        //
        // One library can hold "AZ" and "Arizona" for the same place, depending on which app
        // wrote the activity and when. Comparing the raw strings meant a filter set to Arizona
        // silently dropped every run stored as AZ — the filter looked like it worked, and simply
        // showed you half your history. Cities have no such abbreviations, so they stay exact.
        if let city, run.city != city { return false }
        if let state, PlaceNames.canonicalState(run.state) != PlaceNames.canonicalState(state) {
            return false
        }
        if let country,
           PlaceNames.canonicalCountry(run.country) != PlaceNames.canonicalCountry(country) {
            return false
        }

        if let minDistance, run.distance < minDistance { return false }
        if let maxDistance, run.distance > maxDistance { return false }
        if let minDuration, run.movingTime < minDuration { return false }
        if let maxDuration, run.movingTime > maxDuration { return false }
        return true
    }

    private func matchesDate(_ date: Date) -> Bool {
        let cal = Calendar.current
        let now = Date()
        switch dateRange {
        case .all:
            return true
        case .last7Days:
            return date >= cal.date(byAdding: .day, value: -7, to: now)!
        case .last30Days:
            return date >= cal.date(byAdding: .day, value: -30, to: now)!
        case .thisMonth:
            return cal.isDate(date, equalTo: now, toGranularity: .month)
        case .thisYear:
            return cal.isDate(date, equalTo: now, toGranularity: .year)
        case .year(let y):
            return cal.component(.year, from: date) == y
        case .custom(let start, let end):
            return date >= start && date <= end
        }
    }

    /// A short label for the active date range, used on floating chips.
    var dateRangeLabel: String {
        switch dateRange {
        case .all: return "All Time"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .thisMonth: return "This Month"
        case .thisYear: return "This Year"
        case .year(let y): return String(y)
        case .custom: return "Custom"
        }
    }
}
