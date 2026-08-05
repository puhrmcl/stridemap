import SwiftUI
import SwiftData

/// Switches between onboarding and the map depending on authentication state.
struct RootView: View {
    @Environment(StravaAuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Query private var runs: [Run]

    var body: some View {
        Group {
            if auth.isAuthenticated {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.gentle, value: auth.isAuthenticated)
        .task(id: auth.isAuthenticated) {
            // Auto-sync on first appearance after login.
            if auth.isAuthenticated && runs.isEmpty {
                await sync.sync()
            }
        }
    }
}
