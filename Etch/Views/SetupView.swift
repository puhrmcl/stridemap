import SwiftUI

/// The first-run setup — and the recovery screen when every activity is switched off. New users
/// choose which activities to track and whether the app opens to the Map or Studio; either can be
/// changed later in Settings / Profile. Turning an activity on re-imports it; nothing is deleted.
struct SetupView: View {
    @Environment(SyncService.self) private var sync
    @Environment(\.colorScheme) private var scheme

    @AppStorage("includeRuns") private var includeRuns = true
    @AppStorage("includeHikes") private var includeHikes = true
    @AppStorage("includeWalks") private var includeWalks = false
    @AppStorage("studioIsHome") private var studioIsHome = false
    @AppStorage("didCompleteSetup") private var didCompleteSetup = false

    private var ground: Color { scheme == .dark ? Theme.Palette.ink : Theme.Palette.bone }
    private var allOff: Bool { !includeRuns && !includeHikes && !includeWalks }

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    header
                    activitiesCard
                    defaultViewCard
                    continueButton
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 44)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("BrandLogo")
                .resizable().scaledToFit().frame(height: 40)
                .accessibilityLabel("Etch")
            Text("Set Up Etch")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Choose what to track and where the app opens. You can change these anytime in Settings.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    // MARK: Activities

    private var activitiesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Activities")
            VStack(spacing: 0) {
                toggleRow("Runs", "figure.run", $includeRuns)
                rowDivider
                toggleRow("Hikes", "figure.hiking", $includeHikes)
                rowDivider
                toggleRow("Walks", "figure.walk", $includeWalks)
                rowDivider
                comingSoonRow("Cycling", "figure.outdoor.cycle")
            }
            .background(.regularMaterial, in: .rect(cornerRadius: 18))
        }
    }

    private func toggleRow(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding.onChange { on in if on { Task { await sync.sync() } } }) {
            Label(title, systemImage: icon)
                .font(.system(.body, design: .rounded).weight(.medium))
        }
        .tint(Theme.accent)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func comingSoonRow(_ title: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Coming soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.15), in: .capsule)
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Default view

    private var defaultViewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Opens to")
            Picker("Default view", selection: $studioIsHome) {
                Text("Map").tag(false)
                Text("Studio").tag(true)
            }
            .pickerStyle(.segmented)
            Text(studioIsHome
                 ? "Etch Studio is home; the map is a tap away in the corner."
                 : "The map is home; Studio lives in the menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
    }

    private var continueButton: some View {
        Button {
            didCompleteSetup = true
        } label: {
            Text("Get Started")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(allOff ? Color.gray.opacity(0.4) : Theme.accent, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(allOff)
        .padding(.top, 4)
    }

    // MARK: Bits

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var rowDivider: some View { Divider().padding(.leading, 54) }
}

private extension Binding where Value == Bool {
    /// Runs a side effect when the value changes.
    func onChange(_ action: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { wrappedValue }, set: { newValue in wrappedValue = newValue; action(newValue) })
    }
}
