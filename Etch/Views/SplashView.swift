import SwiftUI

/// The system launch dot becomes the wordmark's period as a circular reveal opens the logo.
struct SplashView: View {
    /// Frozen production states for the screenshot harness.
    var previewLine = false
    var previewStatic = false
    var previewDot = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 0
    @State private var bloom: CGFloat = 1

    var body: some View {
        ZStack {
            Theme.Brand.ink.ignoresSafeArea()
            Image("LaunchLogo")
                .mask {
                    if reduceMotion || previewStatic { Rectangle() }
                    else {
                        GeometryReader { geometry in
                            Circle()
                                .frame(width: geometry.size.width * 2.4 * reveal,
                                       height: geometry.size.width * 2.4 * reveal)
                                .position(x: geometry.size.width * (0.5 + 0.46 * reveal),
                                          y: geometry.size.height * (0.5 + 0.216 * reveal))
                        }
                    }
                }
                .overlay {
                    if !reduceMotion && !previewStatic {
                        GeometryReader { geometry in
                            Circle().fill(Theme.Brand.blue)
                                .frame(width: geometry.size.width * 0.08, height: geometry.size.width * 0.08)
                                .scaleEffect(bloom)
                                .opacity(1 - reveal)
                                .position(x: geometry.size.width * (0.5 + 0.46 * reveal),
                                          y: geometry.size.height * (0.5 + 0.216 * reveal))
                        }.allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Etch — Leave your mark")
        }
        .task(id: reduceMotion) {
            reveal = 0; bloom = 1
            guard !reduceMotion && !previewStatic && !previewDot else { return }
            if previewLine { reveal = 0.5; bloom = 1.6; return }
            do {
                try await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.22)) { bloom = 2.2 }
                try await Task.sleep(for: .milliseconds(180))
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.65)) {
                    reveal = 1; bloom = 1
                }
            } catch { return }
        }
    }
}
