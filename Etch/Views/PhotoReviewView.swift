import SwiftUI
import SwiftData
import PhotosUI

/// Fast batch correction, with a persistent route back to rejected matches after Undo disappears.
struct PhotoReviewView: View {
    let run: Run
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var showingRemoved = false
    @State private var lastRemoved: [(id: String, index: Int)] = []
    @State private var saveError = false
    @State private var isSelecting = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var preview: PhotoPreview?
    private struct PhotoPreview: Identifiable { let id: String }

    private var identifiers: [String] { showingRemoved ? run.rejectedPhotoReferences : run.photoReferences }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(run.name).font(.etch(.headline))
                    Text("Tap a photo to view it. Use Select to remove unwanted matches. Your originals stay in Apple Photos, and removed matches stay removed when Etch scans again.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Photos", selection: $showingRemoved) {
                        Text("Attached (\(run.photoReferences.count))").tag(false)
                        Text("Removed (\(run.rejectedPhotoReferences.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: showingRemoved) { _, removed in selected = []; isSelecting = removed }
                    if identifiers.isEmpty {
                        ContentUnavailableView(showingRemoved ? "No removed matches" : "No attached photos",
                                               systemImage: "photo")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(identifiers, id: \.self) { id in
                            Button {
                                if isSelecting {
                                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                                } else {
                                    preview = PhotoPreview(id: id)
                                }
                            } label: {
                                RunPhotoThumbnail(identifier: id, size: 96)
                                    .overlay(alignment: .topTrailing) {
                                        if isSelecting {
                                            Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(.white).shadow(radius: 2).padding(6)
                                        }
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        if run.memoryHiddenPhotoReferences.contains(id) {
                                            Image(systemName: "eye.slash.fill").foregroundStyle(.white)
                                                .padding(6).background(.black.opacity(0.5), in: .capsule)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Photo \((identifiers.firstIndex(of: id) ?? 0) + 1)")
                            .accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
                        }
                    }
                    if !showingRemoved, !selected.isEmpty {
                        Button("Hide selected from Memories") { setMemoryVisibility(hidden: true) }
                        Button("Show selected in Memories") { setMemoryVisibility(hidden: false) }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Manage Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !showingRemoved {
                        Button(isSelecting ? "Cancel" : "Select") {
                            isSelecting.toggle()
                            selected = []
                        }
                        .disabled(identifiers.isEmpty)
                    }
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                run.attachPhotos(items.compactMap(\.itemIdentifier), manually: true)
                pickerItems = []
                showingRemoved = false
                selected = []
                save()
            }
            .fullScreenCover(item: $preview) { photo in
                RunPhotoViewer(photos: run.photoReferences.map { GalleryPhoto(photoID: $0, run: run) },
                               selection: GalleryPhoto(photoID: photo.id, run: run).id)
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting || !lastRemoved.isEmpty {
                    VStack(spacing: 10) {
                        if !lastRemoved.isEmpty {
                            Button("Undo last removal") {
                                for item in lastRemoved.sorted(by: { $0.index < $1.index }) {
                                    run.restorePhoto(item.id, at: item.index)
                                }
                                lastRemoved = []
                                save()
                            }
                        }
                        Button(showingRemoved ? "Restore selected (\(selected.count))" : "Not part of this activity (\(selected.count))") {
                            if showingRemoved {
                                run.attachPhotos(identifiers.filter { selected.contains($0) }, manually: true)
                            } else {
                                lastRemoved = run.photoReferences.enumerated().compactMap { index, id in
                                    selected.contains(id) ? (id: id, index: index) : nil
                                }
                                for item in lastRemoved { run.rejectPhoto(item.id) }
                            }
                            selected = []
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty)
                    }
                    .padding().frame(maxWidth: .infinity).background(.bar)
                }
            }
            .alert("Couldn’t save photo changes", isPresented: $saveError) {
                Button("Retry") { save() }
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func setMemoryVisibility(hidden: Bool) {
        for id in selected { run.setPhotoHiddenFromMemories(id, hidden: hidden) }
        selected = []
        save()
    }

    private func save() {
        do { try context.save() } catch { saveError = true }
    }
}
