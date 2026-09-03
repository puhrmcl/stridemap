import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: UnderStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.state.hasCompletedOnboarding {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            // A day rolls over — and locks — at the user's own midnight.
            if phase == .active { store.refreshToday() }
        }
    }
}

#if DEBUG
#Preview {
    RootView().environmentObject(UnderStore.previewCouple)
}
#endif
