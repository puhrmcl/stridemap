import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(StravaAuthService.self) private var auth
    @Environment(HealthKitService.self) private var healthKit
    @Environment(SyncService.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var runs: [Run]

    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @AppStorage("unitSystem") private var unitSystem = UnitSystem.miles.rawValue

    @State private var exportURL: URL?
    @State private var showDeleteConfirm = false
    @State private var isConnectingStrava = false

    var body: some View {
        NavigationStack {
            Form {
                sourcesSection
                syncSection
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

    private var sourcesSection: some View {
        Section {
            // Apple Health — the primary source.
            HStack {
                Label("Apple Health", systemImage: "heart.fill")
                Spacer()
                if healthKit.isAvailable && healthKit.hasRequestedAuthorization {
                    Text("Connected").foregroundStyle(.green).font(.subheadline)
                } else if !healthKit.isAvailable {
                    Text("Unavailable").foregroundStyle(.secondary).font(.subheadline)
                } else {
                    Button("Connect") { Task { try? await healthKit.requestAuthorization() } }
                        .font(.subheadline)
                }
            }

            // Strava — optional enrichment.
            HStack {
                Label("Strava", systemImage: "figure.run")
                Spacer()
                if auth.isAuthenticated {
                    Menu {
                        Button("Disconnect", role: .destructive) { auth.signOut() }
                    } label: {
                        Text(auth.athlete?.displayName.isEmpty == false ? auth.athlete!.displayName : "Connected")
                            .foregroundStyle(.green).font(.subheadline)
                    }
                } else if isConnectingStrava {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Connect") { Task { await connectStrava() } }
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Sources")
        } footer: {
            Text("Runs come from Apple Health, including workouts recorded by Nike Run Club, Garmin, COROS, Polar, Wahoo, and others. Connect Strava to add titles, gear, and race details.")
        }
    }

    private var runsMissingMaps: Int {
        runs.filter { $0.healthKitID != nil && !$0.hasRoute }.count
    }

    private var syncSection: some View {
        Section {
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
            .disabled(sync.isSyncing || !sync.hasAnySource)

            if healthKit.isAvailable {
                Button {
                    Task { await sync.resyncHealthKitRoutes() }
                } label: {
                    HStack {
                        Label("Recover Missing Maps", systemImage: "map")
                        Spacer()
                        if sync.isRecoveringRoutes { ProgressView().controlSize(.small) }
                        else if runsMissingMaps > 0 {
                            Text("\(runsMissingMaps)")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }
                .disabled(sync.isRecoveringRoutes || sync.isSyncing)
            }
        } footer: {
            Text("Some apps save a run to Apple Health before its GPS route finishes syncing. Etch recovers those maps automatically; use this to check now.")
        }
    }

    private func connectStrava() async {
        isConnectingStrava = true
        defer { isConnectingStrava = false }
        do {
            try await auth.signIn()
            await sync.sync()
        } catch {
            if case StravaAuthService.AuthError.cancelled = error { return }
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
            LabeledContent("Runs with Maps", value: runs.filter(\.hasRoute).count.formatted())

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
            LabeledContent("Version", value: AppInfo.label)
            NavigationLink {
                PrivacyView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
        } footer: {
            Text("Etch stores your runs on this device only. Apple Health and Strava are both read-only.")
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
                Etch reads your running workouts and GPS routes from Apple Health \
                with read-only access. If you connect Strava, it is used only to enrich \
                those runs with titles, gear, and race details — its access token is stored \
                securely in the iOS Keychain. All run data is cached locally on this device.

                Etch does not run its own servers, does not upload your data anywhere, \
                and does not share your information with third parties. Disconnecting a source \
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
