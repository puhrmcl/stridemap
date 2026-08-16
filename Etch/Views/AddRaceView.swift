import SwiftUI
import SwiftData

/// Add a race from the curated library: pick the race and year, enter your own finish time and
/// date, and choose whether it counts toward your totals. Creates a real activity with the
/// official course drawn on the map — for races you ran but never tracked on a watch or app.
struct AddRaceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var eventID: String = RaceCatalog.events.first?.id ?? ""
    @State private var year: Int = RaceCatalog.events.first?.years.first ?? Calendar.current.component(.year, from: Date())
    @State private var date: Date = Date()
    @State private var hours = 4
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var countsInTotals = true

    private var event: RaceEvent {
        RaceCatalog.events.first { $0.id == eventID } ?? RaceCatalog.events[0]
    }

    private var finishSeconds: Int { hours * 3600 + minutes * 60 + seconds }

    var body: some View {
        Form {
            raceSection
            resultSection
            totalsSection
            noteSection
        }
        .navigationTitle("Add a Race")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { add() }
                    .fontWeight(.semibold)
                    .disabled(finishSeconds <= 0)
            }
        }
        .onAppear(perform: syncDefaults)
        .onChange(of: eventID) { syncDefaults() }
        .onChange(of: year) { date = event.defaultDate(for: year) }
    }

    private var raceSection: some View {
        Section {
            Picker("Race", selection: $eventID) {
                ForEach(RaceCatalog.events) { event in
                    Text(event.name).tag(event.id)
                }
            }
            Picker("Year", selection: $year) {
                ForEach(event.years, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
        } header: {
            Text("Race")
        } footer: {
            Text("\(event.city)\(event.state.map { ", \($0)" } ?? "") · \(Format.distance(event.distanceMeters, decimals: 1))")
        }
    }

    private var resultSection: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            LabeledContent("Finish time") {
                HStack(spacing: 2) {
                    wheel(value: $hours, range: 0...12, unit: "h")
                    wheel(value: $minutes, range: 0...59, unit: "m")
                    wheel(value: $seconds, range: 0...59, unit: "s")
                }
            }
        } header: {
            Text("Your result")
        }
    }

    private func wheel(value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        Picker(unit, selection: value) {
            ForEach(Array(range), id: \.self) { n in
                Text("\(n)\(unit)").tag(n)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private var totalsSection: some View {
        Section {
            Toggle(isOn: $countsInTotals) {
                Label("Count toward my totals", systemImage: "sum")
            }
        } footer: {
            Text("On, this race adds to your distance, activity count, and records. Off, it still appears on the map, in your timeline, and in Studio — it just won't change your tracked numbers. Useful for a hand-entered official time you'd rather keep separate.")
        }
    }

    private var noteSection: some View {
        Section {
            Label {
                Text("Courses are representative and may vary by year. Your time and date are exactly as you enter them.")
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    /// Keep the year and default date consistent with the selected event.
    private func syncDefaults() {
        if !event.years.contains(year) {
            year = event.years.first ?? year
        }
        date = event.defaultDate(for: year)
    }

    private func add() {
        let run = RaceCatalog.makeRun(
            event: event,
            year: year,
            date: date,
            finishSeconds: finishSeconds,
            countsInTotals: countsInTotals
        )
        context.insert(run)
        try? context.save()
        dismiss()
    }
}
