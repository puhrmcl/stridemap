import SwiftUI

/// A square thumbnail that loads a Photos asset by identifier.
struct RunPhotoThumbnail: View {
    let identifier: String
    var size: CGFloat = 84
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.15))
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

/// Full-screen swipeable viewer for a run's photos, with a close and delete action.
struct RunPhotoViewer: View {
    let identifiers: [String]
    @State var selection: String
    var onDelete: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(identifiers, id: \.self) { id in
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
                    Button(role: .destructive) {
                        onDelete(selection)
                        dismiss()
                    } label: { Image(systemName: "trash") }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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
