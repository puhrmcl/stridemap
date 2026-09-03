import Foundation
import UserNotifications

/// One optional local notification in the evening. It reminds *you* to check in.
/// Nothing here ever fires because of what the other person logged.
enum Reminder {
    static let categoryID = "under.checkin"
    static let noneActionID = "under.action.none"
    static let lowActionID = "under.action.low"
    static let requestID = "under.daily"

    static func registerCategories() {
        let noSpend = UNNotificationAction(identifier: noneActionID, title: "No spend", options: [])
        let underTwentyFive = UNNotificationAction(identifier: lowActionID, title: "Under $25", options: [])
        let category = UNNotificationCategory(identifier: categoryID,
                                              actions: [noSpend, underTwentyFive],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func schedule(hour: Int, minute: Int, quickActions: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        let content = UNMutableNotificationContent()
        content.title = "Mark today."
        if quickActions {
            content.categoryIdentifier = categoryID
        }

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.add(UNNotificationRequest(identifier: requestID, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
    }
}

/// Lets a solo check-in finish straight from the notification.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private let store: UnderStore

    init(store: UnderStore) {
        self.store = store
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let store = self.store
        DispatchQueue.main.async {
            switch action {
            case Reminder.noneActionID: store.logForActivePerson(Bucket.none)
            case Reminder.lowActionID: store.logForActivePerson(Bucket.low)
            default: break
            }
            completionHandler()
        }
    }
}
