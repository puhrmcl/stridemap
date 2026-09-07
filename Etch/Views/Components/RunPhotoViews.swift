import SwiftUI
import SwiftData

/// A square thumbnail that loads a Photos asset by identifier.
struct RunPhotoThumbnail: View {
    let identifier: String
    var size: CGFloat = 84
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.Brand.inkWell)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: 12))
        .task(id: identifier) {
            image = await PhotoLibrary.image(
                for: identifier,
                targetSize: CGSize(width: size * 3, height: size * 3)
            )
        }
    }
}

/// A pager whose identity is the association, not just the asset: overlapping activities can
/// legitimately share a photo. All actions address the activity shown on the current page.
struct RunPhotoViewer: View {
    let photos: [GalleryPhoto]
    @State var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var order: [GalleryPhoto] = []
    @State private var initialized = false
    @State private var shareImage: UIImage?
    @State private var removed: Removed?
    @State private var saveError = false

    private struct Removed {
        let photo: GalleryPhoto
        let photoIndex: Int
        let pageIndex: Int
    }

    private var pages: [GalleryPhoto] { initialized ? order : photos }
    private var current: GalleryPhoto? { pages.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    ContentUnavailableView("Photo removed from activity", systemImage: "photo",
                        description: Text("The original is still in Apple Photos. You can undo below."))
                } else {
                    TabView(selection: $selection) {
                        ForEach(pages) { photo in
                            FullPhoto(identifier: photo.photoID).tag(photo.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .background(Color.black.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareImage {
                        ShareLink(item: Image(uiImage: shareImage),
                            preview: SharePreview("Activity photo", image: Image(uiImage: shareImage))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .onAppear {
                guard !initialized else { return }
                order = photos
                initialized = true
            }
            .alert("Couldn’t save photo changes", isPresented: $saveError) {
                Button("Retry") { save() }
                Button("OK", role: .cancel) {}
            } message: { Text("Your changes are still on this screen. Try saving again before leaving.") }
        }
        .preferredColorScheme(.dark)
        .task(id: selection) {
            shareImage = nil
            guard let photo = current else { return }
            let loaded = await PhotoLibrary.fullImage(for: photo.photoID)
            guard !Task.isCancelled else { return }
            shareImage = loaded
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let removed {
                HStack {
                    Text("Removed from activity").font(.footnote)
                    Spacer()
                    Button("Undo") {
                        removed.photo.run.restorePhoto(removed.photo.photoID, at: removed.photoIndex)
                        order.insert(removed.photo, at: min(removed.pageIndex, order.count))
                        selection = removed.photo.id
                        self.removed = nil
                        save()
                    }
                }
            }
            if pages.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 5) {
                            ForEach(pages) { photo in
                                Button { selection = photo.id } label: {
                                    FilmstripFrame(identifier: photo.photoID, isCurrent: photo.id == selection)
                                }
                                .buttonStyle(.plain)
                                .id(photo.id)
                                .accessibilityLabel("Photo from \(photo.run.name)")
                            }
                        }
                    }
                    .frame(height: FilmstripFrame.tall)
                    .onChange(of: selection, initial: true) { _, id in proxy.scrollTo(id, anchor: .center) }
                }
            }
            if let photo = current {
                Text(photo.run.name).font(.etch(.subheadline, weight: .semibold)).lineLimit(2)
                HStack {
                    Button {
                        photo.run.makePhotoCover(photo.photoID)
                        save()
                    } label: {
                        Label(photo.run.photoReferences.first == photo.photoID ? "Cover photo" : "Make cover",
                              systemImage: "star")
                    }
                    Spacer()
                    Menu {
                        Button {
                            let hidden = photo.run.memoryHiddenPhotoReferences.contains(photo.photoID)
                            photo.run.setPhotoHiddenFromMemories(photo.photoID, hidden: !hidden)
                            save()
                        } label: {
                            Label(photo.run.memoryHiddenPhotoReferences.contains(photo.photoID)
                                  ? "Show in Memories" : "Hide from Memories", systemImage: "eye.slash")
                        }
                    } label: { Label("More", systemImage: "ellipsis") }
                }
                .font(.etch(.footnote, weight: .semibold))
                Button {
                    guard let index = photo.run.rejectPhoto(photo.photoID),
                          let page = order.firstIndex(where: { $0.id == photo.id }) else { return }
                    removed = Removed(photo: photo, photoIndex: index, pageIndex: page)
                    order.remove(at: page)
                    selection = order.isEmpty ? "" : order[min(page, order.count - 1)].id
                    shareImage = nil
                    save()
                } label: {
                    Label("Not part of this activity", systemImage: "minus.circle")
                }
                .font(.etch(.footnote, weight: .semibold))
                Text("This only removes the match in Etch, not the original photo.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func save() {
        do { try context.save() } catch { saveError = true }
    }
}


/// One frame in the filmstrip. The current one is taller and outlined; the rest are dimmed, so a
/// glance down finds your place without reading anything.
private struct FilmstripFrame: View {
    let identifier: String
    let isCurrent: Bool
    @State private var image: UIImage?

    /// The strip's height, and the current frame's. Named so the ScrollView and the frame cannot
    /// disagree about it — a strip 2pt shorter than its tallest child clips the border.
    static let tall: CGFloat = 54
    private static let short: CGFloat = 40

    private var side: CGFloat { isCurrent ? Self.tall : Self.short }

    var body: some View {
        Color.clear
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.12))
                }
            }
            .clipShape(.rect(cornerRadius: isCurrent ? 6 : 4))
            .overlay {
                RoundedRectangle(cornerRadius: isCurrent ? 6 : 4)
                    .strokeBorder(.white.opacity(isCurrent ? 0.9 : 0), lineWidth: 1.5)
            }
            .opacity(isCurrent ? 1 : 0.55)
            .frame(width: side, height: Self.tall)
            .contentShape(.rect)
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
            .task(id: identifier) {
                image = await PhotoLibrary.image(
                    for: identifier,
                    targetSize: CGSize(width: 160, height: 160)
                )
            }
    }
}

private struct FullPhoto: View {
    let identifier: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: identifier) {
            image = await PhotoLibrary.image(for: identifier, targetSize: CGSize(width: 1600, height: 1600))
        }
    }
}

/// Chooses which of an activity's photos travel with its share.
///
/// Only offered when the activity has photos — a photo-less run shares straight away. Everything
/// else in the share (the details text, the route map, the Apple Maps location) always goes; this
/// sheet decides only the photographs, because those are the personal part: a race with thirty
/// photos does not want all thirty in one message, and which three it does want is not a call
/// the app can make.
struct SharePhotoPicker: View {
    let identifiers: [String]
    /// Called with the chosen identifiers, in the activity's own photo order.
    let onShare: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Everything starts selected: the common case is "share it all", one tap away, and pruning
    /// two photos is less work than picking eight.
    @State private var selected: Set<String>

    init(identifiers: [String], onShare: @escaping ([String]) -> Void) {
        self.identifiers = identifiers
        self.onShare = onShare
        _selected = State(initialValue: Set(identifiers))
    }

    private var chosen: [String] { identifiers.filter { selected.contains($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(identifiers, id: \.self) { identifier in
                        Button {
                            if selected.contains(identifier) {
                                selected.remove(identifier)
                            } else {
                                selected.insert(identifier)
                            }
                        } label: {
                            RunPhotoThumbnail(identifier: identifier, size: 96)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: selected.contains(identifier)
                                          ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Theme.accent)
                                        .shadow(radius: 2)
                                        .padding(6)
                                }
                                .opacity(selected.contains(identifier) ? 1 : 0.5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                Text("The share always includes your activity details, the route map, and the location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle("Include Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(chosen.isEmpty ? "Share" : "Share (\(chosen.count))") {
                        let picked = chosen
                        dismiss()
                        onShare(picked)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
