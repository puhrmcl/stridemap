import SwiftUI

/// The brand splash shown briefly on launch. It must be pixel-identical to the system launch
/// screen — same ground, same wordmark at its natural size, same centring — so the handoff from
/// launch screen to app is invisible and the logo reads as ONE continuous moment. Any animation
/// or size difference here makes the logo appear twice.
struct SplashView: View {
    /// The icon's own deep navy — one splash in both modes, seamless with the system launch
    /// screen (which uses the same ground and the same cream wordmark).
    private static let ground = Color(red: 8 / 255, green: 30 / 255, blue: 54 / 255)

    var body: some View {
        ZStack {
            Self.ground.ignoresSafeArea()
            // Natural size (240×180pt @3x asset), exactly as UILaunchScreen renders it.
            Image("LaunchLogo")
                .accessibilityLabel("Etch — Leave your mark")
        }
    }
}
