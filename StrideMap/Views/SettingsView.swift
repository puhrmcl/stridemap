import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(StravaAuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var runs: [Run]

    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("unitSystem") private var unitSystem = UnitSystem.miles.rawValue

    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete all cached runs? You can re-sync from Strava.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Cache", role: .destructive) { deleteCache() }
            }
        }
    }

    private var accountSection: some View {
        Section("Strava") {
            if let athlete = auth.athlete, !athlete.displayName.isEmpty {
                LabeledContent("Connected as", value: athlete.displayName)
            } else {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Button {
                Task { await sync.sync() }
            } label: {
                HStack {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if sync.isSyncing { ProgressView().controlSize(.small) }
                    else if let last = sync.lastSyncDate {
                        Text(last.formatted(.relative(presentation: .named)))
                            .foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            .disabled(sync.isSyncing)

            Button("Disconnect Strava", role: .destructive) { auth.signOut() }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Units", selection: $unitSystem) {
                ForEach(UnitSystem.allCases) { Text($0.label).tag($0.rawValue) }
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            LabeledContent("Cached Runs", value: runs.count.formatted())

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export GPX", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    exportURL = try? GPXExporter.writeTemporaryFile(for: runs)
                } label: {
                    Label("Prepare GPX Export", systemImage: "square.and.arrow.up")
                }
                .disabled(runs.isEmpty)
            }

            Button("Delete Cache", role: .destructive) { showDeleteConfirm = true }
                .disabled(runs.isEmpty)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.shortVersion)
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
        } footer: {
            Text("StrideMap stores your runs on this device only. Strava data is fetched with read-only access.")
        }
    }

    private func deleteCache() {
        for run in runs { context.delete(run) }
        try? context.save()
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")
    }
}

private struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Data Stays Yours")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("""
                StrideMap connects to Strava using read-only OAuth access to fetch your \
                activities and their GPS routes. Your access token is stored securely in \
                the iOS Keychain. All run data is cached locally on this device using \
                on-device storage.

                StrideMap does not run its own servers, does not upload your data anywhere, \
                and does not share your information with third parties. Disconnecting Strava \
                or deleting the cache removes the data from this device.
                """)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
