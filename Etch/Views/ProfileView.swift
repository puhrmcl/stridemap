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

    /// The user's chosen profile photo (shared with the map search bar avatar).
    @AppStorage("profileImageData") private var profileImageData: Data?
    /// The local profile identity — shown on the hub and editable in the profile editor. Local
    /// only: no account system exists yet (identity/sync is a post-launch concern).
    @AppStorage("profileFirstName") private var firstName = ""
    @AppStorage("profileLastName") private var lastName = ""
    @AppStorage("profileHometown") private var hometown = ""
    @AppStorage("profileBio") private var bio = ""
    @State private var showEditor = false

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
            .sheet(isPresented: $showEditor) { ProfileEditorView() }
        }
    }

    private var fullName: String {
        [firstName, lastName].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The identity header: avatar, name, hometown, then an Edit Profile capsule that opens the
    /// editor (photo changes live there too — the old visible "Remove Photo" control is gone).
    private var header: some View {
        VStack(spacing: 14) {
            Button { showEditor = true } label: {
                ProfileAvatar(size: 96) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.15))
                        Image(systemName: "person.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile photo")

            VStack(spacing: 4) {
                if !fullName.isEmpty {
                    Text(fullName)
                        .font(.system(.title2, design: .default).weight(.bold))
                }
                if !hometown.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(hometown)
                        .font(.system(.subheadline, design: .default))
                        .foregroundStyle(.secondary)
                }
                if !bio.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 2)
                }
            }

            Button { showEditor = true } label: {
                Text("Edit Profile")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            HStack(spacing: 22) {
                stat(
                    value: Format.distanceValue(stats.totalDistanceMeters)
                        .formatted(.number.precision(.fractionLength(0))),
                    label: UnitSystem.current.distanceSuffix
                )
                Rectangle().fill(.secondary.opacity(0.3)).frame(width: 1, height: 30)
                stat(value: stats.totalRuns.formatted(), label: scope.countNoun)
            }
            .padding(.top, 6)
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
            Text(value).font(.system(.title2, design: .default).weight(.bold))
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

/// The profile editor — Cancel / Save over the avatar (with an Edit control for the photo),
/// stacked first/last name fields, hometown, and a 150-character bio with a live counter.
/// Text edits are staged locally and only committed on Save; photo changes apply immediately
/// (they're their own flow, with their own Remove).
private struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("profileImageData") private var profileImageData: Data?
    @AppStorage("profileFirstName") private var storedFirstName = ""
    @AppStorage("profileLastName") private var storedLastName = ""
    @AppStorage("profileHometown") private var storedHometown = ""
    @AppStorage("profileBio") private var storedBio = ""

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var hometown = ""
    @State private var bio = ""
    @State private var loaded = false

    @State private var showPhotoOptions = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?

    private let bioLimit = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    photoBlock
                    fieldSection("Name") { nameCard }
                    fieldSection("Hometown") {
                        boxed { TextField("City, State", text: $hometown).textInputAutocapitalization(.words) }
                    }
                    fieldSection("Bio", trailing: "\(bio.count)/\(bioLimit)") {
                        boxed {
                            TextField("\(bioLimit) characters", text: $bio, axis: .vertical)
                                .lineLimit(4...8)
                        }
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                firstName = storedFirstName
                lastName = storedLastName
                hometown = storedHometown
                bio = storedBio
            }
            .onChange(of: bio) { _, new in
                if new.count > bioLimit { bio = String(new.prefix(bioLimit)) }
            }
            .confirmationDialog("Profile Photo", isPresented: $showPhotoOptions) {
                Button("Choose Photo") { showPhotoPicker = true }
                if profileImageData != nil {
                    Button("Remove Photo", role: .destructive) { profileImageData = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem,
                          matching: .images, photoLibrary: .shared())
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let avatar = Self.avatarData(from: image) {
                        await MainActor.run { profileImageData = avatar }
                    }
                }
            }
        }
    }

    /// Avatar with "Edit" beneath — tapping either opens the photo options.
    private var photoBlock: some View {
        VStack(spacing: 8) {
            Button { showPhotoOptions = true } label: {
                VStack(spacing: 8) {
                    ProfileAvatar(size: 96) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.15))
                            Image(systemName: "person.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text("Edit")
                        .font(.system(.body, design: .default))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile photo")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// First and last name stacked in one bordered card, split by a hairline.
    private var nameCard: some View {
        VStack(spacing: 0) {
            TextField("First name", text: $firstName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 16).padding(.vertical, 15)
            Divider()
            TextField("Last name", text: $lastName)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 16).padding(.vertical, 15)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private func fieldSection<Content: View>(_ title: String, trailing: String? = nil,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(.headline, design: .default).weight(.bold))
                Spacer()
                if let trailing {
                    Text(trailing).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    /// A single bordered field container matching the name card's look.
    private func boxed<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 16).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }

    private func save() {
        storedFirstName = firstName.trimmingCharacters(in: .whitespaces)
        storedLastName = lastName.trimmingCharacters(in: .whitespaces)
        storedHometown = hometown.trimmingCharacters(in: .whitespaces)
        storedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }

    /// Downscale a picked photo to a small square-ish JPEG before storing it — app storage isn't
    /// for large blobs, and the avatar is only ever shown small.
    static func avatarData(from image: UIImage, maxDimension: CGFloat = 512) -> Data? {
        let maxSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(1, maxSide))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
