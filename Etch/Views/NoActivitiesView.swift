import SwiftUI

/// Shown when every activity type is turned off — the app has nothing to display, so it guides the
/// user to switch at least one back on. Turning any type on re-enters the app immediately (the runs
/// were only hidden, never deleted).
struct NoActivitiesView: View {
    @Environment(SyncService.self) private var sync
    @Environment(\.colorScheme) private var scheme

    @AppStorage("includeRuns") private var includeRuns = true
    @AppStorage("includeHikes") private var includeHikes = true
    @AppStorage("includeWalks") private var includeWalks = false

    private var ground: Color { scheme == .dark ? Theme.Palette.ink : Theme.Palette.bone }

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            VStack(spacing: 26) {
                Spacer()

                Image(systemName: "figure.mixed.cardio")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                VStack(spacing: 8) {
                    Text("Choose Your Activities")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Turn on at least one activity to see your maps, totals, and art.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 36)

                VStack(spacing: 0) {
                    toggleRow("Runs", "figure.run", $includeRuns)
                    Divider().padding(.leading, 54)
                    toggleRow("Hikes", "figure.hiking", $includeHikes)
                    Divider().padding(.leading, 54)
                    toggleRow("Walks", "figure.walk", $includeWalks)
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 18))
                .padding(.horizontal, 28)

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func toggleRow(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding.onChange { on in if on { Task { await sync.sync() } } }) {
            Label(title, systemImage: icon)
                .font(.system(.body, design: .rounded).weight(.medium))
        }
        .tint(Theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }
}

private extension Binding where Value == Bool {
    /// Runs a side effect when the value changes to a new value.
    func onChange(_ action: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { wrappedValue }, set: { newValue in wrappedValue = newValue; action(newValue) })
    }
}
