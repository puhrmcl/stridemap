import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// The account hub. A quick summary of the runner's totals, with Search and Settings living
/// here rather than crowding the map's bottom bar.
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]

    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showFilters = false
    @State private var showImport = false

    /// The user's chosen profile photo (shared with the map search bar avatar), and the picker
    /// selection that feeds it.
    @AppStorage("profileImageData") private var profileImageData: Data?
    @State private var photoItem: PhotosPickerItem?

    /// The scope the totals reflect — the user's app-wide selection, clamped back to All if the
    /// stored scope was hidden in Settings. The filter is always available here on the profile hub.
    private var scope: ActivityScope {
        ActivitySettings.isVisible(appModel.activityScope) ? appModel.activityScope : .all
    }

    /// Totals honour the activity filter and drop activities the user kept out of totals.
    private var stats: RunStatistics { RunStatistics(allRuns.scoped(to: scope).countingTotals) }

    var body: some View {
        @Bindable var appModel = appModel
        return NavigationStack {
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
                    row(title: "Import Activity", subtitle: "Bring in runs from other apps",
                        systemName: "square.and.arrow.down") { showImport = true }
                    row(title: "Settings", subtitle: "Account, units, sync, and more",
                        systemName: "gearshape") { showSettings = true }
                }

                Section {
                    AppFocusToggle(studioIsHome: $appModel.studioIsHome)
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
            .sheet(isPresented: $showImport) { NavigationStack { AddHistoryView() } }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            // Tap the avatar to choose a profile photo; long-press to remove it once set.
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                ProfileAvatar(size: 84) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15))
                        Image(systemName: "person.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Theme.accent, in: .circle)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                if profileImageData != nil {
                    Button(role: .destructive) { profileImageData = nil } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                }
            }
            // A visible remove control once a photo is set (the long-press menu isn't obvious).
            if profileImageData != nil {
                Button(role: .destructive) { profileImageData = nil } label: {
                    Text("Remove Photo")
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let avatar = avatarData(from: image) {
                    await MainActor.run { profileImageData = avatar }
                }
            }
        }
    }

    /// Downscale a picked photo to a small square-ish JPEG before storing it — app storage isn't
    /// for large blobs, and the avatar is only ever shown small.
    private func avatarData(from image: UIImage, maxDimension: CGFloat = 512) -> Data? {
        let maxSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(1, maxSide))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
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
