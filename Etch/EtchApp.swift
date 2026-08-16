import SwiftUI
import SwiftData

@main
struct EtchApp: App {

    /// One shared container for the whole app.
    let modelContainer: ModelContainer

    @State private var auth = StravaAuthService.shared
    @State private var healthKit: HealthKitService
    @State private var appModel = AppModel()
    @State private var sync: SyncService

    @AppStorage("appearance") private var appearance: String = Appearance.system.rawValue

    init() {
        // Migrate installs from before the setup step existed: anyone who already finished the old
        // onboarding is considered set up, so they aren't sent back through the new setup screen.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "didCompleteSetup") == nil {
            defaults.set(defaults.bool(forKey: "didCompleteOnboarding"), forKey: "didCompleteSetup")
        }

        do {
            let container = try ModelContainer(for: Run.self, SavedPoster.self)
            self.modelContainer = container
            let health = HealthKitService()
            _healthKit = State(initialValue: health)
            _sync = State(
                initialValue: SyncService(
                    healthKit: health,
                    auth: StravaAuthService.shared,
                    context: container.mainContext
                )
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(healthKit)
                .environment(appModel)
                .environment(sync)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .tint(Theme.accent)
        }
        .modelContainer(modelContainer)
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
