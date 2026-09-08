import SwiftUI

/// The first frame uses the exact system-launch artwork. A fine line draws beneath the
/// wordmark, then retracts into its blue period. One gesture, finished before RootView fades.
struct SplashView: View {
    /// Freeze the production drawing for CI screenshots; normal launches always animate.
    var previewLine = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var erased: CGFloat = 0
    @State private var pulse: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.Brand.ink.ignoresSafeArea()
            Image("LaunchLogo")
                .overlay {
                    if !reduceMotion {
                        GeometryReader { geometry in
                            // Coordinates are normalized to the actual 720 x 335 launch asset.
                            // Keep the original image at its natural size, matching UILaunchScreen.
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let dot = CGPoint(x: width * 0.96, y: height * 0.716)
                            Path { path in
                                path.move(to: CGPoint(x: width * 0.025, y: height * 0.89))
                                path.addLine(to: CGPoint(x: dot.x - 8, y: height * 0.89))
                                path.addQuadCurve(to: dot, control: CGPoint(x: dot.x, y: height * 0.89))
                            }
                            .trim(from: erased, to: drawn)
                            .stroke(Theme.Brand.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            Circle()
                                .fill(Theme.Brand.blue)
                                .frame(width: width * 0.08, height: width * 0.08)
                                .scaleEffect(1 + pulse * 0.24)
                                .opacity(pulse)
                                .position(dot)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Etch — Leave your mark")
        }
        .task(id: reduceMotion) {
            drawn = 0; erased = 0; pulse = 0
            guard !reduceMotion else { return }
            if previewLine { drawn = 1; return }
            do {
                try await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeInOut(duration: 0.42)) { drawn = 1 }
                try await Task.sleep(for: .milliseconds(440))
                withAnimation(.easeInOut(duration: 0.32)) { erased = 1 }
                withAnimation(.easeOut(duration: 0.20).delay(0.20)) { pulse = 1 }
                try await Task.sleep(for: .milliseconds(420))
                withAnimation(.easeInOut(duration: 0.16)) { pulse = 0 }
            } catch { return }
        }
    }
}
