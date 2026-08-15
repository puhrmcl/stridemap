import SwiftUI
import MapKit

/// The aggregate map-print screen: preview a full-history poster, switch between kinds, narrow to
/// a single state / city / country, choose orientation, and zoom / pan the frame before export.
struct MapPrintView: View {
    let runs: [Run]
    @Environment(\.dismiss) private var dismiss

    @State private var kind: MapPrintKind
    /// A specific place within the current kind; nil = the aggregate.
    @State private var focusName: String?
    @State private var orientation: StudioOrientation = .portrait
    @State private var artPalette: MapArtPalette = .gallery
    @State private var artStyle: MapArtStyle = .lines
    /// >1 tightens onto the core, <1 pulls back for context.
    @State private var zoom: Double = 1.0
    /// Accumulated pan, as fractions of the current span.
    @State private var panX: Double = 0
    @State private var panY: Double = 0

    @State private var rendered: [String: UIImage] = [:]
    @State private var rendering: Set<String> = []
    @State private var showExport = false
    @State private var showPrints = false

    init(runs: [Run], kind: MapPrintKind = .allRuns) {
        self.runs = runs
        _kind = State(initialValue: kind)
    }

    // MARK: Places + request

    /// The single-place options for the current kind (empty for All Runs / Landmarks).
    private var focusPlaces: [(name: String, runs: [Run])] {
        switch kind {
        case .cities:
            return RunStatistics(runs).travelPlaces.map { place in
                let parts = place.label.components(separatedBy: ", ")
                let name = parts.count >= 2 ? parts.prefix(2).joined(separator: ", ") : place.label
                return (name, place.runs)
            }
        case .countries:
            return RunStatistics(runs).countryPlaces.map { ($0.label, $0.runs) }
        case .states:
            let grouped = Dictionary(grouping: runs.filter { !($0.state ?? "").isEmpty }, by: { $0.state ?? "" })
            return grouped.map { (name: $0.key, runs: $0.value) }.sorted { $0.runs.count > $1.runs.count }
        case .artMap, .allRuns, .landmarks:
            return []
        }
    }

    /// The base request — a single place drawn as routes, or the aggregate for the kind.
    private var baseRequest: MapPrintRequest {
        if let focusName, let place = focusPlaces.first(where: { $0.name == focusName }) {
            var req = MapPrintRequest.make(kind: .allRuns, runs: place.runs)
            // Outline the state. Resolve the boundary from a run's coordinate so it works whether
            // run.state is an abbreviation ("AZ") or a full name.
            if kind == .states,
               let coord = place.runs.lazy.compactMap(\.startCoordinate).first,
               let boundaryName = USStateBoundaries.shared.region(containing: coord) {
                req.boundaryStateName = boundaryName
            }
            return req
        }
        return MapPrintRequest.make(kind: kind, runs: runs)
    }

    /// The base request with orientation, zoom (span) and pan (centre) applied.
    private var request: MapPrintRequest {
        var req = baseRequest
        req.orientation = orientation
        req.artPalette = artPalette
        req.artStyle = artStyle
        let factor = 1.0 / zoom
        let latSpan = min(170, max(0.002, req.region.span.latitudeDelta * factor))
        let lonSpan = min(340, max(0.002, req.region.span.longitudeDelta * factor))
        let center = CLLocationCoordinate2D(
            latitude: req.region.center.latitude + panY * latSpan,
            longitude: req.region.center.longitude - panX * lonSpan
        )
        req.region = MKCoordinateRegion(center: center,
                                        span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        return req
    }

    private var currentKey: String {
        "\(kind.rawValue)-\(focusName ?? "all")-\(orientation.rawValue)-\(artPalette.rawValue)-\(artStyle.rawValue)-" +
        String(format: "%.2f-%.2f-%.2f", zoom, panX, panY)
    }

    private var previewAspect: CGFloat {
        let s = kind.isArt
            ? (orientation == .landscape ? CGSize(width: 1500, height: 1000) : CGSize(width: 1000, height: 1500))
            : MapPrintComposition.nominalSize(orientation)
        return s.width / s.height
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
            .task(id: currentKey) { await renderIfNeeded(currentKey) }
            .onChange(of: kind) { focusName = nil; resetFrame() }
            .onChange(of: focusName) { resetFrame() }
        }
    }

    // MARK: Preview (with drag-to-pan)

    private var preview: some View {
        GeometryReader { geo in
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
                            .aspectRatio(previewAspect, contentMode: .fit)
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
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onEnded { value in
                        guard geo.size.width > 0, geo.size.height > 0 else { return }
                        panX += Double(value.translation.width / geo.size.width)
                        panY += Double(value.translation.height / geo.size.height)
                    }
            )
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                kindMenu
                if kind.supportsSinglePlace, !focusPlaces.isEmpty { placeMenu }
            }
            if kind.isArt {
                HStack(spacing: 10) { paletteMenu; styleMenu }
            }

            Text(focusName == nil ? kind.descriptor : "A single \(singularKindName), framed to its runs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Picker("Orientation", selection: $orientation) {
                ForEach(StudioOrientation.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            zoomPanRow
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var singularKindName: String {
        switch kind {
        case .states: return "state"
        case .cities: return "city"
        case .countries: return "country"
        default: return "place"
        }
    }

    private var kindMenu: some View {
        Menu {
            Picker("Kind", selection: $kind) {
                ForEach(MapPrintKind.allCases) { kind in
                    Label(kind.name, systemImage: kind.symbol).tag(kind)
                }
            }
        } label: {
            menuChip(icon: kind.symbol, text: kind.name)
        }
    }

    private var placeMenu: some View {
        Menu {
            Button("All \(kind.name)") { focusName = nil }
            ForEach(focusPlaces, id: \.name) { place in
                Button("\(place.name)  ·  \(place.runs.count)") { focusName = place.name }
            }
        } label: {
            menuChip(icon: "scope", text: focusName ?? "All \(kind.name)")
        }
    }

    private var paletteMenu: some View {
        Menu {
            Picker("Palette", selection: $artPalette) {
                ForEach(MapArtPalette.allCases) { Text($0.name).tag($0) }
            }
        } label: {
            menuChip(icon: "paintpalette", text: artPalette.name)
        }
    }

    private var styleMenu: some View {
        Menu {
            Picker("Style", selection: $artStyle) {
                ForEach(MapArtStyle.allCases) { Text($0.name).tag($0) }
            }
        } label: {
            menuChip(icon: "wand.and.stars", text: artStyle.name)
        }
    }

    private func menuChip(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption)
            Text(text).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.1), in: .capsule)
    }

    private var zoomPanRow: some View {
        HStack(spacing: 16) {
            Button { setZoom(zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass").font(.title3) }
                .disabled(zoom <= 0.4)
            Text(String(format: "%.1f×", zoom))
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .frame(width: 46)
            Button { setZoom(zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass").font(.title3) }
                .disabled(zoom >= 6)

            Spacer(minLength: 8)
            Label("Drag to pan", systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)

            if zoom != 1 || panX != 0 || panY != 0 {
                Button("Reset") { resetFrame() }.font(.system(.subheadline, design: .rounded))
            }
        }
        .tint(Theme.accent)
        .frame(maxWidth: 360)
    }

    private func setZoom(_ value: Double) {
        withAnimation(.easeInOut(duration: 0.2)) { zoom = min(6, max(0.4, value)) }
    }

    private func resetFrame() {
        zoom = 1; panX = 0; panY = 0
    }

    private func renderIfNeeded(_ cacheKey: String) async {
        guard rendered[cacheKey] == nil, !rendering.contains(cacheKey) else { return }
        rendering.insert(cacheKey)
        defer { rendering.remove(cacheKey) }
        if let image = await MapPrintRenderer.image(for: request, scale: 2) {
            rendered[cacheKey] = image
        }
    }
}
