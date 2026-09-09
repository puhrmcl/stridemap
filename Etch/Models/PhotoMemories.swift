import Foundation
import CoreLocation

/// These operations only change Etch's associations. They never delete a Photos asset.
extension Run {
    var memoryPhotoReferences: [String] {
        photoReferences.filter { !memoryHiddenPhotoReferences.contains($0) && !rejectedPhotoReferences.contains($0) }
    }

    /// - Returns: whether anything actually changed.
    ///
    /// The return value is not decoration. A rescan that finds nothing new must not stamp
    /// `updatedAt`: the map keys its content revision on the newest edit, so an unconditional bump
    /// makes every scan look like an edit to every activity and rebuilds overlays that did not
    /// change.
    @discardableResult
    func attachPhotos(_ identifiers: [String], manually: Bool) -> Bool {
        var changed = false
        if manually {
            let before = rejectedPhotoReferences.count
            rejectedPhotoReferences.removeAll { identifiers.contains($0) }
            changed = rejectedPhotoReferences.count != before
        }
        for id in identifiers where !rejectedPhotoReferences.contains(id) && !photoReferences.contains(id) {
            photoReferences.append(id)
            changed = true
        }
        if changed { updatedAt = Date() }
        return changed
    }

    /// The former index is enough to restore the cover/order without replacing later edits.
    @discardableResult
    func rejectPhoto(_ id: String) -> Int? {
        let index = photoReferences.firstIndex(of: id)
        photoReferences.removeAll { $0 == id }
        if !rejectedPhotoReferences.contains(id) { rejectedPhotoReferences.append(id) }
        updatedAt = Date()
        return index
    }

    func restorePhoto(_ id: String, at index: Int) {
        rejectedPhotoReferences.removeAll { $0 == id }
        if !photoReferences.contains(id) { photoReferences.insert(id, at: min(index, photoReferences.count)) }
        updatedAt = Date()
    }

    func setPhotoHiddenFromMemories(_ id: String, hidden: Bool) {
        memoryHiddenPhotoReferences.removeAll { $0 == id }
        if hidden { memoryHiddenPhotoReferences.append(id) }
        updatedAt = Date()
    }

    func makePhotoCover(_ id: String) {
        guard photoReferences.contains(id) else { return }
        photoReferences.removeAll { $0 == id }
        photoReferences.insert(id, at: 0)
        updatedAt = Date()
    }
}

struct PhotoMemory: Identifiable {
    let run: Run
    let yearsAgo: Int
    var id: UUID { run.id }
    var match: Match = .day
    enum Match: Equatable { case day, week, month, history, nearby }
    var title: String {
        let age = yearsAgo > 0 ? "\(yearsAgo) \(yearsAgo == 1 ? "year" : "years") ago" : "Earlier this year"
        switch match {
        case .day: return "\(age) today"
        case .week: return "\(age), around this day"
        case .month: return "\(age), this month"
        case .history: return "From your history"
        case .nearby: return "Back in this area"
        }
    }
    var cover: String? { run.memoryPhotoReferences.first }
}

enum PhotoMemories {
    /// Exact month/day anniversaries, not a rolling 365-day offset. February 29 only resurfaces
    /// on February 29; we don't silently call February 28 the same day. Calendar is injectable
    /// for deterministic tests and uses the reader's current timezone in the app.
    static func onThisDay(in runs: [Run], scope: ActivityScope, now: Date = Date(),
                          calendar: Calendar = .current, limit: Int = 5) -> [PhotoMemory] {
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        return runs.scoped(to: scope).compactMap { run -> PhotoMemory? in
            guard !run.isHiddenFromMemories, !run.memoryPhotoReferences.isEmpty else { return nil }
            let date = calendar.dateComponents([.year, .month, .day], from: run.startDate)
            guard date.month == today.month, date.day == today.day,
                  let year = date.year, let current = today.year, year < current else { return nil }
            return PhotoMemory(run: run, yearsAgo: current - year)
        }.sorted {
            if $0.run.startDate != $1.run.startDate { return $0.run.startDate > $1.run.startDate }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(max(0, limit)).map { $0 }
    }
}


extension PhotoMemories {
    struct Collection {
        let match: PhotoMemory.Match
        let memories: [PhotoMemory]
        var heading: String {
            switch match {
            case .day: return "On this day"
            case .week: return "Around this day"
            case .month: return "This month in your history"
            case .history: return "From your history"
            case .nearby: return "Near you"
            }
        }
        var detail: String {
            switch match {
            case .day: return "This date, across all your previous years."
            case .week: return "Within three days of this date, across previous years."
            case .month: return "More moments from this month in previous years."
            case .history: return "Past activities worth revisiting, with or without a photograph."
            case .nearby: return "Past activities that started within 25 km of your current location."
            }
        }
    }

    /// Expand only when the narrower photo set is empty. With no usable photos, activities
    /// themselves become memories. Date labels remain tied to the actual matching rule.
    static func discover(in runs: [Run], scope: ActivityScope, now: Date = Date(),
                         calendar: Calendar = .current, limit: Int = 8) -> Collection {
        let today = calendar.startOfDay(for: now)
        let current = calendar.dateComponents([.year, .month, .day], from: now)
        let eligible = runs.scoped(to: scope).filter { !$0.isHiddenFromMemories && $0.startDate < today }
            .sorted { $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate > $1.startDate }
        let previousYears = eligible.filter { calendar.component(.year, from: $0.startDate) < (current.year ?? 0) }
        let exact = previousYears.filter {
            let date = calendar.dateComponents([.month, .day], from: $0.startDate)
            return date.month == current.month && date.day == current.day
        }
        let week = previousYears.filter { run in
            let date = calendar.dateComponents([.month, .day], from: run.startDate)
            return [-1, 0, 1].contains { offset in
                let year = (current.year ?? 0) + offset
                guard let anniversary = calendar.date(from: DateComponents(year: year, month: date.month, day: date.day)) else { return false }
                let verified = calendar.dateComponents([.month, .day], from: anniversary)
                guard verified.month == date.month, verified.day == date.day else { return false }
                return abs(calendar.dateComponents([.day], from: today, to: anniversary).day ?? 999) <= 3
            }
        }
        let month = previousYears.filter { calendar.component(.month, from: $0.startDate) == current.month }
        let tiers: [(PhotoMemory.Match, [Run])] = [(.day, exact), (.week, week), (.month, month), (.history, eligible)]
        for photosOnly in [true, false] {
            for (match, candidates) in tiers {
                let selected = candidates.filter { !photosOnly || !$0.memoryPhotoReferences.isEmpty }
                if !selected.isEmpty {
                    return Collection(match: match, memories: selected.prefix(max(0, limit)).map {
                        PhotoMemory(run: $0, yearsAgo: max(0, (current.year ?? 0) - calendar.component(.year, from: $0.startDate)), match: match)
                    })
                }
            }
        }
        return Collection(match: .history, memories: [])
    }

    /// Uses start coordinates, not inferred city names. No network or reverse geocoding.
    static func nearby(in runs: [Run], scope: ActivityScope, location: CLLocation,
                       now: Date = Date(), calendar: Calendar = .current,
                       radius: CLLocationDistance = 25_000, limit: Int = 8) -> [PhotoMemory] {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 5_000,
              abs(location.timestamp.timeIntervalSince(now)) <= 300, radius > 0,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return [] }
        return runs.scoped(to: scope).filter { run in
            guard !run.isHiddenFromMemories, run.startDate < calendar.startOfDay(for: now),
                  let coordinate = run.startCoordinate, CLLocationCoordinate2DIsValid(coordinate) else { return false }
            return location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= radius
        }.sorted { $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate > $1.startDate }
            .prefix(max(0, limit)).map {
                PhotoMemory(run: $0, yearsAgo: max(0, calendar.component(.year, from: now) - calendar.component(.year, from: $0.startDate)), match: .nearby)
            }
    }
}
