import SwiftUI
import SwiftData

/// Fast batch correction, with a persistent route back to rejected matches after Undo disappears.
struct PhotoReviewView: View {
    let run: Run
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var showingRemoved = false
    @State private var lastRemoved: [(id: String, index: Int)] = []
    @State private var saveError = false

    private var identifiers: [String] { showingRemoved ? run.rejectedPhotoReferences : run.photoReferences }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(run.name).font(.etch(.headline))
                    Text("Choose photos that don’t belong to this activity. Removed matches stay removed when Etch scans again. Your originals stay in Apple Photos.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Picker("Photos", selection: $showingRemoved) {
                        Text("Attached (\(run.photoReferences.count))").tag(false)
                        Text("Removed (\(run.rejectedPhotoReferences.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: showingRemoved) { _, _ in selected = [] }
                    if identifiers.isEmpty {
                        ContentUnavailableView(showingRemoved ? "No removed matches" : "No attached photos",
                                               systemImage: "photo")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        ForEach(identifiers, id: \.self) { id in
                            Button {
                                if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                            } label: {
                                RunPhotoThumbnail(identifier: id, size: 96)
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(.white).shadow(radius: 2).padding(6)
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
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
