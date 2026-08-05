import SwiftUI
import SwiftData
import MapKit

/// A pin for every place you've ever run. Tap a place to see the runs from that trip.
struct TravelMapView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query private var runs: [Run]

    @State private var selectedPlace: RunStatistics.TravelPlace?

    private var places: [RunStatistics.TravelPlace] { RunStatistics(runs).travelPlaces }

    var body: some View {
        NavigationStack {
            Map {
                ForEach(places) { place in
                    Annotation(place.label, coordinate: place.coordinate) {
                        Button {
                            selectedPlace = place
                        } label: {
                            PlacePin(count: place.runs.count)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .navigationTitle("Travel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedPlace) { place in
                PlaceRunsSheet(place: place) { run in
                    appModel.select(run)
                    appModel.presentedSurface = nil
                    dismiss()
                }
                .presentationDetents([.medium, .large])
            }
            .overlay(alignment: .bottom) {
                if places.isEmpty {
                    Text("Places appear here once your runs have location data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .glassBackground(cornerRadius: 16)
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

private struct PlacePin: View {
    let count: Int
    var body: some View {
        VStack(spacing: 2) {
            Text(count.formatted())
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.accent, in: .capsule)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .offset(y: -4)
        }
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

private struct PlaceRunsSheet: View {
    let place: RunStatistics.TravelPlace
    let onSelect: (Run) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(place.runs) { run in
                        Button { onSelect(run) } label: { RunRow(run: run, showPlace: false) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(place.runs.count) runs · \(Format.distance(place.totalDistance, decimals: 0))")
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .navigationTitle(place.label)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
