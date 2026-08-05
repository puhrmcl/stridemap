import SwiftUI
import SwiftData

/// Filter the map by date range, surface, and location.
struct FilterView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query private var allRuns: [Run]

    @State private var draft = RunFilter()
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var customEnd = Date()
    @State private var useCustom = false

    private var stats: RunStatistics { RunStatistics(allRuns) }

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                surfaceSection
                locationSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { draft = RunFilter() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") { apply() }.fontWeight(.semibold)
                }
            }
            .onAppear { draft = appModel.filter }
        }
        .presentationDetents([.large])
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
        appModel.setFilter(draft)
        dismiss()
    }
}
