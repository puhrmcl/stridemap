import SwiftUI

/// Etch Studio: a gallery-like way to turn a run into a finished piece. The user swipes
/// through curated *editions* — each a complete composition — and can retune the path and text
/// colours from a curated set before exporting. Deliberately editorial: the artwork is the
/// hero, chrome stays quiet.
struct StudioView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss

    @State private var selection: StudioEdition.ID = .gallery
    @State private var includeWeather = false
    @State private var routeColor: Color?
    @State private var textColor: Color?
    @State private var showPrints = false
    /// Bumped on any customization change; part of the cache key so artwork re-renders.
    @State private var revision = 0

    @State private var rendered: [String: UIImage] = [:]
    @State private var rendering: Set<String> = []

    private let pathSwatches: [Color] = [
        Theme.Palette.blue, Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass, Theme.Palette.sage
    ]
    private let textSwatches: [Color] = [Theme.Palette.ink, Theme.Palette.bone, Theme.Palette.brass]

    private var editions: [StudioEdition] { StudioEdition.available(for: run) }
    private var current: StudioEdition { StudioEdition.edition(selection) }
    private func key(_ id: StudioEdition.ID) -> String { "\(id.rawValue)-\(revision)" }
    private var currentKey: String { key(selection) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(editions) { edition in
                        page(for: edition).tag(edition.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                controls
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Etch Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPrints = true } label: { Image(systemName: "bag") }
                }
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
            .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: run.name) }
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

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(editions) { edition in
                    Circle()
                        .fill(edition.id == selection ? Theme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            VStack(spacing: 2) {
                Text(current.name)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(current.descriptor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            colorRow("Path", selection: $routeColor, swatches: pathSwatches, fallback: current.route)
            colorRow("Text", selection: $textColor, swatches: textSwatches, fallback: current.ink)

            if run.hasWeather {
                Toggle(isOn: $includeWeather) {
                    Label("Include weather", systemImage: "cloud.sun")
                        .font(.system(.subheadline, design: .rounded))
                }
                .tint(Theme.accent)
                .frame(maxWidth: 280)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .onChange(of: includeWeather) { bump() }
        .onChange(of: routeColor) { bump() }
        .onChange(of: textColor) { bump() }
    }

    private func colorRow(_ title: String, selection: Binding<Color?>, swatches: [Color], fallback: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)

            autoChip(isSelected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
            ForEach(swatches.indices, id: \.self) { i in
                swatchDot(swatches[i], isSelected: selection.wrappedValue == swatches[i]) {
                    selection.wrappedValue = swatches[i]
                }
            }
            ColorPicker("", selection: Binding(
                get: { selection.wrappedValue ?? fallback },
                set: { selection.wrappedValue = $0 }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32)
        }
    }

    private func autoChip(isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Auto")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(isSelected ? Theme.accent : Color.secondary.opacity(0.15), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func swatchDot(_ color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Circle().stroke(Theme.accent, lineWidth: isSelected ? 2.5 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Rendering

    private func bump() {
        rendered.removeAll()
        rendering.removeAll()
        revision += 1
    }

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
        let panelSize = CGSize(width: StudioComposition.width, height: StudioComposition.artHeight)
        var panelImage: UIImage?
        if edition.isPhoto {
            // Memory fills the panel with the run's photo; the route is drawn over it in the
            // composition.
            if let id = run.photoReferences.first {
                panelImage = await PhotoLibrary.image(for: id, targetSize: CGSize(width: 2000, height: 2000))
            }
        } else if edition.mapKind != nil {
            panelImage = await PosterMap.studioPanel(for: run, size: panelSize, edition: edition, route: routeColor)
        }
        let composition = StudioComposition(
            run: run, edition: edition, panelImage: panelImage,
            includeWeather: includeWeather, routeOverride: routeColor, textOverride: textColor
        )
        let renderer = ImageRenderer(content: composition)
        renderer.scale = 2
        return renderer.uiImage
    }
}
