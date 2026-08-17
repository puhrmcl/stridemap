import SwiftUI
import MapKit

/// Drop or move a run's location by hand — for indoor/treadmill runs (or GPS-less imports) that no
/// source gave coordinates for. Pan the map so the pin sits on the spot, then Set. Seeds from the
/// run's current location or a suggested nearby one, so it starts close instead of mid-ocean.
struct LocationPickerView: View {
    let title: String
    let onSet: (CLLocationCoordinate2D) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition
    @State private var center: CLLocationCoordinate2D

    init(title: String, start: CLLocationCoordinate2D?, onSet: @escaping (CLLocationCoordinate2D) -> Void) {
        self.title = title
        self.onSet = onSet
        // Fall back to the geographic centre of the US when there's nothing to suggest.
        let seed = start ?? CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)
        _center = State(initialValue: seed)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: seed,
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position)
                .mapStyle(.standard(elevation: .flat))
                .onMapCameraChange(frequency: .continuous) { center = $0.region.center }
                .overlay { centerPin }
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) { bottomBar }
                .navigationTitle("Set Location")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                }
        }
    }

    /// A pin whose tip rests on the exact map centre (offset up by half its height), so panning the
    /// map beneath it aims the point precisely.
    private var centerPin: some View {
        Image(systemName: "mappin")
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(Theme.accent)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            .offset(y: -18)
            .allowsHitTesting(false)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("Drag the map so the pin sits where \(title) happened.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onSet(center)
                dismiss()
            } label: {
                Text("Set Location")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.accent, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.regularMaterial)
    }
}
