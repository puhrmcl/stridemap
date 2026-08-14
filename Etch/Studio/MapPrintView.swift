import SwiftUI

/// The aggregate map-print screen: preview a full-history poster, switch between the four kinds
/// (all runs / states / cities / landmarks), and export or order a print. The counterpart to the
/// single-run `StudioView`.
struct MapPrintView: View {
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MapPrintKind
    @State private var rendered: [MapPrintKind: UIImage] = [:]
    @State private var rendering: Set<MapPrintKind> = []
    @State private var showExport = false
    @State private var showPrints = false

    init(runs: [Run], kind: MapPrintKind = .allRuns) {
        self.runs = runs
        _kind = State(initialValue: kind)
    }

    private var request: MapPrintRequest { MapPrintRequest.make(kind: kind, runs: runs) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                controls
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Full-Map Print")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPrints = true } label: { Image(systemName: "bag") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showExport = true } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
            .sheet(isPresented: $showExport) { MapPrintExportSheet(request: request) }
            .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: request.title) }
            .task(id: kind) { await renderIfNeeded(kind) }
        }
    }

    private var preview: some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let image = rendered[kind] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.Palette.bone)
                        .aspectRatio(MapPrintComposition.width / MapPrintComposition.size.height, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                ProgressView().tint(Theme.accent)
                                Text("Composing…")
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                }
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Picker("Kind", selection: $kind) {
                ForEach(MapPrintKind.allCases) { kind in
                    Label(kind.name, systemImage: kind.symbol).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(kind.descriptor)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func renderIfNeeded(_ kind: MapPrintKind) async {
        guard rendered[kind] == nil, !rendering.contains(kind) else { return }
        rendering.insert(kind)
        defer { rendering.remove(kind) }
        if let image = await MapPrintRenderer.image(for: MapPrintRequest.make(kind: kind, runs: runs), scale: 2) {
            rendered[kind] = image
        }
    }
}
