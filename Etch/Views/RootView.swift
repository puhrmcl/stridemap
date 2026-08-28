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

    /// Whether *any* run exists — not the runs themselves.
    ///
    /// This was `@Query private var runs: [Run]`, used for a single `runs.isEmpty` check. That
    /// made the root view a dependant of every Run in the store, so the first launch — which
    /// imports a whole HealthKit history — re-evaluated `body` on each batch of inserts and tore
    /// down and rebuilt the entire content tree underneath, map and all, hundreds of times while
    /// the splash was fading. Fetching one row with no properties answers the same question and
    /// leaves the root still.
    @Query(Self.existenceProbe) private var anyRun: [Run]

    private static var existenceProbe: FetchDescriptor<Run> {
        var descriptor = FetchDescriptor<Run>()
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = []
        return descriptor
    }

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
            // Import on first appearance, then keep observing for new workouts. Also run when
            // Strava was just connected but its full history hasn't been backfilled yet, so
            // maps attach to pre-existing runs without a manual "Sync Now".
            if anyRun.isEmpty || sync.needsStravaBackfill { await sync.sync() }
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
