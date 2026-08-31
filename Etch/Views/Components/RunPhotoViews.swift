import SwiftUI

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

/// Full-screen swipeable viewer for a run's photos, with close, cover, share and delete actions.
struct RunPhotoViewer: View {
    let identifiers: [String]
    @State var selection: String
    /// Whether a given photo is currently its activity's cover — the one that represents it on
    /// tiles, in the timeline, on the Photo Wall and on a book's race page.
    ///
    /// A closure rather than a single identifier, because the gallery swipes across every
    /// activity's photos at once: which photo is "the cover" changes with the page, and only the
    /// caller knows whose cover it would be.
    var isCoverPhoto: ((String) -> Bool)?
    var onDelete: (String) -> Void
    /// Makes the visible photo the cover. Optional so a viewer opened somewhere without a run to
    /// write back to simply does not offer it.
    var onSetCover: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// Full-resolution image for the current photo, loaded for sharing.
    @State private var shareImage: UIImage?

    /// The photo chosen as a cover on this screen, so the star fills on the tap rather than on the
    /// next model update. Only ever the one that was tapped; every other page asks the model.
    @State private var pickedCover: String?

    /// The page order, snapshotted on first appearance.
    ///
    /// Setting a cover moves that photo to the front of `run.photoReferences`, which would
    /// re-order the pager under the reader's thumb — the photo they are looking at would slide to
    /// position one mid-gesture. The order they opened with is the order they keep.
    @State private var order: [String] = []
    private var pages: [String] { order.isEmpty ? identifiers : order }

    private var isCover: Bool {
        pickedCover == selection || (isCoverPhoto?(selection) ?? false)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(pages, id: \.self) { id in
                    FullPhoto(identifier: id).tag(id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: identifiers.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let shareImage {
                        ShareLink(
                            item: Image(uiImage: shareImage),
                            preview: SharePreview("Run photo", image: Image(uiImage: shareImage))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        onDelete(selection)
                        dismiss()
                    } label: { Image(systemName: "trash") }
                }
                // The cover action sits at the bottom rather than in the toolbar with the others.
                // It is the one control here that changes what this activity looks like everywhere
                // else in the app, and it needs to say which photo is currently carrying that job —
                // neither of which a 22pt toolbar glyph can do.
                if onSetCover != nil {
                    ToolbarItem(placement: .bottomBar) { coverButton }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { if order.isEmpty { order = identifiers } }
        }
        .preferredColorScheme(.dark)
        // Reload the shareable image whenever the visible photo changes.
        .task(id: selection) {
            shareImage = nil
            shareImage = await PhotoLibrary.fullImage(for: selection)
        }
    }

    /// Star this photo as the one that represents the activity.
    ///
    /// It states the outcome rather than the toggle: "Cover photo" with a filled star is a label,
    /// and "Make cover photo" is an invitation. Tapping the one that is already the cover does
    /// nothing rather than un-setting it — an activity with photos always has a cover, so there is
    /// no off state to offer.
    private var coverButton: some View {
        Button {
            guard !isCover else { return }
            pickedCover = selection
            onSetCover?(selection)
        } label: {
            Label(isCover ? "Cover photo" : "Make cover photo",
                  systemImage: isCover ? "star.fill" : "star")
                .font(.etch(.subheadline, weight: .semibold))
                .foregroundStyle(isCover ? Theme.accent : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: .capsule)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isCover)
        .accessibilityLabel(isCover ? "This is the cover photo" : "Make this the cover photo")
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
