import SwiftUI
import SwiftData

@main
struct EtchApp: App {

    /// One shared container for the whole app.
    let modelContainer: ModelContainer

    /// Set when the on-disk library could not be opened. The app then runs against an in-memory
    /// store and says so, rather than pretending an empty library is the user's.
    let storeFailure: Error?

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

        // Adopt the last-known-good served configuration before the first view renders, so
        // prices and availability never flash a compiled value and then correct themselves.
        RemoteConfigService.loadCached()

        // A store that will not open is no longer a crash. Once there are real libraries on real
        // devices, `fatalError` here is an app that cannot be launched at all by the people with
        // the most to lose, and no route to telling them why.
        let opening = StoreOpening.open()
        self.modelContainer = opening.container
        self.storeFailure = opening.failure
        let health = HealthKitService()
        _healthKit = State(initialValue: health)
        _sync = State(
            initialValue: SyncService(
                healthKit: health,
                auth: StravaAuthService.shared,
                context: opening.container.mainContext
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let storeFailure {
                    StoreUnavailableView(error: storeFailure)
                } else {
                    RootView()
                }
            }
                .environment(auth)
                .environment(healthKit)
                .environment(appModel)
                .environment(sync)
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
                .tint(Theme.accent)
                // Refresh the served configuration each launch; a failure silently keeps the
                // cached (or compiled) document.
                .task { await RemoteConfigService.refresh() }
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
