import SwiftUI

/// Chooses which of the run's photos fills a Gallery frame — real thumbnails, not numbers.
/// Every photo on the activity is offered (no cap), current selection ringed, plus an Add Photo
/// tile that pulls a new one from the library straight into the frame being edited. The photo
/// sibling of `MetricPickerSheet`: tap a slot, see the gallery, pick.
struct FramePhotoPickerSheet: View {
    let run: Run
    /// Absolute index (into `run.photoReferences`) the frame currently shows.
    let current: Int
    let onPick: (Int) -> Void
    let onAddPhoto: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var thumbnails: [Int: UIImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(run.photoReferences.indices, id: \.self) { index in
                        Button {
                            onPick(index)
                            dismiss()
                        } label: {
                            thumbnailTile(index)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        dismiss()
                        onAddPhoto()
                    } label: {
                        addTile
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .navigationTitle("Choose Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .task { await loadThumbnails() }
        }
        .presentationDetents([.medium, .large])
    }

    private func thumbnailTile(_ index: Int) -> some View {
        Color.clear
            .overlay {
                if let image = thumbnails[index] {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        ProgressView()
                    }
                }
            }
            .frame(height: 104)
            .clipShape(.rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(index == current ? Theme.accent : Color.primary.opacity(0.08),
                                  lineWidth: index == current ? 2.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if index == current {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, Theme.accent)
                        .padding(5)
                }
            }
    }

    private var addTile: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Add Photo")
                .font(.system(.caption, design: .default).weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func loadThumbnails() async {
        for (index, id) in run.photoReferences.enumerated() where thumbnails[index] == nil {
            if let image = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 320, height: 320)) {
                thumbnails[index] = image
            }
        }
    }
}
