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
    /// New users pick their activities and default view here before entering the app.
    @AppStorage("didCompleteSetup") private var didCompleteSetup = false
    /// Studio-first mode: Studio is the home page, the map becomes a popup.
    @AppStorage("studioIsHome") private var studioIsHome = false
    // Observed so the root re-renders when the user toggles activities to/from all-off.
    @AppStorage("includeRuns") private var includeRuns = true
    @AppStorage("includeHikes") private var includeHikes = true
    @AppStorage("includeWalks") private var includeWalks = false

    private var allActivitiesOff: Bool { !includeRuns && !includeHikes && !includeWalks }

    /// The brand splash covers the app on launch, then fades away.
    @State private var showSplash = true

    private var isReady: Bool {
        didCompleteOnboarding || healthKit.hasRequestedAuthorization || auth.isAuthenticated
    }

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            // Hold the logo briefly, then fade into the app.
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeInOut(duration: 0.5)) { showSplash = false }
        }
    }

    private var content: some View {
        Group {
            if isReady {
                if !didCompleteSetup || allActivitiesOff {
                    SetupView()
                        .transition(.opacity)
                } else if studioIsHome {
                    StudioHomeView(isHome: true)
                        .transition(.opacity)
                } else {
                    HomeView()
                        .transition(.opacity)
                }
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.gentle, value: isReady)
        .animation(Theme.gentle, value: studioIsHome)
        .animation(Theme.gentle, value: allActivitiesOff)
        .animation(Theme.gentle, value: didCompleteSetup)
        .task(id: isReady) {
            guard isReady else { return }
            // Import on first appearance, then keep observing for new workouts. Also run when
            // Strava was just connected but its full history hasn't been backfilled yet, so
            // maps attach to pre-existing runs without a manual "Sync Now".
            if runs.isEmpty || sync.needsStravaBackfill { await sync.sync() }
            // Backfill place names for located runs still missing them (e.g. a file/ZIP import in a
            // prior session that never ran a full sync): state/country fill instantly offline, and
            // cities continue filling via the bounded geocoder.
            await sync.enrichLocations()
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
