import SwiftUI
import SwiftData
import CoreLocation

/// Wraps a parsed activity so it can drive a `.sheet(item:)`.
struct ImportedRunDraft: Identifiable {
    let id = UUID()
    let activity: ImportedActivity
}

/// Import a single run file into Etch with your own choices: set the title, decide whether it's a
/// race, and whether it counts toward your totals. Used from Studio to bring in any run — including
/// one from an app Etch doesn't sync — and turn it into art.
struct ImportRunView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let activity: ImportedActivity

    @State private var title: String
    @State private var makeRace: Bool
    @State private var countsInTotals = true
    /// nil = Auto (use Etch's detection); a value overrides it.
    @State private var activityOverride: ActivityType?

    init(activity: ImportedActivity) {
        self.activity = activity
        _title = State(initialValue: activity.name?.isEmpty == false ? activity.name! : "Imported Run")
        _makeRace = State(initialValue: activity.isRace ?? false)
    }

    /// The type that will be used — the override, or Etch's auto-detection.
    private var resolvedType: ActivityType { activityOverride ?? activity.activityType }
    private var typeChoices: [ActivityType] { [.run, .hike, .ride, .walk] }

    private var hasRoute: Bool { !activity.coordinates.isEmpty }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
            } header: {
                Text("Title")
            }

            Section {
                LabeledContent("Date", value: activity.startDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Distance", value: Format.distance(activity.distance, decimals: 1))
                LabeledContent("Time", value: Format.duration(activity.movingTime))
                if !hasRoute {
                    Label("No GPS route in this file — it won't have a map to etch.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("From the file")
            }

            Section {
                Picker(selection: $activityOverride) {
                    Text("Auto — \(activity.activityType.detailLabel)")
                        .tag(ActivityType?.none)
                    ForEach(typeChoices, id: \.self) { type in
                        Label(type.detailLabel, systemImage: type.detailIcon)
                            .tag(ActivityType?.some(type))
                    }
                } label: {
                    Label("Activity", systemImage: resolvedType.detailIcon)
                }
            } header: {
                Text("Activity type")
            } footer: {
                Text("Auto lets Etch detect the type from the file. Choose a type to override it.")
            }

            Section {
                Toggle(isOn: $makeRace) {
                    Label("Mark as a race", systemImage: "trophy")
                }
                Toggle(isOn: $countsInTotals) {
                    Label("Count toward my totals", systemImage: "sum")
                }
            } footer: {
                Text("Off keeps this run out of your distance, activity count, and records while it still appears on the map, in your timeline, and in Studio.")
            }
        }
        .navigationTitle("Import a Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { add() }
                    .fontWeight(.semibold)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
    }

    private func add() {
        let coords = activity.coordinates
        let polyline = activity.encodedPolyline ?? PolylineDecoder.encode(coords)
        let box = RouteGeometry.boundingBox(of: coords, fallbackStart: coords.first)
        let run = Run(
            provider: activity.provider,
            originApp: activity.originApp,
            name: trimmedTitle,
            startDate: activity.startDate,
            distance: activity.distance,
            movingTime: activity.movingTime,
            elapsedTime: activity.elapsedTime,
            elevationGain: activity.elevationGain ?? 0,
            summaryPolyline: polyline,
            averageHeartRate: activity.averageHeartRate,
            maxHeartRate: activity.maxHeartRate,
            activeEnergy: activity.activeEnergy,
            averageCadence: activity.averageCadence,
            city: activity.city,
            state: activity.state,
            country: activity.country,
            sportType: activity.sportType ?? "Run",
            isRace: makeRace,
            isCommute: activity.isCommute ?? false,
            isTrail: activity.isTrail ?? false,
            isIndoor: activity.isIndoor ?? false,
            excludedFromTotals: !countsInTotals,
            startLatitude: coords.first?.latitude,
            startLongitude: coords.first?.longitude,
            minLatitude: box.minLat,
            maxLatitude: box.maxLat,
            minLongitude: box.minLon,
            maxLongitude: box.maxLon
        )
        run.importMethod = activity.importMethod ?? .manual
        run.activityType = resolvedType
        if !activity.elevationSeries.isEmpty { run.elevationSeries = activity.elevationSeries }
        run.weatherTemperatureC = activity.weatherTemperatureC
        run.weatherConditionRaw = activity.weatherCondition
        run.nameIsCustom = true
        run.raceIsCustom = true
        if !activity.externalID.isEmpty { run.sourceExternalID = activity.externalID }
        if !coords.isEmpty {
            run.routeStatus = .available
            run.routeSource = .imported
        }
        context.insert(run)
        try? context.save()
        dismiss()
    }
}
