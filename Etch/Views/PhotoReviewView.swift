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
                    Text("Tap a photo to view it, or touch and hold it to remove it. Use Select to remove several at once. Your originals stay in Apple Photos, and removed matches stay removed when Etch scans again.")
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
                            .contextMenu { tileMenu(id) }
                        }
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
                    // Culling twenty near-identical frames one tap at a time is the case this
                    // screen actually gets used for, so selecting the lot is one control.
                    if isSelecting {
                        Button(selected.count == identifiers.count ? "None" : "All") {
                            selected = selected.count == identifiers.count ? [] : Set(identifiers)
                        }
                        .disabled(identifiers.isEmpty)
                    }
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
                        // Only while selecting: a long-press removal raises this bar for its
                        // Undo, and a disabled "Remove 0" sitting under it is noise.
                        if isSelecting {
                            HStack(spacing: 10) {
                                // "Not part of this activity" described the consequence accurately
                                // and read as a statement rather than a control. The primary action
                                // on a culling screen should say what it does, in one word.
                                Button(role: showingRemoved ? nil : .destructive) {
                                    if showingRemoved {
                                        restore(identifiers.filter { selected.contains($0) })
                                    } else {
                                        remove(identifiers.filter { selected.contains($0) })
                                    }
                                } label: {
                                    Text(showingRemoved
                                         ? "Restore \(selected.count)"
                                         : "Remove \(selected.count)")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(selected.isEmpty)

                                // These used to sit inline beneath the grid, which on an activity
                                // with twenty photographs meant scrolling past all of them to
                                // reach the controls for the ones just selected.
                                if !showingRemoved {
                                    Menu {
                                        Button("Hide from Memories", systemImage: "eye.slash") {
                                            setMemoryVisibility(hidden: true)
                                        }
                                        Button("Show in Memories", systemImage: "eye") {
                                            setMemoryVisibility(hidden: false)
                                        }
                                    } label: {
                                        Label("More", systemImage: "ellipsis.circle")
                                            .labelStyle(.iconOnly)
                                            .font(.title3)
                                    }
                                    .disabled(selected.isEmpty)
                                }
                            }
                        }
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

    /// The per-photo menu. This is the change that matters: removing one photograph used to cost
    /// a mode switch, a tap, a scroll to the foot of twenty thumbnails and a fourth tap. Here it
    /// is a long press and a tap, from the ordinary browsing state, and the Undo bar still
    /// appears — so a slip costs nothing.
    @ViewBuilder
    private func tileMenu(_ id: String) -> some View {
        if showingRemoved {
            Button("Restore to Activity", systemImage: "arrow.uturn.backward") { restore([id]) }
        } else {
            Button("View", systemImage: "eye") { preview = PhotoPreview(id: id) }
            if run.memoryHiddenPhotoReferences.contains(id) {
                Button("Show in Memories", systemImage: "eye") {
                    run.setPhotoHiddenFromMemories(id, hidden: false); save()
                }
            } else {
                Button("Hide from Memories", systemImage: "eye.slash") {
                    run.setPhotoHiddenFromMemories(id, hidden: true); save()
                }
            }
            Divider()
            Button("Remove from Activity", systemImage: "minus.circle", role: .destructive) {
                remove([id])
            }
        }
    }

    /// Detaches photographs, remembering where each sat so Undo can put it back in place. The
    /// original in Apple Photos is never touched.
    private func remove(_ ids: [String]) {
        let removing = Set(ids)
        lastRemoved = run.photoReferences.enumerated().compactMap { index, id in
            removing.contains(id) ? (id: id, index: index) : nil
        }
        for item in lastRemoved { run.rejectPhoto(item.id) }
        selected.subtract(removing)
        save()
    }

    private func restore(_ ids: [String]) {
        run.attachPhotos(ids, manually: true)
        selected.subtract(Set(ids))
        save()
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
