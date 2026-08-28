import SwiftUI

/// The brand splash shown briefly on launch.
///
/// The hard rule this screen has always had: its **first frame** must be pixel-identical to the
/// system launch screen — same ground, same wordmark at its natural size, same centring — or the
/// handoff shows and the logo appears twice. That rule is why this view had no animation at all.
///
/// It still holds, and the animation is built to respect it rather than around it: nothing moves
/// until `settled` flips a beat after appearance, so the frame that replaces the launch screen is
/// the launch screen. What follows is a single sheen drawn across the letterforms — light raking
/// across an engraved surface, which is the one motion this brand can make without inventing a
/// gesture. The mark itself never moves or resizes; only the light does.
///
/// Reduce Motion turns the sheen off and leaves the original static splash, which is the correct
/// fallback because the static splash was never a compromise.
struct SplashView: View {
    /// The icon's own deep navy — one splash in both modes, seamless with the system launch
    /// screen (which uses the same ground and the same cream wordmark).
    private static let ground = Color(red: 8 / 255, green: 30 / 255, blue: 54 / 255)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// False for the first beat, so the handoff frame is identical to the launch screen.
    @State private var settled = false
    /// Drives the sheen's travel, in multiples of the mark's width.
    @State private var sweep: CGFloat = -1

    var body: some View {
        ZStack {
            Self.ground.ignoresSafeArea()

            // Natural size (240×180pt @3x asset), exactly as UILaunchScreen renders it.
            Image("LaunchLogo")
                .overlay { if settled && !reduceMotion { sheen } }
                .accessibilityLabel("Etch — Leave your mark")
        }
        .task {
            guard !reduceMotion else { return }
            // Long enough that the launch screen has certainly been replaced by this view before
            // anything moves — the whole point of the delay.
            try? await Task.sleep(for: .milliseconds(260))
            settled = true
            withAnimation(.easeInOut(duration: 0.95)) { sweep = 1 }
        }
    }

    /// A band of light travelling across the wordmark, clipped to the letterforms.
    ///
    /// Masked by the artwork itself so the sheen only ever touches ink — a highlight crossing the
    /// navy around the mark would read as a screen wipe rather than as light on a surface. The
    /// gradient is mostly clear with a soft centre so the leading and trailing edges never show
    /// as hard lines.
    private var sheen: some View {
        GeometryReader { geo in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(width: geo.size.width * 0.55)
            .offset(x: sweep * geo.size.width * 1.3)
        }
        .mask {
            Image("LaunchLogo")
        }
        .allowsHitTesting(false)
    }
}
