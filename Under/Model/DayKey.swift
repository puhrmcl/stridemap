import Foundation

/// Days are keyed by the *local* calendar date, which is what makes "locks at
/// midnight" mean the same thing as the user's own midnight. Built from
/// `Calendar` components rather than a formatter so there is no locale or
/// time-zone drift in the stored key.
enum DayKey {
    static func key(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let numbers = key.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        var parts = DateComponents()
        parts.year = numbers[0]
        parts.month = numbers[1]
        parts.day = numbers[2]
        return calendar.date(from: parts)
    }

    static func today(_ calendar: Calendar = .current) -> String {
        key(from: Date(), calendar: calendar)
    }

    /// Every day key in the calendar week containing `date`.
    static func week(of date: Date, calendar: Calendar = .current) -> [String] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        var keys: [String] = []
        var cursor = interval.start
        while cursor < interval.end {
            keys.append(key(from: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }
}
