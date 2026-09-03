import SwiftUI
import PhotosUI

/// The book's photo curation sheet — **users curate, Etch designs**. Every photograph the
/// book's activities carry is shown included by default; a tap takes one out (or back in),
/// a context menu puts one on the cover, and the library picker adds photos that no activity
/// carries. Nothing re-renders until the reader says so: the Republish button at the foot
/// saves the choices and rebuilds the book's pages.
struct BookPhotoSheet: View {
    let plan: BookPlan
    @Binding var curation: BookCuration
    /// Called after saving — the studio bumps its render key and rebuilds every preview.
    let onRepublish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var picking: [PhotosPickerItem] = []
    /// The curation as it stood when the sheet opened — Republish only lights up on change.
    @State private var opening: BookCuration?
    /// Near-identical groups found among the candidates (perceptual hash), computed once.
    @State private var duplicateClusters: [[String]] = []

    /// Every photo the book's activities carry, in date order. De-duplicated by reference:
    /// on a real device the same library asset can be attached to two activities, and the
    /// grid's identity (and the include/exclude choice) is the photograph, not the pairing.
    private var candidates: [(run: Run, reference: String)] {
        var seen = Set<String>()
        return plan.runs.flatMap { run in run.photoReferences.map { (run, $0) } }
            .filter { seen.insert($0.1).inserted }
    }

    private var hasChanges: Bool { opening.map { $0 != curation } ?? false }
    private var includedCount: Int {
        candidates.filter { curation.includes($0.reference) }.count + curation.extraPhotoIDs.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Tap a photo to take it out of the book or put it back. Touch and hold to put one on the cover.")
                        .font(.etch(.footnote))
                        .foregroundStyle(.secondary)

                    duplicatesBanner

                    if candidates.isEmpty && curation.extraPhotoIDs.isEmpty {
                        ContentUnavailableView {
                            Label("No photos yet", systemImage: "photo.on.rectangle.angled")
                        } description: {
                            Text("Add photos to your activities — or bring any in from your library below — and the book will set them into its pages.")
                        }
                    }

                    photoGrid

                    if !curation.extraPhotoIDs.isEmpty {
                        Text("FROM YOUR LIBRARY")
                            .font(.etch(.caption, weight: .semibold)).tracking(2)
                            .foregroundStyle(.secondary)
                        extrasGrid
                    }

                    addButton
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("The Book's Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { republishBar }
            .onAppear { if opening == nil { opening = curation } }
            .task {
                guard duplicateClusters.isEmpty else { return }
                duplicateClusters = await PhotoDedupe.clusters(
                    references: candidates.map(\.reference))
            }
        }
    }

    // MARK: Near-duplicates

    /// The clusters that still hold more than one *included* photo — resolved ones drop out.
    private var pendingDuplicates: [[String]] {
        duplicateClusters
            .map { $0.filter(curation.includes) }
            .filter { $0.count > 1 }
    }

    @ViewBuilder private var duplicatesBanner: some View {
        let pending = pendingDuplicates
        if !pending.isEmpty {
            let extras = pending.reduce(0) { $0 + $1.count - 1 }
            HStack(spacing: 12) {
                Image(systemName: "square.on.square")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(extras) near-duplicate photo\(extras == 1 ? "" : "s")")
                        .font(.etch(.subheadline, weight: .semibold))
                    Text("Burst shots and repeats of the same moment.")
                        .font(.etch(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Keep one of each") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        for cluster in pending {
                            for reference in cluster.dropFirst() {
                                curation.excludedRefs.insert(reference)
                                if curation.coverPhotoRef == reference {
                                    curation.coverPhotoRef = nil
                                }
                            }
                        }
                    }
                }
                .font(.etch(.footnote, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 14))
        }
    }

    // MARK: The activity photos

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem](repeating: GridItem(.flexible(), spacing: 10), count: 3),
                  spacing: 14) {
            ForEach(candidates, id: \.reference) { candidate in
                tile(reference: candidate.reference,
                     caption: candidate.run.name,
                     included: curation.includes(candidate.reference))
                    .onTapGesture { toggle(candidate.reference) }
                    .contextMenu {
                        Button {
                            curation.coverPhotoRef = candidate.reference
                            curation.coverStyle = .photo
                            curation.excludedRefs.remove(candidate.reference)
                        } label: {
                            Label("Use on the cover", systemImage: "book.closed")
                        }
                        Button {
                            toggle(candidate.reference)
                        } label: {
                            curation.includes(candidate.reference)
                                ? Label("Take out of the book", systemImage: "minus.circle")
                                : Label("Put back in the book", systemImage: "plus.circle")
                        }
                    }
            }
        }
    }

    private var extrasGrid: some View {
        LazyVGrid(columns: [GridItem](repeating: GridItem(.flexible(), spacing: 10), count: 3),
                  spacing: 14) {
            ForEach(curation.extraPhotoIDs, id: \.self) { id in
                tile(reference: id, caption: "From your library", included: true)
                    .overlay(alignment: .topLeading) {
                        Button {
                            curation.extraPhotoIDs.removeAll { $0 == id }
                            if curation.coverPhotoRef == id { curation.coverPhotoRef = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .padding(6)
                    }
                    .contextMenu {
                        Button {
                            curation.coverPhotoRef = id
                            curation.coverStyle = .photo
                        } label: {
                            Label("Use on the cover", systemImage: "book.closed")
                        }
                    }
            }
        }
    }

    private func tile(reference: String, caption: String, included: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                Rectangle().fill(Theme.Palette.stone.opacity(0.5))
                if let image = thumbnails[reference] {
                    Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill())
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 10))
            .opacity(included ? 1 : 0.35)
            .overlay(alignment: .topTrailing) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, included ? Theme.accent : .black.opacity(0.35))
                    .padding(6)
            }
            .overlay(alignment: .bottomLeading) {
                if curation.coverPhotoRef == reference, curation.coverStyle == .photo {
                    Text("COVER")
                        .font(.etch(size: 9, weight: .bold)).tracking(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Theme.accent, in: .capsule)
                        .padding(6)
                }
            }
            Text(caption)
                .font(.etch(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(.rect)
        .task(id: reference) {
            guard thumbnails[reference] == nil else { return }
            thumbnails[reference] = await PhotoLibrary.image(
                for: reference, targetSize: CGSize(width: 400, height: 400))
        }
    }

    private func toggle(_ reference: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if curation.excludedRefs.contains(reference) {
                curation.excludedRefs.remove(reference)
            } else {
                curation.excludedRefs.insert(reference)
                if curation.coverPhotoRef == reference { curation.coverPhotoRef = nil }
            }
        }
    }

    // MARK: Adding from the library

    private var addButton: some View {
        PhotosPicker(selection: $picking, maxSelectionCount: 12, matching: .images,
                     photoLibrary: .shared()) {
            Label("Add photos from your library", systemImage: "photo.badge.plus")
                .font(.etch(.subheadline, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.etchSecondary)
        .onChange(of: picking) { _, items in
            guard !items.isEmpty else { return }
            // The picker runs against the shared library, so each item carries its asset
            // identifier — the same currency activity photos use. No copy, no re-import.
            let ids = items.compactMap(\.itemIdentifier)
            for id in ids where !curation.extraPhotoIDs.contains(id) {
                curation.extraPhotoIDs.append(id)
            }
            picking = []
        }
    }

    // MARK: Republish

    private var republishBar: some View {
        VStack(spacing: 8) {
            Button {
                curation.save(slug: plan.slug)
                onRepublish()
                dismiss()
            } label: {
                Label(hasChanges ? "Republish the book" : "No changes yet",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.etch(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent.opacity(hasChanges ? 1 : 0.35),
                                in: .rect(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!hasChanges)
            Text("\(includedCount) photo\(includedCount == 1 ? "" : "s") in the book")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
