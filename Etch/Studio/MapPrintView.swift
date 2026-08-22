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
    @State private var artStyle: MapArtStyle = .grid
    @State private var artWeight: MapArtWeight = .medium
    /// Narrows which runs the Wall Art draws from (all / favorites / races / a year / a place).
    @State private var artFilter: ArtFilter = .all

    /// A subset selector for the Wall Art. Only choices that actually match runs are offered.
    enum ArtFilter: Hashable {
        case all, favorites, races
        case year(Int)
        case place(String)   // a city short-label from `travelPlaces`
        case state(String)   // a state as stored on the run (e.g. "AZ")
    }
    /// Single-state print: editable title + which metrics are shown.
    @State private var stateTitle: String = ""
    @State private var stateMetrics: Set<StateMetric> = Set(StateMetric.allCases)
    /// >1 tightens onto the core, <1 pulls back for context.
    @State private var zoom: Double = 1.0
    /// Accumulated pan, as fractions of the current span.
    @State private var panX: Double = 0
    @State private var panY: Double = 0
    /// States aggregate: clean US choropleth (no base map, so no Canada / Mexico).
    @State private var statesUSAOnly = false
    /// Aggregate prints: show the footer (title / stats / caption) or the map alone.
    @State private var showDetails = true

    @State private var rendered: [String: UIImage] = [:]
    @State private var rendering: Set<String> = []
    @State private var showExport = false
    @State private var showPrints = false

    init(runs: [Run], kind: MapPrintKind = .allRuns, artStyle: MapArtStyle = .grid) {
        self.runs = runs
        _kind = State(initialValue: kind)
        // The Archive Collection opens Wall Art directly on a chosen style.
        _artStyle = State(initialValue: artStyle)
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

    /// A compact "City, ST" label for a travel place (drops the country).
    private func cityLabel(_ place: RunStatistics.TravelPlace) -> String {
        let parts = place.label.components(separatedBy: ", ")
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ", ") : place.label
    }

    /// The runs the Wall Art draws from, after the active filter.
    private var artFilteredRuns: [Run] {
        switch artFilter {
        case .all:       return runs
        case .favorites: return runs.filter(\.isFavorite)
        case .races:     return runs.filter(\.isRace)
        case .year(let y):
            let cal = Calendar.current
            return runs.filter { cal.component(.year, from: $0.startDate) == y }
        case .place(let name):
            guard let place = RunStatistics(runs).travelPlaces.first(where: { cityLabel($0) == name }) else { return runs }
            let ids = Set(place.runs.map(\.id))
            return runs.filter { ids.contains($0.id) }
        case .state(let name):
            return runs.filter { ($0.state ?? "") == name }
        }
    }

    private var artFilterLabel: String {
        switch artFilter {
        case .all:       return "All Runs"
        case .favorites: return "Favorites"
        case .races:     return "Races"
        case .year(let y): return String(y)
        case .place(let name): return name
        case .state(let name): return name
        }
    }

    /// The base request — a single place drawn as routes, or the aggregate for the kind.
    private var baseRequest: MapPrintRequest {
        if kind.isArt {
            var req = MapPrintRequest.make(kind: kind, runs: artFilteredRuns)
            // Home Turf defaults to a zoom on the densest area (the most-run city), not the whole
            // country — otherwise a spread-out history renders as scattered specks.
            if artStyle == .homeTurf, let region = MapPrintRequest.homeTurfRegion(runs: artFilteredRuns) {
                req.region = region
            }
            return req
        }
        if let focusName, let place = focusPlaces.first(where: { $0.name == focusName }) {
            var req = MapPrintRequest.make(kind: .allRuns, runs: place.runs)
            if kind == .states {
                req.isSingleState = true
                req.stateMetrics = StateMetric.allCases.filter { stateMetrics.contains($0) }
                req.titleOverride = stateTitle.isEmpty ? nil : stateTitle
                // Centre on the state and show its full name; resolve from a run's coordinate so it
                // works whether run.state is an abbreviation ("AZ") or a full name.
                if let coord = place.runs.lazy.compactMap(\.startCoordinate).first,
                   let boundaryName = USStateBoundaries.shared.region(containing: coord) {
                    req.boundaryStateName = boundaryName
                    req.title = boundaryName
                    if let rect = USStateBoundaries.shared.boundingMapRect(for: boundaryName) {
                        req.region = MKCoordinateRegion(rect.insetBy(dx: -rect.width * 0.06,
                                                                     dy: -rect.height * 0.06))
                    }
                }
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
        req.artWeight = artWeight
        req.artZoom = CGFloat(zoom)   // Bloom (and other region-free art) scale by this.
        let factor = 1.0 / zoom
        let latSpan = min(170, max(0.002, req.region.span.latitudeDelta * factor))
        let lonSpan = min(340, max(0.002, req.region.span.longitudeDelta * factor))
        let center = CLLocationCoordinate2D(
            latitude: req.region.center.latitude + panY * latSpan,
            longitude: req.region.center.longitude - panX * lonSpan
        )
        req.region = MKCoordinateRegion(center: center,
                                        span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        req.statesUSAOnly = statesUSAOnly && kind == .states && focusName == nil
        req.showFooter = showDetails || kind.isArt || isSingleState
        return req
    }

    /// Aggregate map prints (not Wall Art, not a single state) expose the USA-only / details toggles.
    private var showsAggregateOptions: Bool { !kind.isArt && !isSingleState }

    private var isSingleState: Bool { kind == .states && focusName != nil }

    private var stateMetricsKey: String {
        StateMetric.allCases.filter { stateMetrics.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private var currentKey: String {
        "\(kind.rawValue)-\(focusName ?? "all")-\(orientation.rawValue)-\(artPalette.rawValue)-\(artStyle.rawValue)-\(artWeight.rawValue)-" +
        "\(artFilterLabel)-\(stateTitle)|\(stateMetricsKey)-\(statesUSAOnly)-\(showDetails)-" +
        String(format: "%.2f-%.2f-%.2f", zoom, panX, panY)
    }

    private var previewAspect: CGFloat {
        // Map-only aggregate prints are the square panel alone.
        if showsAggregateOptions && !showDetails { return 1 }
        let s: CGSize
        if kind.isArt {
            s = orientation == .landscape ? CGSize(width: 1500, height: 1000) : CGSize(width: 1000, height: 1500)
        } else if isSingleState {
            s = orientation == .landscape ? CGSize(width: 1500, height: 1000) : CGSize(width: 1000, height: 1400)
        } else {
            s = MapPrintComposition.nominalSize(orientation)
        }
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
            .onChange(of: kind) { focusName = nil; stateTitle = ""; artFilter = .all; statesUSAOnly = false; resetFrame() }
            .onChange(of: focusName) { stateTitle = ""; resetFrame() }
            // Each art style has its own default framing (Home Turf zooms to the home city), so
            // start fresh when switching rather than carrying over a prior zoom/pan.
            .onChange(of: artStyle) { resetFrame() }
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
                        guard panRelevant, geo.size.width > 0, geo.size.height > 0 else { return }
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { artFilterMenu; styleMenu; paletteMenu; weightMenu }
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: 360)
            }
            if isSingleState { stateControls }

            if showsAggregateOptions { aggregateToggles }

            Text(descriptorText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Picker("Orientation", selection: $orientation) {
                ForEach(StudioOrientation.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            if zoomRelevant { zoomPanRow }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    /// Toggles for the aggregate map prints: a clean USA-only states map, and a map-only mode that
    /// hides the footer entirely.
    private var aggregateToggles: some View {
        VStack(spacing: 6) {
            if kind == .states && focusName == nil {
                Toggle("USA only (hide Canada & Mexico)", isOn: $statesUSAOnly)
            }
            Toggle("Show details", isOn: $showDetails)
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .font(.system(.subheadline, design: .rounded))
        .frame(maxWidth: 320)
    }

    private var descriptorText: String {
        if kind.isArt { return artStyle.descriptor }
        if focusName != nil { return "A single \(singularKindName), framed to its runs." }
        return kind.descriptor
    }

    /// When the zoom control applies. Every map-based print, plus the art styles that scale:
    /// Home Turf / Constellation frame by geography, and Bloom scales its radiating routes. Grid
    /// (a fixed contact sheet) has no zoom.
    private var zoomRelevant: Bool {
        if kind.isArt { return artStyle == .homeTurf || artStyle == .constellation || artStyle == .bloom }
        return true
    }

    /// When drag-to-pan applies — only the geography-framed views. Bloom is centred, so it zooms
    /// but doesn't pan.
    private var panRelevant: Bool {
        if kind.isArt { return artStyle == .homeTurf || artStyle == .constellation }
        return true
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

    private var weightMenu: some View {
        Menu {
            Picker("Weight", selection: $artWeight) {
                ForEach(MapArtWeight.allCases) { Text($0.name).tag($0) }
            }
        } label: {
            menuChip(icon: "lineweight", text: artWeight.name)
        }
    }

    /// Narrows the Wall Art to a subset of runs. Only options that match at least one run are
    /// shown, so a selection can never empty the poster.
    private var artFilterMenu: some View {
        let stats = RunStatistics(runs)
        let years = stats.years
        let places = stats.travelPlaces
        let grouped: [String: [Run]] = Dictionary(grouping: runs.filter { !($0.state ?? "").isEmpty },
                                                  by: { $0.state ?? "" })
        let states: [(name: String, count: Int)] = grouped
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        return Menu {
            Button { artFilter = .all } label: {
                Label("All Runs", systemImage: artFilter == .all ? "checkmark" : "circle.grid.2x2")
            }
            if runs.contains(where: \.isFavorite) {
                Button { artFilter = .favorites } label: {
                    Label("Favorites", systemImage: artFilter == .favorites ? "checkmark" : "star")
                }
            }
            if runs.contains(where: \.isRace) {
                Button { artFilter = .races } label: {
                    Label("Races", systemImage: artFilter == .races ? "checkmark" : "flag.checkered")
                }
            }
            if !years.isEmpty {
                Menu("Year") {
                    ForEach(years, id: \.self) { year in
                        Button(String(year)) { artFilter = .year(year) }
                    }
                }
            }
            if !states.isEmpty {
                Menu("State") {
                    ForEach(states, id: \.name) { state in
                        Button("\(state.name)  ·  \(state.count)") { artFilter = .state(state.name) }
                    }
                }
            }
            if !places.isEmpty {
                Menu("Location") {
                    ForEach(places) { place in
                        Button("\(cityLabel(place))  ·  \(place.runs.count)") {
                            artFilter = .place(cityLabel(place))
                        }
                    }
                }
            }
        } label: {
            menuChip(icon: "line.3.horizontal.decrease", text: artFilterLabel)
        }
    }

    /// The full state name, used as the editable title's placeholder.
    private var currentStateName: String {
        guard let place = focusPlaces.first(where: { $0.name == focusName }),
              let coord = place.runs.lazy.compactMap(\.startCoordinate).first,
              let name = USStateBoundaries.shared.region(containing: coord) else { return focusName ?? "State" }
        return name
    }

    private var stateControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "textformat").font(.caption).foregroundStyle(.secondary)
                TextField(currentStateName, text: $stateTitle)
                    .font(.system(.subheadline, design: .rounded))
                    .textInputAutocapitalization(.words)
                if !stateTitle.isEmpty {
                    Button { stateTitle = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 340)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StateMetric.allCases) { metricChip($0) }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: 360)
        }
    }

    private func metricChip(_ metric: StateMetric) -> some View {
        let on = stateMetrics.contains(metric)
        return Button {
            if on { stateMetrics.remove(metric) } else { stateMetrics.insert(metric) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.caption)
                Text(metric.name).font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(on ? Color.white : Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(on ? Theme.accent : Theme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
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
            if panRelevant {
                Label("Drag to pan", systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)
            }

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
