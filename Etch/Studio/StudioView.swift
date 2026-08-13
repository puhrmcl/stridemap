import SwiftUI

/// Etch Studio: a gallery-like way to turn a run into a finished piece. The user swipes
/// through curated *editions* — each a complete composition, not a set of controls — and
/// exports the one they want. Deliberately editorial: the artwork is the hero, chrome is quiet.
struct StudioView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss

    @State private var selection: StudioEdition.ID = .gallery
    @State private var includeWeather = false
    /// Rendered artwork, keyed by edition + weather state so toggling re-renders correctly.
    @State private var rendered: [String: UIImage] = [:]
    @State private var rendering: Set<String> = []

    private var current: StudioEdition { StudioEdition.edition(selection) }
    private var currentKey: String { key(selection) }
    private func key(_ id: StudioEdition.ID) -> String { "\(id.rawValue)-\(includeWeather)" }

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
                    if let image = rendered[currentKey] {
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
            .task(id: currentKey) { await renderIfNeeded(selection) }
        }
    }

    // MARK: Pages

    private func page(for edition: StudioEdition) -> some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let image = rendered[key(edition.id)] {
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

            if run.hasWeather {
                Toggle(isOn: $includeWeather) {
                    Label("Include weather", systemImage: "cloud.sun")
                        .font(.system(.subheadline, design: .rounded))
                }
                .tint(Theme.accent)
                .frame(maxWidth: 280)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    // MARK: Rendering

    private func renderIfNeeded(_ id: StudioEdition.ID) async {
        let k = key(id)
        guard rendered[k] == nil, !rendering.contains(k) else { return }
        rendering.insert(k)
        defer { rendering.remove(k) }
        if let image = await render(StudioEdition.edition(id)) {
            rendered[k] = image
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
        let composition = StudioComposition(
            run: run, edition: edition, mapImage: mapImage, includeWeather: includeWeather
        )
        let renderer = ImageRenderer(content: composition)
        renderer.scale = 2
        return renderer.uiImage
    }
}
