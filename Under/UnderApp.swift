import SwiftUI

@main
struct UnderApp: App {
    @StateObject private var store: UnderStore
    private let notifications: NotificationCoordinator

    init() {
        let store = UnderStore()
        _store = StateObject(wrappedValue: store)
        notifications = NotificationCoordinator(store: store)
        Reminder.registerCategories()
        store.applyReminder()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
