import SwiftUI
import MapKit

/// The aggregate map-print screen: preview a full-history poster, switch between the four kinds
/// (all runs / states / cities / landmarks), zoom the frame, and export or order a print. The
/// counterpart to the single-run `StudioView`.
struct MapPrintView: View {
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MapPrintKind
    /// Frame zoom: >1 tightens onto the core, <1 pulls back for more context.
    @State private var zoom: Double = 1.0
    @State private var rendered: [String: UIImage] = [:]
    @State private var rendering: Set<String> = []
    @State private var showExport = false
    @State private var showPrints = false

    init(runs: [Run], kind: MapPrintKind = .allRuns) {
        self.runs = runs
        _kind = State(initialValue: kind)
    }

    private func key(_ kind: MapPrintKind) -> String { "\(kind.rawValue)-\(String(format: "%.2f", zoom))" }
    private var currentKey: String { key(kind) }
    private var request: MapPrintRequest { zoomedRequest(kind) }

    /// The base request for a kind, with its region span scaled by the current zoom.
    private func zoomedRequest(_ kind: MapPrintKind) -> MapPrintRequest {
        var req = MapPrintRequest.make(kind: kind, runs: runs)
        let factor = 1.0 / zoom
        req.region = MKCoordinateRegion(
            center: req.region.center,
            span: MKCoordinateSpan(
                latitudeDelta: min(170, max(0.002, req.region.span.latitudeDelta * factor)),
                longitudeDelta: min(340, max(0.002, req.region.span.longitudeDelta * factor))
            )
        )
        return req
    }

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
            .task(id: currentKey) { await renderIfNeeded(currentKey, kind: kind) }
        }
    }

    private var preview: some View {
        VStack {
            Spacer(minLength: 0)
            Group {
                if let image = rendered[currentKey] {
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

            zoomRow
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var zoomRow: some View {
        HStack(spacing: 18) {
            Button { setZoom(zoom / 1.4) } label: {
                Image(systemName: "minus.magnifyingglass").font(.title3)
            }
            .disabled(zoom <= 0.4)

            Text(String(format: "%.1f×", zoom))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(width: 52)

            Button { setZoom(zoom * 1.4) } label: {
                Image(systemName: "plus.magnifyingglass").font(.title3)
            }
            .disabled(zoom >= 6)

            if abs(zoom - 1) > 0.01 {
                Button("Reset") { setZoom(1) }
                    .font(.system(.subheadline, design: .rounded))
            }
        }
        .tint(Theme.accent)
    }

    private func setZoom(_ value: Double) {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoom = min(6, max(0.4, value))
        }
    }

    private func renderIfNeeded(_ cacheKey: String, kind: MapPrintKind) async {
        guard rendered[cacheKey] == nil, !rendering.contains(cacheKey) else { return }
        rendering.insert(cacheKey)
        defer { rendering.remove(cacheKey) }
        if let image = await MapPrintRenderer.image(for: zoomedRequest(kind), scale: 2) {
            rendered[cacheKey] = image
        }
    }
}
