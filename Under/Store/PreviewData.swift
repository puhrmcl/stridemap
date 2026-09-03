import Foundation

#if DEBUG
extension UnderStore {
    /// Shared preview stores. Held as constants so a preview's view and its
    /// environment object are the same instance.
    static let previewCouple = UnderStore.preview(couple: true)
    static let previewSolo = UnderStore.preview(couple: false)

    /// A store with a couple and a fortnight of plausible days, for previews.
    static func preview(couple: Bool = true) -> UnderStore {
        let sam = Person(name: "Sam")
        let alex = Person(name: "Alex")
        let people = couple ? [sam, alex] : [sam]

        let calendar = Calendar.current
        var logs: [DayLog] = []
        let samDays: [Bucket] = [.none, .low, .none, .none, .mid, .low, .none, .none, .low, .none]
        let alexDays: [Bucket] = [.low, .none, .high, .none, .low, .low, .none, .mid, .none, .low]

        for offset in 0..<samDays.count {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let day = DayKey.key(from: date)
            logs.append(DayLog(personID: sam.id, day: day, bucket: samDays[offset]))
            if couple {
                logs.append(DayLog(personID: alex.id, day: day, bucket: alexDays[offset]))
            }
        }

        let state = AppState(hasCompletedOnboarding: true,
                             people: people,
                             activePersonID: sam.id,
                             logs: logs)
        return UnderStore(storage: MemoryStorage(state))
    }
}
#endif
