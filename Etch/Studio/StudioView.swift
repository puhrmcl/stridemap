import SwiftUI

/// Etch Studio: a gallery-like way to turn a run into a finished piece. The user swipes
/// through curated *editions* — each a complete composition, not a set of controls — and
/// exports the one they want. Deliberately editorial: the artwork is the hero, chrome is quiet.
struct StudioView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss

    @State private var selection: StudioEdition.ID = .gallery
    @State private var rendered: [StudioEdition.ID: UIImage] = [:]
    @State private var rendering: Set<StudioEdition.ID> = []

    private var current: StudioEdition { StudioEdition.edition(selection) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(StudioEdition.all) { edition in
                        page(for: edition).tag(edition.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                caption
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Etch Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let image = rendered[selection] {
                        let title = "\(run.name) · \(current.name)"
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(title, image: Image(uiImage: image))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task(id: selection) { await renderIfNeeded(selection) }
        }
    }

    // MARK: Pages

    private func page(for edition: StudioEdition) -> some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let image = rendered[edition.id] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(edition.ground)
                        .aspectRatio(StudioComposition.width / StudioComposition.size.height, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                ProgressView().tint(edition.accent)
                                Text("Composing…")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(edition.subtle)
                            }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
    }

    // MARK: Caption

    private var caption: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(StudioEdition.all) { edition in
                    Circle()
                        .fill(edition.id == selection ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Text(current.name)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(current.descriptor)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    // MARK: Rendering

    private func renderIfNeeded(_ id: StudioEdition.ID) async {
        guard rendered[id] == nil, !rendering.contains(id) else { return }
        rendering.insert(id)
        defer { rendering.remove(id) }
        if let image = await render(StudioEdition.edition(id)) {
            rendered[id] = image
        }
    }

    @MainActor
    private func render(_ edition: StudioEdition) async -> UIImage? {
        var mapImage: UIImage?
        if edition.usesMap {
            mapImage = await PosterMap.studioPanel(
                for: run,
                size: CGSize(width: StudioComposition.width, height: StudioComposition.artHeight),
                edition: edition
            )
        }
        let renderer = ImageRenderer(content: StudioComposition(run: run, edition: edition, mapImage: mapImage))
        renderer.scale = 2
        return renderer.uiImage
    }
}
