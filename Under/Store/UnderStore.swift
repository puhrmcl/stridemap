import Foundation
import SwiftUI

/// The single source of truth. Deliberately un-isolated so notification
/// callbacks can reach it; every mutation funnels through here and lands on the
/// main queue.
final class UnderStore: ObservableObject {
    @Published private(set) var state: AppState
    /// The current local day, refreshed when the app comes forward. Views read
    /// this so a day rolls over (and locks) at the user's own midnight.
    @Published private(set) var today: String

    private let storage: StateStorage
    private let calendar: Calendar
    /// "day|personID" -> bucket, so calendar cells are a dictionary hit.
    private var index: [String: Bucket] = [:]

    init(storage: StateStorage = UserDefaultsStorage(), calendar: Calendar = .current) {
        self.storage = storage
        self.calendar = calendar
        self.state = storage.load() ?? AppState()
        self.today = DayKey.today(calendar)
        rebuildIndex()
    }

    // MARK: - People

    var people: [Person] { state.people }
    var isCouple: Bool { state.people.count >= 2 }

    var activePerson: Person? {
        if let id = state.activePersonID, let match = state.people.first(where: { $0.id == id }) {
            return match
        }
        return state.people.first
    }

    var partner: Person? {
        guard let active = activePerson else { return nil }
        return state.people.first(where: { $0.id != active.id })
    }

    /// A name is never blank in the UI, even mid-edit in Settings.
    func displayName(_ person: Person) -> String {
        if !person.trimmedName.isEmpty { return person.trimmedName }
        if state.people.first?.id == person.id { return "You" }
        return "Partner"
    }

    func person(_ id: UUID) -> Person? {
        state.people.first(where: { $0.id == id })
    }

    func setActivePerson(_ id: UUID) {
        guard state.people.contains(where: { $0.id == id }) else { return }
        mutate { $0.activePersonID = id }
    }

    func rename(_ id: UUID, to name: String) {
        guard let position = state.people.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.people[position].name = name }
    }

    /// Second person joins. Their log starts empty; nobody logs for anybody else.
    func addPartner(named name: String = "") {
        guard state.people.count < 2 else { return }
        mutate { $0.people.append(Person(name: name)) }
    }

    /// Dropping a partner is allowed. Their days go with them. Whoever is
    /// checking in stays — they are the one holding the phone.
    func removePartner() {
        guard state.people.count > 1, let keeper = activePerson else { return }
        mutate { draft in
            draft.people = [keeper]
            draft.activePersonID = keeper.id
            draft.logs.removeAll { log in log.personID != keeper.id }
        }
    }

    // MARK: - Onboarding

    func completeOnboarding(names: [String]) {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let people = cleaned.isEmpty ? [Person(name: "You")] : cleaned.map { Person(name: $0) }
        mutate {
            $0.people = people
            $0.activePersonID = people.first?.id
            $0.hasCompletedOnboarding = true
        }
    }

    // MARK: - Logs

    func bucket(for personID: UUID, on day: String) -> Bucket? {
        index[Self.indexKey(day: day, person: personID)]
    }

    func todayBucket(for personID: UUID) -> Bucket? {
        bucket(for: personID, on: today)
    }

    /// One check-in per person per day, editable by that person until local
    /// midnight. Any other day is closed.
    func log(_ bucket: Bucket, for personID: UUID, on day: String? = nil) {
        let target = day ?? today
        guard target == DayKey.today(calendar) else { return }
        guard state.people.contains(where: { $0.id == personID }) else { return }
        mutate { draft in
            if let position = draft.logs.firstIndex(where: { $0.personID == personID && $0.day == target }) {
                draft.logs[position].bucket = bucket
                draft.logs[position].loggedAt = Date()
            } else {
                draft.logs.append(DayLog(personID: personID, day: target, bucket: bucket))
            }
        }
    }

    func logForActivePerson(_ bucket: Bucket) {
        guard let active = activePerson else { return }
        log(bucket, for: active.id)
    }

    // MARK: - Streak & counts

    /// Consecutive quiet days for one person, ending today — or ending
    /// yesterday while today is still unlogged, because an evening that hasn't
    /// happened yet is not a broken streak.
    func streak(for personID: UUID, asOf date: Date = Date()) -> Int {
        var cursor = calendar.startOfDay(for: date)
        if bucket(for: personID, on: DayKey.key(from: cursor, calendar: calendar)) == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while true {
            guard let logged = bucket(for: personID, on: DayKey.key(from: cursor, calendar: calendar)),
                  logged.isQuiet else { return count }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return count }
            cursor = previous
        }
    }

    /// Your quiet days this week. A count of days, never an estimate of dollars.
    func quietDays(for personID: UUID, inWeekOf date: Date = Date()) -> Int {
        DayKey.week(of: date, calendar: calendar).reduce(into: 0) { total, day in
            if bucket(for: personID, on: day)?.isQuiet == true { total += 1 }
        }
    }

    // MARK: - Reminder

    func setReminder(on isOn: Bool) {
        mutate { $0.reminder.isOn = isOn }
        applyReminder()
    }

    func setReminderTime(hour: Int, minute: Int) {
        mutate {
            $0.reminder.hour = hour
            $0.reminder.minute = minute
        }
        applyReminder()
    }

    /// Quick actions only make sense solo — nobody answers for the other person.
    func applyReminder() {
        if state.reminder.isOn {
            Reminder.schedule(hour: state.reminder.hour,
                              minute: state.reminder.minute,
                              quickActions: !isCouple)
        } else {
            Reminder.cancel()
        }
    }

    // MARK: - Day rollover

    func refreshToday() {
        let current = DayKey.today(calendar)
        if current != today { today = current }
    }

    // MARK: - Plumbing

    private func mutate(_ change: (inout AppState) -> Void) {
        var draft = state
        change(&draft)
        guard draft != state else { return }
        state = draft
        rebuildIndex()
        storage.save(draft)
    }

    private func rebuildIndex() {
        var built: [String: Bucket] = [:]
        for log in state.logs {
            built[Self.indexKey(day: log.day, person: log.personID)] = log.bucket
        }
        index = built
    }

    private static func indexKey(day: String, person: UUID) -> String {
        day + "|" + person.uuidString
    }
}
