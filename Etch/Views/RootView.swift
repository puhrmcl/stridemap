import SwiftUI
import SwiftData

/// Switches between onboarding and the map. The app is usable with Apple Health alone;
/// Strava is optional. Onboarding is shown until the user has connected at least one
/// source (or explicitly chosen to continue).
struct RootView: View {
    @Environment(StravaAuthService.self) private var auth
    @Environment(HealthKitService.self) private var healthKit
    @Environment(SyncService.self) private var sync
    @Query private var runs: [Run]

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false

    private var isReady: Bool {
        didCompleteOnboarding || healthKit.hasRequestedAuthorization || auth.isAuthenticated
    }

    var body: some View {
        Group {
            if isReady {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.gentle, value: isReady)
        .task(id: isReady) {
            guard isReady else { return }
            // Import on first appearance, then keep observing for new workouts. Also run when
            // Strava was just connected but its full history hasn't been backfilled yet, so
            // maps attach to pre-existing runs without a manual "Sync Now".
            if runs.isEmpty || sync.needsStravaBackfill { await sync.sync() }
            healthKit.startObserving {
                Task { @MainActor in await sync.sync() }
            }
            // Separately observe routes so a map that finishes syncing after its workout
            // (e.g. Nike Run Club) is recovered without a full re-import.
            healthKit.startObservingRoutes {
                Task { @MainActor in await sync.recoverMissingRoutes() }
            }
        }
    }
}
