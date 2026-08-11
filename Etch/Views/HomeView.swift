import SwiftUI
import SwiftData

/// Full-screen map with floating glass controls. The map is the product; chrome floats.
struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SyncService.self) private var sync
    @Query(sort: \Run.startDate, order: .reverse) private var allRuns: [Run]

    private var stats: RunStatistics { RunStatistics(allRuns) }

    /// Runs passing the active filter.
    private var visibleRuns: [Run] {
        let prs = appModel.filter.mode == .prs ? stats.prRunIDs : []
        return allRuns.filter { appModel.filter.matches($0, isPR: prs.contains($0.id)) }
    }

    private var visibleStats: RunStatistics { RunStatistics(visibleRuns) }

    var body: some View {
        @Bindable var appModel = appModel

        ZStack {
            RunMapView(
                runs: visibleRuns,
                selectedRunID: $appModel.selectedRunID,
                command: $appModel.command
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                HStack {
                    Spacer()
                    GlassIconButton(systemName: "location.fill") {
                        appModel.recenterOnUser()
                    }
                }
                .padding(.bottom, 10)
                bottomBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if allRuns.isEmpty {
                emptyOrSyncing
            }
        }
        // A single sheet for both surfaces and the run detail. Two `.sheet` modifiers — even
        // on different views — can leave one flaky; one sheet driven by one binding is
        // reliable, so the bottom buttons always present on the first tap.
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case .surface(let surface):
                surfaceView(for: surface)
            case .run(let id):
                if let run = allRuns.first(where: { $0.id == id }) {
                    RunDetailView(run: run)
                        .presentationDetents([.medium, .large])
                        .presentationBackground(.regularMaterial)
                }
            }
        }
    }

    /// The one thing presented over the map: a surface (bottom buttons) or a selected run.
    private enum ActiveSheet: Identifiable {
        case surface(AppModel.Surface)
        case run(UUID)
        var id: String {
            switch self {
            case .surface(let surface): return "surface-\(surface.rawValue)"
            case .run(let id): return "run-\(id.uuidString)"
            }
        }
    }

    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if let surface = appModel.presentedSurface { return .surface(surface) }
                if let id = appModel.selectedRunID { return .run(id) }
                return nil
            },
            set: { newValue in
                switch newValue {
                case .surface(let surface):
                    appModel.presentedSurface = surface
                case .run(let id):
                    appModel.selectedRunID = id
                case nil:
                    appModel.presentedSurface = nil
                    appModel.selectedRunID = nil
                }
            }
        )
    }

    // MARK: Top — totals + mode toggles

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                GlassPill(
                    title: UnitSystem.current.distanceSuffix,
                    value: Format.distanceValue(visibleStats.totalDistanceMeters)
                        .formatted(.number.precision(.fractionLength(0))),
                    systemName: "point.topleft.down.to.point.bottomright.curvepath"
                )
                GlassPill(
                    title: "runs",
                    value: visibleStats.totalRuns.formatted(),
                    systemName: "figure.run"
                )
                Spacer()
                if sync.isSyncing {
                    GlassContainer(padding: 10, cornerRadius: 18) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Syncing").font(.caption.weight(.medium))
                        }
                    }
                }
            }

            modeSelector
        }
    }

    private var modeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RunFilter.Mode.allCases) { mode in
                    let selected = appModel.filter.mode == mode
                    Button {
                        var f = appModel.filter
                        f.mode = mode
                        appModel.setFilter(f)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.symbol).font(.caption)
                            Text(mode.rawValue).font(.system(.subheadline, design: .rounded).weight(.semibold))
                        }
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accent)
                            } else {
                                Capsule().fill(.clear).glassBackground(cornerRadius: 20)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: Bottom — navigation controls

    private var bottomBar: some View {
        HStack(spacing: 10) {
            controlButton(icon: "magnifyingglass", surface: .search)
            controlButton(icon: "line.3.horizontal.decrease", surface: .filters, active: appModel.filter.isActive)
            controlButton(icon: "calendar", surface: .timeline)
            controlButton(icon: "sparkles", surface: .explore)
            controlButton(icon: "mappin.and.ellipse", surface: .travel)
            Spacer()
            controlButton(icon: "gearshape", surface: .settings)
        }
    }

    private func controlButton(icon: String, surface: AppModel.Surface, active: Bool = false) -> some View {
        GlassIconButton(systemName: icon, isActive: active) {
            appModel.presentedSurface = surface
        }
    }

    // MARK: Empty / syncing state

    private var emptyOrSyncing: some View {
        VStack(spacing: 12) {
            if sync.isSyncing {
                ProgressView()
                Text(syncingLabel)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "figure.run.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No runs yet")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Button("Sync Now") {
                    Task { await sync.sync() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .padding(28)
        .glassBackground(cornerRadius: Theme.cardRadius)
    }

    private var syncingLabel: String {
        if case .syncing(let imported) = sync.status, imported > 0 {
            return "Importing runs… \(imported)"
        }
        return "Importing your runs…"
    }

    // MARK: Sheet plumbing

    @ViewBuilder
    private func surfaceView(for surface: AppModel.Surface) -> some View {
        switch surface {
        case .filters: FilterView()
        case .timeline: TimelineView()
        case .explore: ExploreView()
        case .travel: TravelMapView()
        case .yearInReview: YearInReviewView(year: stats.years.first ?? Calendar.current.component(.year, from: Date()))
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
}
