import SwiftUI
import SwiftData

/// Switches between onboarding and the map. The app is usable with Apple Health alone;
/// Strava is optional. Onboarding is shown until the user has connected at least one
/// source (or explicitly chosen to continue).
struct RootView: View {
    @Environment(StravaAuthService.self) private var auth
    @Environment(HealthKitService.self) private var healthKit
    @Environment(SyncService.self) private var sync
    @Environment(AppModel.self) private var appModel

    // Deliberately no `@Query` here. The root once fetched runs to decide whether to sync,
    // which made it a dependant of every Run in the store: the first launch re-evaluated `body`
    // on each batch of inserts and tore down the whole content tree, map and all, hundreds of
    // times while the splash faded. The launch sync is now unconditional, so the root needs to
    // know nothing about the library.

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    /// New users pick their activities and default view here before entering the app.
    @AppStorage("didCompleteSetup") private var didCompleteSetup = false
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
        // CI preview (ETCH_PREVIEW=<screen>): open the named surface on a synthetic history,
        // skipping the splash, onboarding, and a sync the simulator has no data for. Inert in
        // every normal launch.
        if PreviewHarness.isActive {
            PreviewHarnessView()
        } else {
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
    }

    private var content: some View {
        Group {
            if isReady {
                if !didCompleteSetup || allActivitiesOff {
                    SetupView()
                        .transition(.opacity)
                } else {
                    // One root with four destinations, replacing the `studioIsHome` fork.
                    //
                    // That preference asked people to choose which half of the app they wanted,
                    // and then honoured the choice by hiding the other half behind a modal. It is
                    // the kind of setting you add when the navigation cannot hold both things —
                    // so the fix was the navigation, not a better default.
                    EtchTabView()
                        .transition(.opacity)
                }
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.gentle, value: isReady)
        .animation(Theme.gentle, value: allActivitiesOff)
        .animation(Theme.gentle, value: didCompleteSetup)
        .task(id: isReady) {
            guard isReady else { return }
            // Import on every launch, then keep observing for new workouts. This used to run
            // only when the library was empty, which left the app entirely dependent on the
            // HealthKit observer firing — so a workout that landed while Etch was closed could
            // sit there unnoticed. The HealthKit read is anchored, so a launch with nothing new
            // costs one query per type and imports nothing.
            await sync.sync()
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
