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
    @State private var showFilters = false
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
                    activityFilterRow
                    row(title: "Settings", subtitle: "Account, units, sync, and more",
                        systemName: "gearshape") { showSettings = true }
                }

                Section {
                    AppFocusToggle(studioIsHome: $studioIsHome)
                        .padding(.vertical, 10)
                } header: {
                    Text("App Focus")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showFilters) { FilterView() }
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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The filter row between Search and Settings — opens the full Filters sheet (activity, date,
    /// distance, time, location, surface, race). The subtitle summarises what's currently applied.
    private var activityFilterRow: some View {
        Button { showFilters = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filters").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(filterSummary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    /// A short line naming what the filter is currently doing — the activity plus whether any
    /// further filter (date, distance, location, …) is narrowing the set.
    private var filterSummary: String {
        let scopeLabel = scope == .all ? "All activities" : scope.label
        return appModel.filter.isActive ? "\(scopeLabel) · filtered" : "\(scopeLabel) · all time"
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
