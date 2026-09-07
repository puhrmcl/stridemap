import Foundation

/// These operations only change Etch's associations. They never delete a Photos asset.
extension Run {
    var memoryPhotoReferences: [String] {
        photoReferences.filter { !memoryHiddenPhotoReferences.contains($0) && !rejectedPhotoReferences.contains($0) }
    }

    func attachPhotos(_ identifiers: [String], manually: Bool) {
        if manually { rejectedPhotoReferences.removeAll { identifiers.contains($0) } }
        for id in identifiers where !rejectedPhotoReferences.contains(id) && !photoReferences.contains(id) {
            photoReferences.append(id)
        }
        updatedAt = Date()
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
    var title: String { "\(yearsAgo) \(yearsAgo == 1 ? "year" : "years") ago today" }
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
