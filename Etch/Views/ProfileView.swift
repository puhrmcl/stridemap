import SwiftUI
import SwiftData

/// The account hub. A quick summary of the runner's totals, with Search and Settings living
/// here rather than crowding the map's bottom bar.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]

    @State private var showSearch = false
    @State private var showSettings = false
    @AppStorage("studioIsHome") private var studioIsHome = false

    /// The scope the totals reflect — the user's app-wide selection, clamped back to All if the
    /// stored scope was hidden in Settings. The filter is always available here on the profile hub.
    private var scope: ActivityScope {
        ActivitySettings.isVisible(appModel.activityScope) ? appModel.activityScope : .all
    }

    /// Totals honour the activity filter and drop activities the user kept out of totals.
    private var stats: RunStatistics { RunStatistics(allRuns.scoped(to: scope).countingTotals) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    row(title: "Search", subtitle: "Find a run by name, place, or date",
                        systemName: "magnifyingglass") { showSearch = true }
                    row(title: "Settings", subtitle: "Account, units, sync, and more",
                        systemName: "gearshape") { showSettings = true }
                }

                Section {
                    Toggle(isOn: $studioIsHome.animation(Theme.gentle)) {
                        HStack(spacing: 14) {
                            Image(systemName: "photo.artframe")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Studio as Home").font(.body.weight(.semibold))
                                Text("Make Studio the main screen").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Opens the app straight into Etch Studio, with the map a tap away in the corner. Timeline and Achievements are tucked away. Turn off to return to the map as home.")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15)).frame(width: 84, height: 84)
                Image(systemName: "person.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 22) {
                stat(
                    value: Format.distanceValue(stats.totalDistanceMeters)
                        .formatted(.number.precision(.fractionLength(0))),
                    label: UnitSystem.current.distanceSuffix
                )
                Rectangle().fill(.secondary.opacity(0.3)).frame(width: 1, height: 30)
                stat(value: stats.totalRuns.formatted(), label: scope.countNoun)
            }
            // The activity filter always lives on the profile hub.
            scopeFilter
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// A chip that names and switches the activity filter, mirroring the app-wide scope.
    private var scopeFilter: some View {
        Menu {
            Picker("Activity", selection: scopeBinding) {
                ForEach(ActivitySettings.visibleScopes) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: scope.icon).font(.system(size: 13, weight: .semibold))
                Text(scope == .all ? "All Activities" : scope.label)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background(.regularMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var scopeBinding: Binding<ActivityScope> {
        Binding(
            get: { scope },
            set: { newValue in withAnimation(Theme.gentle) { appModel.activityScope = newValue } }
        )
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold))
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
    }

    private func row(title: String, subtitle: String, systemName: String,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
