import SwiftUI

/// Chooses the app's home screen: flip left for the activity **map**, right for **Etch Studio**.
/// The two sides are also tappable, and the active one lights up. Used in first-run setup and in
/// Profile.
struct AppFocusToggle: View {
    @Binding var studioIsHome: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                side(icon: "map.fill", title: "Activity Mapping",
                     active: !studioIsHome) { set(false) }

                Toggle("", isOn: $studioIsHome.animation(Theme.gentle))
                    .labelsHidden()
                    .tint(Theme.accent)
                    .fixedSize()

                side(icon: "photo.artframe", title: "Etch Studio",
                     active: studioIsHome) { set(true) }
            }

            Text(studioIsHome
                 ? "Etch Studio is your home screen — your activity map is a tap away in the corner."
                 : "Your activity map is your home screen — Etch Studio lives in the menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func set(_ value: Bool) {
        withAnimation(Theme.gentle) { studioIsHome = value }
    }

    private func side(icon: String, title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(active ? Theme.accent : Color.secondary)
            .opacity(active ? 1 : 0.5)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
