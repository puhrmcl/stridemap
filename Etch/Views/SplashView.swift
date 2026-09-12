import SwiftUI

/// The letters grow out of the period, then settle into the exact authored wordmark.
struct SplashView: View {
    /// Includes a short settled hold before RootView fades into the app.
    static let presentationMilliseconds = 1950

    /// Frozen production states for the screenshot harness.
    var previewLine = false
    var previewStatic = false
    var previewDot = false
    var previewSettled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emergence: CGFloat = 0
    @State private var bloom: CGFloat = 1

    var body: some View {
        ZStack {
            Theme.Brand.ink.ignoresSafeArea()
            if reduceMotion || previewStatic {
                Image("LaunchLogo")
            } else {
                // Preserve the asset's natural bounds, matching the system launch-dot asset.
                Image("LaunchLogo").hidden()
                    .overlay {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let height = geometry.size.height
                            let period = UnitPoint(x: 0.96, y: 0.716)
                            let travel = CGSize(width: -width * 0.46 * (1 - emergence),
                                                height: -height * 0.216 * (1 - emergence))
                            // The dot stays solid while the letters expand leftward from it.
                            // Mask only the asset's existing period so it is never drawn twice.
                            Image("LaunchLogo").resizable()
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: width * 0.915)
                                }
                                .scaleEffect(x: 0.035 + 0.965 * emergence,
                                             y: 0.22 + 0.78 * emergence, anchor: period)
                                .blur(radius: 5 * (1 - emergence))
                                .opacity(emergence)
                                .offset(travel)
                            Circle().fill(Theme.Brand.blue)
                                .frame(width: width * 0.08, height: width * 0.08)
                                .scaleEffect(bloom)
                                .position(x: width * 0.96 + travel.width,
                                          y: height * 0.716 + travel.height)
                        }
                        .allowsHitTesting(false)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Etch — Leave your mark")
        .task(id: reduceMotion) {
            emergence = 0; bloom = 1
            guard !reduceMotion && !previewStatic && !previewDot else { return }
            if previewSettled { emergence = 1; return }
            if previewLine { emergence = 0.45; bloom = 1.45; return }
            do {
                try await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.32)) { bloom = 2.0 }
                try await Task.sleep(for: .milliseconds(320))
                withAnimation(.timingCurve(0.42, 0, 0.22, 1, duration: 1.20)) {
                    // One curve moves the letters and settles the dot together. Starting with
                    // zero velocity avoids the old sudden launch and separate spring snap.
                    emergence = 1
                    bloom = 1
                }
            } catch { return }
        }
    }
}
