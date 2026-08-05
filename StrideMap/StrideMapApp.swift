import SwiftUI
import SwiftData

@main
struct StrideMapApp: App {

    /// One shared container for the whole app.
    let modelContainer: ModelContainer

    @State private var auth = StravaAuthService.shared
    @State private var appModel = AppModel()
    @State private var sync: SyncService

    @AppStorage("appearance") private var appearance: String = Appearance.system.rawValue

    init() {
        do {
            let container = try ModelContainer(for: Run.self)
            self.modelContainer = container
            _sync = State(
                initialValue: SyncService(
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
