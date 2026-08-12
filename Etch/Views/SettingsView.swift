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
    @State private var connectError: String?

    var body: some View {
        NavigationStack {
            Form {
                sourcesSection
                syncSection
                appearanceSection
                routeDiagnosticsSection
                statesDiagnosticsSection
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
            .alert("Strava", isPresented: Binding(get: { connectError != nil }, set: { if !$0 { connectError = nil } })) {
                Button("OK", role: .cancel) { connectError = nil }
            } message: {
                Text(connectError ?? "")
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
        } catch StravaAuthService.AuthError.cancelled {
            // User dismissed the sign-in sheet — no error to show.
        } catch {
            // Surface everything else (not configured / redirect / server) so failures are
            // visible instead of the button silently doing nothing.
            connectError = error.localizedDescription
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

    /// Per-source route availability: how many runs from each app have a map. The tell for
    /// "is a missing map Nike's fault or Etch's?" — a source with 0 maps wrote no routes.
    private var routeBreakdown: [(source: String, total: Int, withMaps: Int)] {
        Dictionary(grouping: runs) { $0.displaySource.label }
            .map { (source: $0.key, total: $0.value.count, withMaps: $0.value.filter(\.hasRoute).count) }
            .sorted { $0.total > $1.total }
    }

    private var routeDiagnosticsSection: some View {
        Section {
            LabeledContent("Cached Runs", value: runs.count.formatted())
            LabeledContent("Runs with Maps", value: runs.filter(\.hasRoute).count.formatted())
            ForEach(routeBreakdown, id: \.source) { row in
                LabeledContent(row.source, value: "\(row.withMaps)/\(row.total) maps")
            }
        } header: {
            Text("Route Diagnostics")
        } footer: {
            Text("Maps come from GPS routes each app writes to Apple Health. If a source shows 0 maps, that app isn't saving routes to Health (e.g. Nike Run Club) — Etch can't map those without another source like Strava.")
        }
    }

    // Runs that carry a start coordinate — the input to the States/Cities maps.
    private var locatedRunCount: Int { runs.filter { $0.startLatitude != nil }.count }

    /// Distinct states the located runs fall in, by point-in-polygon. Pinpoints why the
    /// States map is blank: 0 map regions = boundary data missing from the build; 0 located
    /// runs = no GPS yet; regions and GPS present but 0 detected = attribution problem.
    private var detectedStateCount: Int {
        let boundaries = USStateBoundaries.shared
        guard !boundaries.boundaries.isEmpty else { return 0 }
        var names = Set<String>()
        for run in runs {
            if let coordinate = run.startCoordinate,
               let name = boundaries.region(containing: coordinate) {
                names.insert(name)
            }
        }
        return names.count
    }

    private var statesDiagnosticsSection: some View {
        Section {
            LabeledContent("US map regions", value: USStateBoundaries.shared.boundaries.count.formatted())
            LabeledContent("Runs with GPS", value: locatedRunCount.formatted())
            LabeledContent("States detected", value: detectedStateCount.formatted())
        } header: {
            Text("Map Coverage")
        } footer: {
            Text("The States map shades a state when a run started inside it. \"US map regions\" should be 51 (50 states + DC); if it's 0 the boundary data didn't ship. \"Runs with GPS\" is how many runs have a route to place — only these can be attributed to a state or city.")
        }
    }

    private var dataSection: some View {
        Section("Data") {

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
