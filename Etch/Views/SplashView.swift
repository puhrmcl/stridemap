import SwiftUI

/// The brand splash shown briefly on launch: the Etch logo on the app's ground, fading up. The
/// logo asset is appearance-aware (navy wordmark in light, bone in dark), so the ground matches.
struct SplashView: View {
    @State private var appeared = false

    /// The icon's own deep navy — one splash in both modes, seamless with the system launch
    /// screen (which uses the same ground and the same cream wordmark).
    private static let ground = Color(red: 8 / 255, green: 30 / 255, blue: 54 / 255)

    var body: some View {
        ZStack {
            Self.ground.ignoresSafeArea()
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal, 48)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.96)
                .accessibilityLabel("Etch — Leave your mark")
        }
        .task {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }
}
