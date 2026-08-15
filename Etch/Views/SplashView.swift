import SwiftUI

/// The brand splash shown briefly on launch: the Etch logo on the app's ground, fading up. The
/// logo asset is appearance-aware (navy wordmark in light, bone in dark), so the ground matches.
struct SplashView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false

    private var ground: Color { scheme == .dark ? Theme.Palette.ink : Theme.Palette.bone }

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            Image("BrandLogo")
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
