import SwiftUI
import MapKit

/// A single-activity photo map; keeps the global map renderer and its camera lifecycle untouched.
struct ActivityPhotoMap: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var locations: [PhotoLibrary.LocatedPhoto] = []
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var openedPhoto: GalleryPhoto?
    @State private var showReview = false
    @State private var position: MapCameraPosition = .automatic

    private var unlocated: [String] {
        let located = Set(locations.map(\.id))
        return run.photoReferences.filter { !located.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if coordinates.isEmpty && locations.isEmpty {
                    ContentUnavailableView("No photo locations available", systemImage: "map",
                        description: Text("Photos stay with this activity even without GPS. Etch won’t guess where they were taken."))
                } else {
                    Map(position: $position) {
                        if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates).stroke(Theme.accent, lineWidth: 3)
                        }
                        ForEach(locations) { photo in
                            Annotation("Photo", coordinate: photo.coordinate) {
                                Button { openedPhoto = GalleryPhoto(photoID: photo.id, run: run) } label: {
                                    RunPhotoThumbnail(identifier: photo.id, size: 44)
                                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white, lineWidth: 2) }
                                        .shadow(radius: 3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open photo at its recorded location")
                            }
                        }
                    }
                    .mapControls { MapCompass(); MapScaleView() }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(run.name).font(.etch(.headline)).lineLimit(2)
                    Text("\(locations.count) photos with recorded locations")
                        .font(.caption).foregroundStyle(.secondary)
                    if !PhotoLibrary.isAuthorized {
                        Text("Allow photo access in Settings to see available photo locations.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !unlocated.isEmpty {
                        Text("Without an available photo location").font(.etch(.caption, weight: .semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack {
                                ForEach(unlocated, id: \.self) { id in
                                    Button { openedPhoto = GalleryPhoto(photoID: id, run: run) } label: {
                                        RunPhotoThumbnail(identifier: id, size: 64)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Open activity photo without a map location")
                                }
                            }
                        }
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
            }
            .navigationTitle("Photos on this route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Manage") { showReview = true } }
            }
            .task(id: run.photoReferences) { reload() }
            .onChange(of: scenePhase) { _, value in if value == .active { reload() } }
            .fullScreenCover(item: $openedPhoto) { photo in
                RunPhotoViewer(photos: run.photoReferences.map { GalleryPhoto(photoID: $0, run: run) },
                               selection: photo.id)
            }
            .sheet(isPresented: $showReview) { PhotoReviewView(run: run) }
        }
    }

    private func reload() {
        locations = PhotoLibrary.locatedPhotos(for: run.photoReferences)
        coordinates = run.coordinates
        position = .automatic
    }
}
