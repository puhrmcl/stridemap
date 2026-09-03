import Foundation

/// Everything Under keeps. It is small on purpose: people, their day logs, and a
/// reminder time. No amounts, no notes, no categories, no transactions.
struct AppState: Codable, Equatable {
    var hasCompletedOnboarding: Bool
    var people: [Person]
    var activePersonID: UUID?
    var logs: [DayLog]
    var reminder: ReminderSettings

    init(hasCompletedOnboarding: Bool = false,
         people: [Person] = [],
         activePersonID: UUID? = nil,
         logs: [DayLog] = [],
         reminder: ReminderSettings = ReminderSettings()) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.people = people
        self.activePersonID = activePersonID
        self.logs = logs
        self.reminder = reminder
    }

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, people, activePersonID, logs, reminder
    }

    // Tolerant decoding so a state file written by an older build still opens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        people = try container.decodeIfPresent([Person].self, forKey: .people) ?? []
        activePersonID = try container.decodeIfPresent(UUID.self, forKey: .activePersonID)
        logs = try container.decodeIfPresent([DayLog].self, forKey: .logs) ?? []
        reminder = try container.decodeIfPresent(ReminderSettings.self, forKey: .reminder) ?? ReminderSettings()
    }
}

/// One optional evening nudge, for you, to check in.
struct ReminderSettings: Codable, Equatable {
    var isOn: Bool
    var hour: Int
    var minute: Int

    init(isOn: Bool = true, hour: Int = 21, minute: Int = 0) {
        self.isOn = isOn
        self.hour = hour
        self.minute = minute
    }

    private enum CodingKeys: String, CodingKey { case isOn, hour, minute }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        hour = try container.decodeIfPresent(Int.self, forKey: .hour) ?? 21
        minute = try container.decodeIfPresent(Int.self, forKey: .minute) ?? 0
    }
}
