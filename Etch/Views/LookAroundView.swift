import SwiftUI
import MapKit

/// A "Look Around" entry for a coordinate — Apple's street-level imagery (the Maps binoculars).
/// Renders nothing until a scene is confirmed available at the coordinate, so it only appears
/// where there's coverage. Tapping opens the full interactive Look Around.
struct LookAroundButton: View {
    let coordinate: CLLocationCoordinate2D
    var title: String = "Look Around"

    @State private var scene: MKLookAroundScene?
    @State private var checked = false
    @State private var present = false

    var body: some View {
        Group {
            if let scene {
                Button { present = true } label: { card }
                    .buttonStyle(.plain)
                    .fullScreenCover(isPresented: $present) {
                        LookAroundScreen(scene: scene)
                    }
            }
        }
        .task(id: coordKey) { await load() }
    }

    private var card: some View {
        HStack(spacing: 14) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accentOnGlass)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text("See the street where you were")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: Theme.cardRadius))
        .contentShape(Rectangle())
    }

    private var coordKey: String { "\(coordinate.latitude),\(coordinate.longitude)" }

    private func load() async {
        guard !checked else { return }
        checked = true
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        scene = try? await request.scene
    }
}

/// An identifiable box so a fetched scene can drive a `.fullScreenCover(item:)`.
struct LookAroundScenePresentation: Identifiable {
    let id = UUID()
    let scene: MKLookAroundScene
}

/// Full-screen interactive Look Around with a close button.
struct LookAroundScreen: View {
    let scene: MKLookAroundScene
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            LookAroundContainer(scene: scene)
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }
}

/// Wraps `MKLookAroundViewController` for SwiftUI.
private struct LookAroundContainer: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let controller = MKLookAroundViewController(scene: scene)
        controller.pointOfInterestFilter = .excludingAll
        return controller
    }

    func updateUIViewController(_ controller: MKLookAroundViewController, context: Context) {
        controller.scene = scene
    }
}
