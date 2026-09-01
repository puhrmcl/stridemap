import SwiftUI

/// A help page that routes users to the one thing that makes activities flow into Etch: turning on
/// Apple Health sync in whatever apps they already use. Etch reads everything in Health, so there's
/// no per-app login — just enable each app's Health sync once.
struct ConnectAppsView: View {
    private struct Guide: Identifiable {
        let id = UUID()
        let name: String
        let symbol: String
        let steps: String
    }

    private let guides: [Guide] = [
        Guide(name: "COROS", symbol: "dot.radiowaves.left.and.right",
              steps: "COROS app → Profile → 3rd Party Apps → turn on Apple Health. Watch activities then sync to Health in the background."),
        Guide(name: "AllTrails", symbol: "figure.hiking",
              steps: "AllTrails → Profile → Settings → Apple Health, and allow it to write workouts. Completed hikes flow straight to Health — the most reliable route for AllTrails."),
        Guide(name: "Garmin Connect", symbol: "dot.radiowaves.left.and.right",
              steps: "Garmin Connect → More → Settings → Apple Health."),
        Guide(name: "Wahoo", symbol: "dot.radiowaves.left.and.right",
              steps: "Wahoo app → Profile → Apple Health."),
        Guide(name: "Komoot", symbol: "map",
              steps: "Komoot → Profile → Settings → Apple Health."),
        Guide(name: "Peloton", symbol: "figure.indoor.cycle",
              steps: "Peloton app → Settings → Apple Health."),
        Guide(name: "Nike Run Club", symbol: "figure.run.circle",
              steps: "Allow Nike Run Club in the Health app so it writes workouts, or import a Nike .zip in Add Your History.")
    ]

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Etch reads every workout in Apple Health, so there's nothing to log into. Turn on Apple Health sync in the apps you use and your runs, rides, and hikes flow in automatically — nothing is uploaded anywhere.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.pink)
                }
            }

            Section {
                ForEach(guides) { guide in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(guide.name, systemImage: guide.symbol)
                            .font(.body.weight(.semibold))
                        Text(guide.steps)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 30)
                    }
                    .padding(.vertical, 3)
                }
            } header: {
                Text("Turn on Apple Health sync")
            } footer: {
                Text("After enabling sync, open the app once so it pushes your history into Health, then tap Sync Now. Connect Strava directly (in Sources) for titles, gear, and race details on top.")
            }
        }
        .navigationTitle("Connect Your Apps")
        .navigationBarTitleDisplayMode(.inline)
    }
}
