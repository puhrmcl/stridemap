import SwiftUI
import SwiftData
import CoreLocation
import UniformTypeIdentifiers

/// Adds an event from the library — a marathon, a gran fondo, a summit — with everything the
/// participant actually recorded about the day: their finish time, bib, placing, photos, and
/// the route file from their own watch if they have it.
///
/// The library supplies identity, location, official distance and a date; it does not invent a
/// route. Only the handful of traced courses draw themselves, and a file the participant
/// attaches always wins — it's the line they actually covered.
struct AddRaceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var eventID: String = RaceCatalog.events.first?.id ?? ""
    @State private var date = Date()
    @State private var hours = 4
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var countsInTotals = true
    /// Set when the date came from an explicit choice that changing the event shouldn't undo.
    @State private var keepChosenDate = false

    @State private var bibNumber = ""
    @State private var finishPlace = ""

    /// The participant's own route file, parsed and held until the activity is created.
    @State private var attached: AttachedRoute?
    @State private var showFileImporter = false
    @State private var isReadingFile = false
    @State private var fileError: String?

    @State private var photoIDs: [String] = []
    @State private var showPhotoPicker = false

    private struct AttachedRoute {
        var coordinates: [CLLocationCoordinate2D]
        var elevations: [Double]
        var paces: [Double]
        var distance: Double
        var startDate: Date
    }

    private var event: RaceEvent {
        RaceCatalog.event(id: eventID) ?? RaceCatalog.events[0]
    }

    /// The date is the single source of truth for *when* — which is what lets someone add the
    /// marathon they ran in 1998 without the library having to offer a list of years.
    private var year: Int { Calendar.current.component(.year, from: date) }

    private var finishSeconds: Int { hours * 3600 + minutes * 60 + seconds }

    /// Pace falls straight out of the official distance and their time — shown, never asked for.
    private var paceLine: String? {
        guard finishSeconds > 0, event.distanceMeters > 0 else { return nil }
        let secondsPerKm = Double(finishSeconds) / (event.distanceMeters / 1000)
        return Format.pace(secondsPerKm: secondsPerKm)
    }

    var body: some View {
        Form {
            eventSection
            upcomingSection
            resultSection
            if event.discipline.hasFinisherFields { finisherSection }
            routeSection
            photosSection
            totalsSection
            noteSection
        }
        .navigationTitle(event.discipline == .hike ? "Add a Hike" : "Add a Race")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { add() }
                    .fontWeight(.semibold)
                    .disabled(finishSeconds <= 0)
            }
        }
        .onAppear(perform: syncDefaults)
        .onChange(of: eventID) { syncDefaults() }
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: Self.fileTypes,
                      allowsMultipleSelection: false,
                      onCompletion: handleFile)
        .sheet(isPresented: $showPhotoPicker) {
            AssetPhotoPicker(selectionLimit: 6) { ids in
                for id in ids where !photoIDs.contains(id) { photoIDs.append(id) }
            }
            .ignoresSafeArea()
        }
        .alert("Couldn't read that file", isPresented: .init(
            get: { fileError != nil }, set: { if !$0 { fileError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileError ?? "")
        }
    }

    // MARK: Event

    private var eventSection: some View {
        Section {
            Picker("Event", selection: $eventID) {
                ForEach(RaceCatalog.grouped(), id: \.discipline) { group in
                    Section(group.discipline.title) {
                        ForEach(group.events) { event in
                            Label(event.name, systemImage: event.discipline.icon).tag(event.id)
                        }
                    }
                }
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
            if !isOnTypicalDate {
                Button("Use \(typicalDateLabel)") { date = event.lastOccurrence() }
                    .font(.subheadline)
            }
        } header: {
            Text("Event")
        } footer: {
            Text(event.summary)
        }
    }

    private var isOnTypicalDate: Bool {
        Calendar.current.isDate(date, inSameDayAs: event.defaultDate(for: year))
    }

    private var typicalDateLabel: String {
        event.lastOccurrence().formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// What the library says is coming up next. The calendar is the only thing it knows — there
    /// are no entry lists here — but "Boston is in six weeks" is the reason to open this screen.
    private var upcomingSection: some View {
        Section {
            ForEach(RaceCatalog.upcoming(limit: 5)) { item in
                Button {
                    // Changing the event normally re-dates the form to that event's last running.
                    // Here the date is the whole point of the tap, so it survives the sync.
                    keepChosenDate = true
                    eventID = item.event.id
                    date = item.date
                } label: {
                    HStack {
                        Label(item.event.name, systemImage: item.event.discipline.icon)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(item.date.formatted(.dateTime.month(.abbreviated).day()))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Coming up")
        } footer: {
            Text("The library's usual calendar slots, soonest first. Picking one sets the event and its date — adjust the date if the year you ran it was different.")
        }
    }

    // MARK: Result

    private var resultSection: some View {
        Section {
            LabeledContent(event.discipline == .hike ? "Time" : "Finish time") {
                HStack(spacing: 2) {
                    wheel(value: $hours, range: 0...23, unit: "h")
                    wheel(value: $minutes, range: 0...59, unit: "m")
                    wheel(value: $seconds, range: 0...59, unit: "s")
                }
            }
            if let paceLine {
                LabeledContent("Pace", value: paceLine)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Your result")
        } footer: {
            Text("Pace is calculated from the official distance and your time.")
        }
    }

    private var finisherSection: some View {
        Section {
            LabeledContent("Bib number") {
                TextField("optional", text: $bibNumber)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            LabeledContent("Finishing place") {
                TextField("optional", text: $finishPlace)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
            }
        } header: {
            Text("Finisher details")
        } footer: {
            Text("A plain number becomes an ordinal on your poster — 127 reads as 127th. Anything else prints exactly as you type it.")
        }
    }

    // MARK: Route

    private var routeSection: some View {
        Section {
            if let attached {
                LabeledContent("Route") {
                    Text(String(format: "%.1f mi · %d points", attached.distance / 1609.344,
                                attached.coordinates.count))
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) { self.attached = nil } label: {
                    Label("Remove route file", systemImage: "trash")
                }
            } else {
                Button { showFileImporter = true } label: {
                    Label(isReadingFile ? "Reading file…" : "Attach route file", systemImage: "square.and.arrow.down")
                }
                .disabled(isReadingFile)
            }
        } header: {
            Text("Route")
        } footer: {
            Text(routeFooter)
        }
    }

    private var routeFooter: String {
        if attached != nil {
            return "Your file draws the route and measures the distance — it's the line you actually covered."
        }
        switch event.courseSource {
        case .file:
            return "The library carries this event's official course. Attach your own GPX, TCX or FIT file to draw the route you actually covered instead."
        case .traced:
            return "The library carries an approximate course for this event, traced from public geography. Attach your own GPX, TCX or FIT file for the real thing."
        case .none:
            return "The library places this event but doesn't invent its route. Attach your GPX, TCX or FIT file to draw it — or add it later from the activity."
        }
    }

    private static let fileTypes: [UTType] = {
        var types = [
            UTType(filenameExtension: "gpx", conformingTo: .xml),
            UTType(filenameExtension: "tcx", conformingTo: .xml),
            UTType(filenameExtension: "fit", conformingTo: .data)
        ].compactMap { $0 }
        types.append(contentsOf: [.data, .xml])
        return types
    }()

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isReadingFile = true
        Task {
            defer { isReadingFile = false }
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    return try ActivityFileParsing.parse(data: data, fileName: url.lastPathComponent)
                }.value
                guard let best = parsed.filter({ !$0.coordinates.isEmpty })
                    .max(by: { $0.coordinates.count < $1.coordinates.count }) else {
                    fileError = "That file has no GPS points in it."
                    return
                }
                attached = AttachedRoute(
                    coordinates: best.coordinates, elevations: best.elevationSeries,
                    paces: best.paceSeries, distance: best.distance, startDate: best.startDate
                )
                // The file knows the day better than a calendar default does.
                date = best.startDate
            } catch {
                fileError = error.localizedDescription
            }
        }
    }

    // MARK: Photos

    private var photosSection: some View {
        Section {
            Button {
                Task { await PhotoLibrary.requestAuthorization(); showPhotoPicker = true }
            } label: {
                Label(photoIDs.isEmpty ? "Add photos" : "Photos · \(photoIDs.count)",
                      systemImage: "photo.badge.plus")
            }
            if !photoIDs.isEmpty {
                Button(role: .destructive) { photoIDs.removeAll() } label: {
                    Label("Remove photos", systemImage: "trash")
                }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("Photos from the day. They appear on the activity and can fill the frames of a Gallery poster.")
        }
    }

    // MARK: Totals + note

    private var totalsSection: some View {
        Section {
            Toggle(isOn: $countsInTotals) {
                Label("Count toward my totals", systemImage: "sum")
            }
        } footer: {
            Text("On, this adds to your distance, activity count, and records. Off, it still appears on the map, in your timeline, and in Studio — it just won't change your tracked numbers. Useful for a hand-entered official time you'd rather keep separate.")
        }
    }

    private var noteSection: some View {
        Section {
            Label {
                Text(event.courseSource == .traced
                     ? "Library courses are representative and may vary by year. Your time and details are exactly as you enter them."
                     : "The library supplies this event's location and official distance. Your time and details are exactly as you enter them.")
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func wheel(value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        Picker(unit, selection: value) {
            ForEach(Array(range), id: \.self) { n in Text("\(n)\(unit)").tag(n) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private func syncDefaults() {
        // Their own file knows the day; otherwise default to the last time this came around.
        if attached == nil && !keepChosenDate { date = event.lastOccurrence() }
        keepChosenDate = false
        if !event.discipline.hasFinisherFields { bibNumber = ""; finishPlace = "" }
    }

    private func add() {
        let run = RaceCatalog.makeRun(
            event: event,
            year: year,
            date: date,
            finishSeconds: finishSeconds,
            countsInTotals: countsInTotals,
            bibNumber: bibNumber.trimmingCharacters(in: .whitespaces),
            finishPlace: finishPlace.trimmingCharacters(in: .whitespaces),
            photoReferences: photoIDs,
            attachedRoute: attached?.coordinates,
            attachedElevations: attached?.elevations ?? [],
            attachedPaces: attached?.paces ?? [],
            attachedDistance: attached?.distance
        )
        context.insert(run)
        try? context.save()
        dismiss()
    }
}
