import SwiftUI
import SwiftData

/// Filter the map by date range, surface, and location.
struct FilterView: View {
    /// True when pushed inside the Explore hub's navigation stack (no own NavigationStack).
    var embedded: Bool = false
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query private var allRuns: [Run]

    @State private var draft = RunFilter()
    @State private var scopeDraft: ActivityScope = .all
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEnd = Date()
    @State private var useCustom = false
    // Distance (metres) and moving-time (seconds) range, held as sliders; the extremes map to
    // "no bound" on apply.
    @State private var distLo: Double = 0
    @State private var distHi: Double = 0
    @State private var durLo: Double = 0
    @State private var durHi: Double = 0

    private var stats: RunStatistics { RunStatistics(allRuns) }

    /// Upper bounds for the range sliders, taken from the data (with sane floors).
    private var maxDistance: Double { max(stats.longestRun?.distance ?? 1609, 1609) }
    private var maxDuration: Double { Double(max(stats.longestDurationRun?.movingTime ?? 3600, 600)) }

    var body: some View {
        NavRoot(embedded) {
            Form {
                activitySection
                dateSection
                distanceSection
                timeSection
                surfaceSection
                locationSection
                resetSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { apply() }.fontWeight(.semibold)
                }
            }
            .onAppear { seed() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func seed() {
        draft = appModel.filter
        scopeDraft = ActivitySettings.isVisible(appModel.activityScope) ? appModel.activityScope : .all
        distLo = draft.minDistance ?? 0
        distHi = draft.maxDistance ?? maxDistance
        durLo = Double(draft.minDuration ?? 0)
        durHi = Double(draft.maxDuration ?? Int(maxDuration))
        if case .custom = draft.dateRange { useCustom = true }
    }

    private var activitySection: some View {
        Section("Activity") {
            Picker("Activity", selection: $scopeDraft) {
                ForEach(ActivitySettings.visibleScopes) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
        }
    }

    private var distanceSection: some View {
        Section("Distance") {
            LabeledContent("Minimum", value: distLo <= 0 ? "Any" : Format.distance(distLo, decimals: 1))
            Slider(value: $distLo, in: 0...maxDistance).tint(Theme.accent)
            LabeledContent("Maximum", value: distHi >= maxDistance ? "No limit" : Format.distance(distHi, decimals: 1))
            Slider(value: $distHi, in: 0...maxDistance).tint(Theme.accent)
        }
    }

    private var timeSection: some View {
        Section("Time") {
            LabeledContent("Minimum", value: durLo <= 0 ? "Any" : Format.duration(Int(durLo)))
            Slider(value: $durLo, in: 0...maxDuration).tint(Theme.accent)
            LabeledContent("Maximum", value: durHi >= maxDuration ? "No limit" : Format.duration(Int(durHi)))
            Slider(value: $durHi, in: 0...maxDuration).tint(Theme.accent)
        }
    }

    private var dateSection: some View {
        Section("When") {
            Picker("Range", selection: rangeSelection) {
                Text("All Time").tag(RangeKind.all)
                Text("Last 7 Days").tag(RangeKind.last7)
                Text("Last 30 Days").tag(RangeKind.last30)
                Text("This Month").tag(RangeKind.thisMonth)
                Text("This Year").tag(RangeKind.thisYear)
                Text("Custom").tag(RangeKind.custom)
            }
            .pickerStyle(.menu)

            if !stats.years.isEmpty {
                Picker("Year", selection: yearSelection) {
                    Text("Any").tag(Int?.none)
                    ForEach(stats.years, id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                }
            }

            if useCustom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            }
        }
    }

    private var surfaceSection: some View {
        Section("Surface") {
            Picker("Surface", selection: $draft.surface) {
                ForEach(RunFilter.Surface.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Only Races", isOn: raceToggle)
        }
    }

    private var locationSection: some View {
        Section("Where") {
            locationPicker("City", values: stats.cities, selection: $draft.city)
            locationPicker("State", values: stats.states, selection: $draft.state)
            locationPicker("Country", values: stats.countries, selection: $draft.country)
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset Filters", role: .destructive) {
                draft = RunFilter()
                scopeDraft = .all
                useCustom = false
                distLo = 0; distHi = maxDistance
                durLo = 0; durHi = maxDuration
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func locationPicker(_ title: String, values: [String], selection: Binding<String?>) -> some View {
        Group {
            if values.isEmpty {
                LabeledContent(title, value: "—")
            } else {
                Picker(title, selection: selection) {
                    Text("Any").tag(String?.none)
                    ForEach(values, id: \.self) { v in
                        Text(v).tag(String?.some(v))
                    }
                }
            }
        }
    }

    // MARK: Bindings

    private enum RangeKind { case all, last7, last30, thisMonth, thisYear, custom }

    private var rangeSelection: Binding<RangeKind> {
        Binding(
            get: {
                switch draft.dateRange {
                case .all: return .all
                case .last7Days: return .last7
                case .last30Days: return .last30
                case .thisMonth: return .thisMonth
                case .thisYear: return .thisYear
                case .year: return .all
                case .custom: return .custom
                }
            },
            set: { kind in
                useCustom = kind == .custom
                switch kind {
                case .all: draft.dateRange = .all
                case .last7: draft.dateRange = .last7Days
                case .last30: draft.dateRange = .last30Days
                case .thisMonth: draft.dateRange = .thisMonth
                case .thisYear: draft.dateRange = .thisYear
                case .custom: draft.dateRange = .custom(start: customStart, end: customEnd)
                }
            }
        )
    }

    private var yearSelection: Binding<Int?> {
        Binding(
            get: { if case .year(let y) = draft.dateRange { return y } else { return nil } },
            set: { if let y = $0 { draft.dateRange = .year(y); useCustom = false } else { draft.dateRange = .all } }
        )
    }

    private var raceToggle: Binding<Bool> {
        Binding(
            get: { draft.mode == .races },
            set: { draft.mode = $0 ? .races : .all }
        )
    }

    private func apply() {
        if useCustom { draft.dateRange = .custom(start: customStart, end: customEnd) }
        // Sliders → optional bounds; the extremes mean "no bound".
        let lo = min(distLo, distHi), hi = max(distLo, distHi)
        draft.minDistance = lo <= 0 ? nil : lo
        draft.maxDistance = hi >= maxDistance ? nil : hi
        let dlo = min(durLo, durHi), dhi = max(durLo, durHi)
        draft.minDuration = dlo <= 0 ? nil : Int(dlo)
        draft.maxDuration = dhi >= maxDuration ? nil : Int(dhi)
        appModel.activityScope = scopeDraft
        appModel.setFilter(draft)
        dismiss()
    }
}
