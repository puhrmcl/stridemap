import SwiftUI

/// How the run's data is arranged beneath the art — chosen independently of the edition.
enum StudioLayout: String, CaseIterable, Identifiable {
    case classic, minimal, editorial, grid, gallery, keepsake
    var id: String { rawValue }
    var name: String {
        switch self {
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        case .editorial: return "Editorial"
        case .grid: return "4-Up"
        case .gallery: return "Gallery"
        case .keepsake: return "Keepsake"
        }
    }
}

/// What a single Gallery tile shows. "photo" tiles draw the run's photos in order; the others draw
/// the route as a map, the bare route line, or the elevation profile.
enum GalleryTileKind: String, CaseIterable, Identifiable {
    case photo, map, route, elevation
    var id: String { rawValue }
    var name: String {
        switch self {
        case .photo: return "Photo"
        case .map: return "Map"
        case .route: return "Route"
        case .elevation: return "Elevation"
        }
    }
    var icon: String {
        switch self {
        case .photo: return "photo"
        case .map: return "map"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .elevation: return "mountain.2"
        }
    }
}

/// Poster orientation. Portrait stacks the art over the footer; landscape can set the art beside
/// the data (side) or above it (bottom), per `StudioDataPlacement`.
enum StudioOrientation: String, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }
    var name: String { self == .portrait ? "Portrait" : "Landscape" }
    var symbol: String { self == .portrait ? "rectangle.portrait" : "rectangle" }
}

/// The share/export canvas. `poster` keeps the composition's native print proportions; the others
/// mat it onto a social-platform aspect (the poster centred on its ground colour) for digital
/// sharing — no layout reflow, so every edition stays composed at any size.
enum StudioOutputSize: String, CaseIterable, Identifiable {
    case poster, square, feed, story
    var id: String { rawValue }
    var name: String {
        switch self {
        case .poster: return "Poster"
        case .square: return "Square"
        case .feed:   return "Feed"
        case .story:  return "Story"
        }
    }
    /// A shape/social cue for the picker (SF Symbols has no brand logos, so these evoke the format).
    var symbol: String {
        switch self {
        case .poster: return "photo.artframe"
        case .square: return "square"
        case .feed:   return "rectangle.portrait"
        case .story:  return "iphone"
        }
    }
    /// Target width ÷ height. nil keeps the composition's native aspect.
    var aspect: CGFloat? {
        switch self {
        case .poster: return nil
        case .square: return 1
        case .feed:   return 4.0 / 5.0    // Instagram feed
        case .story:  return 9.0 / 16.0   // Stories / Reels / TikTok
        }
    }
}

/// Where the run data sits relative to the art in landscape — beside it (left / right) or across
/// it (top / bottom). Ignored in portrait (always bottom).
enum StudioDataPlacement: String, CaseIterable, Identifiable {
    case left, right, top, bottom
    var id: String { rawValue }
    var name: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
    var symbol: String {
        switch self {
        case .left: return "rectangle.lefthalf.inset.filled"
        case .right: return "rectangle.righthalf.inset.filled"
        case .top: return "rectangle.tophalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }
    /// Data sits beside the art as a vertical column (left / right), vs. across it (top / bottom).
    var isSide: Bool { self == .left || self == .right }
    /// Maps a stored raw value, translating the pre-b289 `side` name onto the new `right`.
    static func from(raw: String) -> StudioDataPlacement {
        switch raw {
        case "left":  return .left
        case "top":   return .top
        case "bottom": return .bottom
        default:      return .right   // "right" and legacy "side"
        }
    }
}

/// How the Memory edition arranges the run's photos in the art panel. Only meaningful when the
/// run has more than one photo; `single` shows the cover photo, `grid` composes a tasteful
/// 2–4-up arrangement.
enum StudioPhotoLayout: String, CaseIterable, Identifiable {
    case single, grid
    var id: String { rawValue }
    var name: String {
        switch self {
        case .single: return "Single"
        case .grid: return "Grid"
        }
    }
    /// How many photos this layout draws on.
    var maxPhotos: Int { self == .single ? 1 : 4 }
}

/// The Etch Studio artwork: one parametric composition rendering any edition + layout for a
/// run. Image editions (map snapshot, photo) receive a pre-rendered `panelImage`; paper
/// editions draw the route as vector art. Rendered to an image for preview and export.
///
/// Brand typographic hierarchy — a large distance statement, the "Etched." mark as the one
/// quiet signal, wide-tracked uppercase metadata, sparse metrics. Route and text colours may
/// be overridden; the edition supplies the defaults.
struct StudioComposition: View {
    let run: Run
    let edition: StudioEdition
    /// Pre-rendered art panel (map snapshot); nil for paper and photo editions.
    var panelImage: UIImage?
    /// Loaded photos for the Memory edition, in cover-first order. One for `single`, up to four
    /// for `grid`. Empty for non-photo editions.
    var photoImages: [UIImage] = []
    var includeWeather: Bool = false
    var layout: StudioLayout = .classic
    var orientation: StudioOrientation = .portrait
    var dataPlacement: StudioDataPlacement = .right
    var photoLayout: StudioPhotoLayout = .single
    /// User-typed overrides for the title and date; nil/empty falls back to the run's values.
    var titleOverride: String? = nil
    var dateOverride: String? = nil
    /// Editorial layout only: show the cover photo in the open space beside the text.
    var showEditorialPhoto: Bool = false
    /// Memory edition only: etch the route over the photo(s).
    var showMemoryRoute: Bool = false
    /// The metric shown as the big headline.
    var heroMetric: StatMetric = .distance
    /// The footer's metric slots, in order — "complications" the user can retune.
    var statSlots: [StatMetric] = [.time, .pace, .elevationGain]
    /// Terrain elevations along the route (metres) for the profile silhouette; empty = no strip.
    var elevationSamples: [Double] = []
    var showElevationProfile: Bool = false
    /// Gallery layout only: use the route map as one of the tiles (with map background on a map
    /// edition, or the bare route line on a paper edition).
    var galleryShowMapTile: Bool = false
    /// Gallery layout only: the tile plan, in order. Empty falls back to the map-toggle default.
    /// Each raw value is a `GalleryTileKind`; "photo" tiles draw the run's photos in order.
    var galleryCellsRaw: [String] = []
    /// User overrides; nil falls back to the edition's palette.
    var routeOverride: Color? = nil
    var textOverride: Color? = nil
    var groundOverride: Color? = nil

    // MARK: Remodel options
    /// Tone every vector colour to grey (the raster panels are desaturated upstream).
    var monochrome: Bool = false
    /// The curated Title typeface.
    var titleFont: PosterFont = .editorial
    /// Whether the title line is drawn.
    var showTitle: Bool = true
    /// Whether the location line is drawn.
    var showLocation: Bool = true
    /// Whether the date line is drawn.
    var showDate: Bool = true
    /// Location override; nil falls back to the run's city/state.
    var locationOverride: String? = nil
    /// Which of the five Gallery art layouts to compose (Gallery product only).
    var galleryDesignRaw: String = GalleryDesign.portfolio.rawValue
    /// Map product layout — statement (full footer) / minimal (title + date) / photo (photo strip).
    var mapLayoutRaw: String = MapLayout.statement.rawValue
    /// How many photos the map Photo layout shows (1–3).
    var mapPhotoCount: Int = 1
    /// Multiplies every text (and glyph) point size on the poster, so the user can dial the type
    /// larger or smaller. 1 = the designed size.
    var textScale: CGFloat = 1
    /// The print shape this artwork is composed into. 2:3 is the primary — it serves 12×18, 16×24
    /// and 24×36, the entire launch catalogue.
    var printAspect: PrintAspect = .twoThree

    /// A font point size scaled by `textScale` — every `.system(size:)` on the poster runs through
    /// this so one control resizes the whole composition's type together.
    private func ts(_ size: CGFloat) -> CGFloat { size * textScale }

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    /// Footer column width in landscape when the data sits beside the art.
    static let landscapeFooterWidth: CGFloat = 640
    /// Wide art size when landscape sets the data across the bottom.
    static let wideArtWidth: CGFloat = 1640
    static let wideArtHeight: CGFloat = 920

    /// The art panel's pixel size for an orientation + placement.
    static func artSize(_ orientation: StudioOrientation, _ placement: StudioDataPlacement) -> CGSize {
        (orientation == .landscape && !placement.isSide)
            ? CGSize(width: wideArtWidth, height: wideArtHeight)
            : CGSize(width: width, height: artHeight)
    }

    /// The exact canvas an artwork is composed into, in points, for a supported print aspect.
    /// Portrait uses the aspect directly; landscape inverts it. This is the *authoritative* output
    /// shape — the composition is framed to it, so the rendered pixels always match a print size.
    static func canvasSize(_ orientation: StudioOrientation,
                           _ placement: StudioDataPlacement,
                           _ aspect: PrintAspect) -> CGSize {
        switch (orientation, placement) {
        case (.portrait, _):
            return CGSize(width: width, height: width / aspect.ratio)
        case (.landscape, .left), (.landscape, .right):
            return CGSize(width: width + landscapeFooterWidth, height: artHeight)
        case (.landscape, .top), (.landscape, .bottom):
            // Landscape: the same ratio, on its side.
            return CGSize(width: wideArtWidth, height: wideArtWidth * aspect.ratio)
        }
    }

    /// Nominal poster size — used for print-scale math and preview aspect ratios. Now identical to
    /// the canvas, so `printImage`'s scale arithmetic describes the pixels it actually produces.
    static func nominalSize(_ orientation: StudioOrientation, _ placement: StudioDataPlacement,
                            _ aspect: PrintAspect = .twoThree) -> CGSize {
        canvasSize(orientation, placement, aspect)
    }

    /// Grey version of a colour (luminance), used when the poster is monochrome so the route and
    /// type read as considered black-and-white rather than a lone colour on a grey photo.
    private func toneMono(_ c: Color) -> Color {
        guard monochrome else { return c }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        let y = 0.299 * r + 0.587 * g + 0.114 * b
        return Color(red: Double(y), green: Double(y), blue: Double(y)).opacity(Double(a))
    }

    private var routeColor: Color { toneMono(routeOverride ?? edition.route) }
    /// Ground keeps its chosen tone even in monochrome (a warm paper or deep ink still reads);
    /// only the coloured marks (route, accents) are toned to grey.
    private var groundColor: Color { groundOverride ?? edition.ground }
    private var accentColor: Color { toneMono(edition.accent) }
    private var casingColor: Color? { edition.casing.map(toneMono) }

    /// Type colour that stays legible on a user-chosen ground: an explicit text pick always
    /// wins; otherwise, when the ground is overridden, derive ink/subtle from its luminance.
    private var autoInk: Color { groundColor.isDarkGround ? Theme.Palette.bone : Theme.Palette.ink }
    private var inkColor: Color {
        if let textOverride { return toneMono(textOverride) }
        return groundOverride != nil ? autoInk : edition.ink
    }
    private var subtleColor: Color {
        if let textOverride { return toneMono(textOverride).opacity(0.6) }
        return groundOverride != nil ? autoInk.opacity(0.6) : edition.subtle
    }

    private var artDimensions: CGSize { Self.artSize(orientation, dataPlacement) }
    /// Landscape with the data column beside the art (vs. above/below it).
    private var isSideLayout: Bool { orientation == .landscape && dataPlacement.isSide }

    /// The elevation strip only fits under the art in portrait.
    private var hasElevationStrip: Bool {
        showElevationProfile && elevationSamples.count > 1 && orientation == .portrait
    }

    var body: some View {
        Group {
            if layout == .gallery {
                galleryComposition
            } else if layout == .keepsake {
                keepsakeComposition
            } else if isSideLayout {
                HStack(spacing: 0) {
                    if dataPlacement == .left {
                        footer
                        art
                    } else {
                        art
                        footer
                    }
                }
            } else if orientation == .landscape && dataPlacement == .top {
                VStack(spacing: 0) {
                    footer
                    art
                }
            } else {
                // Portrait (and landscape-with-bottom-data): a fixed print-shaped canvas. The
                // footer takes its natural height; the art absorbs the rest. `fixedSize` pins the
                // band and footer at that natural height — without it the fixed-height canvas
                // negotiates the shortfall out of the *footer* (its scale-to-fit texts read as
                // compressible), clipping the stat row and date off the bottom of the artwork
                // while the art panel keeps more than its share.
                VStack(spacing: 0) {
                    flexArt
                    if hasElevationStrip { elevationBand.fixedSize(horizontal: false, vertical: true) }
                    footer.fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: Self.canvasSize(orientation, dataPlacement, printAspect).width,
                       height: Self.canvasSize(orientation, dataPlacement, printAspect).height)
            }
        }
        .background(groundColor)
    }

    // MARK: Gallery layout — a curated row of photo / map tiles under a serif masthead.

    private enum GalleryTile { case photo(Int), map, route, elevation }

    /// The tiles shown. A user-set cell plan (`galleryCellsRaw`) wins — photo tiles draw the run's
    /// photos in order. With no plan, fall back to the old default: an optional map tile then photos.
    private var galleryTiles: [GalleryTile] {
        if !galleryCellsRaw.isEmpty {
            var photoIndex = 0
            var tiles: [GalleryTile] = []
            for raw in galleryCellsRaw {
                switch GalleryTileKind(rawValue: raw) {
                case .photo: tiles.append(.photo(photoIndex)); photoIndex += 1
                case .map: tiles.append(.map)
                case .route: tiles.append(.route)
                case .elevation: tiles.append(.elevation)
                case .none: break
                }
            }
            return tiles.isEmpty ? [.map] : tiles
        }
        var tiles: [GalleryTile] = []
        if galleryShowMapTile { tiles.append(.map) }
        let maxPhotos = galleryShowMapTile ? 2 : 3
        for i in 0..<min(photoImages.count, maxPhotos) { tiles.append(.photo(i)) }
        if tiles.isEmpty { tiles = [.map] }
        return tiles
    }

    private var galleryDesign: GalleryDesign { GalleryDesign(rawValue: galleryDesignRaw) ?? .portfolio }
    /// Gallery follows the chosen orientation: a tall portrait sheet, or a wide landscape one.
    private var galleryWidth: CGFloat { orientation == .portrait ? Self.width : Self.wideArtWidth }
    private var galleryArtHeight: CGFloat { orientation == .portrait ? 620 : 460 }

    private var galleryComposition: some View {
        VStack(spacing: 40) {
            galleryFramesView
                .frame(height: galleryArtHeight)

            galleryMasthead

            if !resolvedStats.isEmpty { galleryStatRow }

            if showElevationProfile && elevationSamples.count > 1 {
                elevationProfileContent
            }
        }
        .padding(80)
        .frame(width: galleryWidth)
        .background(groundColor)
    }

    /// A frame at index `i`, clamped so a design never reads past the resolved tile plan.
    @ViewBuilder private func galleryFrame(_ i: Int, _ tiles: [GalleryTile]) -> some View {
        galleryTileView(i < tiles.count ? tiles[i] : .map)
    }

    /// The five curated arrangements — one hero, two side-by-side, three across, a 2×2 grid, or a
    /// feature frame over a strip of three.
    @ViewBuilder private var galleryFramesView: some View {
        let tiles = galleryTiles
        let g: CGFloat = 16
        switch galleryDesign {
        case .portfolio:
            galleryFrame(0, tiles)
        case .duo:
            HStack(spacing: g) { galleryFrame(0, tiles); galleryFrame(1, tiles) }
        case .triptych:
            HStack(spacing: g) { galleryFrame(0, tiles); galleryFrame(1, tiles); galleryFrame(2, tiles) }
        case .grid:
            VStack(spacing: g) {
                HStack(spacing: g) { galleryFrame(0, tiles); galleryFrame(1, tiles) }
                HStack(spacing: g) { galleryFrame(2, tiles); galleryFrame(3, tiles) }
            }
        case .feature:
            VStack(spacing: g) {
                galleryFrame(0, tiles).frame(maxHeight: .infinity)
                HStack(spacing: g) { galleryFrame(1, tiles); galleryFrame(2, tiles); galleryFrame(3, tiles) }
                    .frame(height: galleryArtHeight * 0.32)
            }
        }
    }

    /// Title + location beneath the frames, in the chosen face.
    @ViewBuilder private var galleryMasthead: some View {
        VStack(spacing: 14) {
            if showTitle {
                Text(titleText.uppercased())
                    .font(.system(size: ts(44), weight: titleFont.titleWeight, design: titleFont.design))
                    .tracking(8 + titleFont.extraTracking)
                    .foregroundStyle(inkColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
            }
            if !placeLine.isEmpty {
                Text(placeLine.uppercased())
                    .font(.system(size: ts(18), weight: .regular, design: titleFont.design))
                    .tracking(5)
                    .foregroundStyle(subtleColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A compact centred row of the chosen data slots, under the masthead.
    private var galleryStatRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(resolvedStats.enumerated()), id: \.offset) { index, item in
                if statDividerShown(resolvedStats, index) { statDivider }
                stat(item.metric, item.value)
            }
        }
        .frame(maxWidth: 680)
    }

    @ViewBuilder private func galleryTileView(_ tile: GalleryTile) -> some View {
        Group {
            switch tile {
            case .photo(let i):
                if i < photoImages.count {
                    Image(uiImage: photoImages[i]).resizable().scaledToFill()
                } else {
                    groundColor
                }
            case .map:
                if edition.usesImagePanel, let panelImage {
                    Image(uiImage: panelImage).resizable().scaledToFill()
                } else {
                    ZStack {
                        groundColor
                        if run.coordinates.count > 1 { routeArt.padding(24) }
                    }
                }
            case .route:
                ZStack {
                    groundColor
                    if run.coordinates.count > 1 { routeArt.padding(24) }
                }
            case .elevation:
                ZStack {
                    groundColor
                    if elevationSamples.count > 1 {
                        ElevationLineShape(samples: elevationSamples)
                            .stroke(subtleColor,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            .padding(24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(.rect(cornerRadius: 6))
    }

    // MARK: Keepsake layout — a full-bleed photo with the data overlaid in white, thin frame.

    private var coordsText: String {
        guard let lat = run.startLatitude, let lon = run.startLongitude else { return "" }
        return String(format: "%.4f° %@ · %.4f° %@",
                      abs(lat), lat >= 0 ? "N" : "S", abs(lon), lon >= 0 ? "E" : "W")
    }

    private var keepsakeComposition: some View {
        ZStack {
            if let photo = photoImages.first {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                groundColor
            }
            LinearGradient(colors: [.black.opacity(0.4), .black.opacity(0.06), .black.opacity(0.52)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(dateLine.uppercased())
                        .font(.system(size: ts(15), weight: .semibold)).tracking(3)
                    Spacer()
                    if !coordsText.isEmpty {
                        Text(coordsText).font(.system(size: ts(15), weight: .semibold)).tracking(2)
                    }
                }
                .foregroundStyle(.white.opacity(0.9))

                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(titleText.uppercased())
                            .font(.system(size: ts(60), weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2).minimumScaleFactor(0.5)
                        if !placeLine.isEmpty {
                            Text(placeLine.uppercased())
                                .font(.system(size: ts(16), weight: .semibold)).tracking(4)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 28)

                Spacer(minLength: 0)

                VStack(spacing: 18) {
                    Rectangle().fill(.white.opacity(0.6)).frame(height: 1)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(fourStats.enumerated()), id: \.offset) { index, item in
                            if statDividerShown(fourStats, index) {
                                Rectangle().fill(.white.opacity(0.4)).frame(width: 1, height: 40)
                            }
                            keepsakeStat(item.metric, item.value)
                        }
                    }
                }
            }
            .padding(64)

            Rectangle().stroke(.white.opacity(0.85), lineWidth: 2).padding(44)
        }
        .frame(width: Self.width, height: Self.width * 1.25)
        .clipped()
    }

    @ViewBuilder
    private func keepsakeStat(_ metric: StatMetric, _ value: String) -> some View {
        if metric == .none {
            Color.clear.frame(maxWidth: .infinity)   // blank column
        } else {
            VStack(spacing: 6) {
                Image(systemName: metric.icon).font(.system(size: ts(15), weight: .semibold))
                Text(value).font(.system(size: ts(26), weight: .bold)).minimumScaleFactor(0.5).lineLimit(1)
                Text(metric.label).font(.system(size: ts(12), weight: .semibold)).tracking(1.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        }
    }

    /// Whole distance units (miles/km) for the profile's markers.
    private var distanceUnitCount: Int { max(0, Int(Format.distanceValue(run.distance))) }

    /// The elevation profile as chrome-less content (label + gradient fill + ridge line + baseline
    /// + mile/km ticks). Fills its container's width, so it works in the portrait band and inside
    /// a landscape footer column alike.
    private var elevationProfileContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ELEVATION  ·  \(UnitSystem.current.label.uppercased())")
                .font(.system(size: ts(15), weight: .semibold))
                .tracking(3)
                .foregroundStyle(subtleColor)

            ZStack {
                ElevationProfileShape(samples: elevationSamples)
                    .fill(LinearGradient(colors: [subtleColor.opacity(0.38), subtleColor.opacity(0.05)],
                                         startPoint: .top, endPoint: .bottom))
                ElevationLineShape(samples: elevationSamples)
                    .stroke(subtleColor.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    // Baseline.
                    Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)) }
                        .stroke(subtleColor.opacity(0.35), lineWidth: 1.5)
                    // Mile / km ticks.
                    if distanceUnitCount >= 2 && distanceUnitCount <= 60 {
                        ForEach(Array(1..<distanceUnitCount), id: \.self) { i in
                            let x = CGFloat(i) / CGFloat(distanceUnitCount) * w
                            Path { p in p.move(to: CGPoint(x: x, y: h)); p.addLine(to: CGPoint(x: x, y: h - (i % 5 == 0 ? 16 : 9))) }
                                .stroke(subtleColor.opacity(0.5), lineWidth: 1.5)
                        }
                    }
                }
            }
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity)
    }

    /// Portrait band, sitting between the art and the footer.
    private var elevationBand: some View {
        elevationProfileContent
            .padding(.horizontal, 70)
            .padding(.top, 26)
            .padding(.bottom, 10)
            .frame(width: Self.width)
            .background(groundColor)
    }

    /// Whether to show the profile inside the footer (landscape, where there's no room between
    /// the art and the footer for a band).
    private var footerElevation: Bool {
        showElevationProfile && elevationSamples.count > 1 && orientation == .landscape
    }

    // MARK: Art panel

    /// The art panel at its authored size — used by the landscape and side-data layouts, whose
    /// geometry is unchanged.
    private var art: some View {
        artBody
            .frame(width: artDimensions.width, height: artDimensions.height)
            .clipped()
    }

    /// The art panel with a flexible height, for the fixed-aspect portrait canvas: the footer takes
    /// the height it needs and the art absorbs everything left over, so the finished piece lands on
    /// an exact print ratio no matter how much metadata the user turned on. Previously the canvas
    /// height was art + a dynamic footer, which produced a 1:1.62 poster that matched no print size
    /// on sale.
    private var flexArt: some View {
        artBody
            .frame(width: artDimensions.width)
            .frame(maxHeight: .infinity)
            .clipped()
    }

    private var artBody: some View {
        ZStack {
            groundColor
            if edition.isPhoto {
                // Memory: the photograph is the art. In portrait the route (when on) moves into
                // the footer; in landscape it stays etched over the photo.
                photoPanel
                if memoryRoutePhoto {
                    LinearGradient(colors: [.black.opacity(0.28), .clear, .black.opacity(0.32)],
                                   startPoint: .top, endPoint: .bottom)
                    routeArt.padding(120)
                }
            } else if edition.usesImagePanel, let panelImage {
                Image(uiImage: panelImage).resizable().scaledToFill()
            } else if run.coordinates.count > 1 {
                routeArt.padding(130)
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: ts(130), weight: .semibold))
                    .foregroundStyle(subtleColor)
            }
        }
    }

    // MARK: Photo panel (Memory)

    /// Arranges the run's photos into a hero-driven editorial grid: the cover (first) photo leads
    /// with the largest tile, the rest fill a column beside or below it. 4 photos use a 2×2. Tiles
    /// are sized exactly so the gaps (edition ground) read as a considered matte.
    @ViewBuilder private var photoPanel: some View {
        let photos = photoLayout == .single ? Array(photoImages.prefix(1))
                                            : Array(photoImages.prefix(4))
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, g = gridGap
            let heroW = (w - g) * 0.62, sideW = (w - g) * 0.38
            if photos.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: ts(120), weight: .semibold))
                    .foregroundStyle(subtleColor)
                    .frame(width: w, height: h)
            } else if photos.count == 1 {
                photoTile(photos[0], width: w, height: h)
            } else if photos.count == 2 {
                HStack(spacing: g) {
                    photoTile(photos[0], width: heroW, height: h)
                    photoTile(photos[1], width: sideW, height: h)
                }
            } else if photos.count == 3 {
                HStack(spacing: g) {
                    photoTile(photos[0], width: heroW, height: h)
                    VStack(spacing: g) {
                        photoTile(photos[1], width: sideW, height: (h - g) / 2)
                        photoTile(photos[2], width: sideW, height: (h - g) / 2)
                    }
                }
            } else {
                let cw = (w - g) / 2, ch = (h - g) / 2
                VStack(spacing: g) {
                    HStack(spacing: g) { photoTile(photos[0], width: cw, height: ch); photoTile(photos[1], width: cw, height: ch) }
                    HStack(spacing: g) { photoTile(photos[2], width: cw, height: ch); photoTile(photos[3], width: cw, height: ch) }
                }
            }
        }
    }

    private var gridGap: CGFloat { 12 }

    private func photoTile(_ image: UIImage, width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: max(width, 1), height: max(height, 1))
            .clipped()
    }

    private var memoryRouteEnabled: Bool { edition.isPhoto && showMemoryRoute && run.coordinates.count > 1 }
    /// Portrait: the route moves into the footer/data area.
    private var memoryRouteInFooter: Bool { memoryRouteEnabled && orientation == .portrait }
    /// Landscape: the route stays etched over the photo.
    private var memoryRoutePhoto: Bool { memoryRouteEnabled && orientation == .landscape }

    private var routeArt: some View { routeGraphic(width: edition.routeWidth) }

    /// The route as vector art (optional casing under the coloured line), at a given stroke width.
    private func routeGraphic(width: CGFloat) -> some View {
        ZStack {
            if let casing = casingColor {
                RouteShape(coordinates: run.coordinates)
                    .stroke(casing.opacity(0.9), style: stroke(width * 1.7))
            }
            RouteShape(coordinates: run.coordinates)
                .stroke(routeColor, style: stroke(width))
        }
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    // MARK: Footer — arranged by layout

    private var footer: some View {
        VStack(spacing: 22) {
            Group {
                if memoryRouteInFooter && layout != .editorial {
                    // Route takes the hero slot; the four metrics run across beneath it.
                    memoryRouteFooter
                } else if layout == .classic {
                    // Map product: the layout beneath the map is chosen by mapLayout.
                    switch MapLayout(rawValue: mapLayoutRaw) ?? .statement {
                    case .statement: classicFooter
                    case .minimal:   mapMinimalFooter
                    case .photo:     mapPhotoFooter
                    }
                } else {
                    switch layout {
                    case .classic: classicFooter
                    case .minimal: minimalFooter
                    case .editorial: editorialFooter
                    case .grid: gridFooter
                    // Gallery & Keepsake render their own full compositions (never this footer).
                    case .gallery, .keepsake: classicFooter
                    }
                }
            }
            if footerElevation { elevationProfileContent }
        }
        .padding(70)
        .frame(width: isSideLayout ? Self.landscapeFooterWidth : artDimensions.width,
               height: isSideLayout ? artDimensions.height : nil)
        .background(groundColor)
    }

    /// Centred, full: title, big distance, place, sparse stat row, date.
    private var classicFooter: some View {
        VStack(spacing: 20) {
            title(leading: false)
            heroBlock(leading: false)
            if !placeLine.isEmpty { metaLine([placeLine], leading: false) }
            if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: false) }
            if !resolvedStats.isEmpty {
                Rectangle().fill(subtleColor.opacity(0.4)).frame(width: 90, height: 2).padding(.vertical, 6)
                statRow
            }
            if !dateLine.isEmpty { metaLine([dateLine], leading: false).padding(.top, 6) }
        }
    }

    /// The most restrained: just the statement and one quiet caption line.
    private var minimalFooter: some View {
        VStack(spacing: 16) {
            title(leading: false)
            heroBlock(leading: false)
            metaLine([placeLine, dateLine], leading: false)
        }
    }

    /// Map "Minimal": the quietest map poster — just the title and the date beneath the map.
    private var mapMinimalFooter: some View {
        VStack(spacing: 12) {
            title(leading: false)
            if !dateLine.isEmpty { metaLine([dateLine], leading: false) }
        }
    }

    /// Map "Photo": a strip of 1–3 photos fills the data area, over the title and a place · date line.
    private var mapPhotoFooter: some View {
        VStack(spacing: 22) {
            title(leading: false)
            mapPhotoStrip
            if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: false) }
            metaLine([placeLine, dateLine], leading: false).padding(.top, 2)
        }
    }

    /// The photo strip for the map Photo layout — equal-width tiles, or a placeholder if the run
    /// has no photos yet (the editor offers an Add Photo action to fill it).
    @ViewBuilder private var mapPhotoStrip: some View {
        let n = max(1, min(3, mapPhotoCount))
        let photos = Array(photoImages.prefix(n))
        if photos.isEmpty {
            RoundedRectangle(cornerRadius: 14)
                .fill(subtleColor.opacity(0.12))
                .frame(height: 360)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: ts(88), weight: .semibold))
                        .foregroundStyle(subtleColor)
                )
        } else if photos.count == 1 {
            // A single photo shows whole — fitted, not centre-cropped, which was cutting heads
            // off portrait shots. The band height caps a tall photo; the ground breathes around
            // whatever width the photo's own aspect gives it.
            Image(uiImage: photos[0])
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: 430)
        } else {
            HStack(spacing: 14) {
                ForEach(photos.indices, id: \.self) { i in
                    Image(uiImage: photos[i])
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .clipped()
                        .clipShape(.rect(cornerRadius: 14))
                }
            }
        }
    }

    /// Left-aligned, gallery-label feel: title, distance, a compact stat line, place · date.
    /// Optionally sets the cover photo in the open space beside the text.
    private var editorialFooter: some View {
        HStack(alignment: .center, spacing: 44) {
            VStack(alignment: .leading, spacing: 18) {
                title(leading: true)
                heroBlock(leading: true)
                HStack(spacing: 28) {
                    ForEach(Array(resolvedStats.enumerated()), id: \.offset) { _, item in
                        editorialStat(item.metric, item.value)
                    }
                }
                if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: true) }
                metaLine([placeLine, dateLine], leading: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The open space holds the route (Memory route option) or the cover photo.
            if memoryRouteInFooter {
                routeGraphic(width: 7)
                    .frame(width: 320, height: 380)
            } else if showEditorialPhoto, let photo = photoImages.first {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 300, height: 380)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    /// Memory with the route option, non-editorial layouts: the route sits where the big headline
    /// would, and the four metrics run across beneath it.
    private var memoryRouteFooter: some View {
        VStack(spacing: 20) {
            title(leading: false)
            routeGraphic(width: 8)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(.vertical, 4)
            if !placeLine.isEmpty { metaLine([placeLine], leading: false) }
            Rectangle().fill(subtleColor.opacity(0.4)).frame(width: 90, height: 2).padding(.vertical, 4)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(fourStats.enumerated()), id: \.offset) { index, item in
                    if statDividerShown(fourStats, index) { statDivider }
                    gridStat(item.metric, item.value)
                }
            }
            if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: false) }
            if !dateLine.isEmpty { metaLine([dateLine], leading: false).padding(.top, 4) }
        }
    }

    /// Four equal stats across — no big headline. The chosen Headline metric leads, followed by
    /// the three slot metrics.
    private var gridFooter: some View {
        VStack(spacing: 18) {
            title(leading: false)
            if !placeLine.isEmpty { metaLine([placeLine], leading: false) }
            Rectangle().fill(subtleColor.opacity(0.4)).frame(width: 90, height: 2).padding(.vertical, 4)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(fourStats.enumerated()), id: \.offset) { index, item in
                    if statDividerShown(fourStats, index) { statDivider }
                    gridStat(item.metric, item.value)
                }
            }
            if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: false) }
            if !dateLine.isEmpty { metaLine([dateLine], leading: false).padding(.top, 4) }
        }
    }

    /// The Headline metric plus the three slot metrics, for the 4-Up layout.
    private var fourStats: [(metric: StatMetric, value: String)] {
        [(metric: heroMetric, value: metricValue(heroMetric) ?? "—")] + resolvedStats
    }

    /// Whether to draw a divider before the column at `index` in a stat row: only between two real
    /// (non-blank) columns, so a blank `.none` slot reads as genuine empty space rather than an
    /// empty box hemmed in by dividers.
    private func statDividerShown(_ items: [(metric: StatMetric, value: String)], _ index: Int) -> Bool {
        index > 0 && items[index].metric != .none && items[index - 1].metric != .none
    }

    /// Resolves a metric's value, sourcing start elevation from the fetched terrain profile.
    private func metricValue(_ metric: StatMetric) -> String? {
        if metric == .startElevation {
            guard let start = elevationSamples.first else { return nil }
            return Format.elevation(start)
        }
        return metric.value(for: run)
    }

    @ViewBuilder
    private func gridStat(_ metric: StatMetric, _ value: String) -> some View {
        if metric == .none {
            Color.clear.frame(maxWidth: .infinity)   // blank column, keeps its share of the row
        } else {
            VStack(spacing: 6) {
                Image(systemName: metric.icon)
                    .font(.system(size: ts(15), weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(value)
                    .font(.system(size: ts(26), weight: .bold))
                    .foregroundStyle(inkColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(metric.label)
                    .font(.system(size: ts(13), weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(subtleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Footer pieces

    /// The title/date shown, honouring user overrides (empty falls back to the run's values).
    private var titleText: String {
        if let titleOverride, !titleOverride.isEmpty { return titleOverride }
        return run.name
    }
    private var dateText: String {
        if let dateOverride, !dateOverride.isEmpty { return dateOverride }
        return Format.date(run.startDate)
    }
    /// The date as it appears on the poster — empty when toggled off, so every layout that folds
    /// it into a meta line drops it the same way `placeLine` drops a hidden location.
    private var dateLine: String { showDate ? dateText : "" }

    @ViewBuilder
    private func title(leading: Bool) -> some View {
        if showTitle {
            Text(titleText.uppercased())
                .font(.system(size: ts(26), weight: titleFont.titleWeight, design: titleFont.design))
                .tracking(4 + titleFont.extraTracking)
                .foregroundStyle(subtleColor)
                .lineLimit(2)
                .multilineTextAlignment(leading ? .leading : .center)
                .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
        }
    }

    private func heroBlock(leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: 6) {
            Text(heroValue)
                .font(.system(size: ts(150), weight: .bold))
                .tracking(-2)
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(heroCaption)
                .font(.system(size: ts(24), weight: .semibold))
                .tracking(8)
                .foregroundStyle(accentColor)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    /// The headline value. None leaves it blank; Distance keeps the signature bare number ("26.22");
    /// any other chosen metric shows its full formatted value.
    private var heroValue: String {
        if heroMetric == .none { return "" }
        return heroMetric == .distance ? heroNumber : (metricValue(heroMetric) ?? "—")
    }

    /// The caption beneath the headline. None leaves it blank; Distance shows the unit; others show
    /// the metric's label.
    private var heroCaption: String {
        if heroMetric == .none { return "" }
        return heroMetric == .distance ? UnitSystem.current.label.uppercased() : heroMetric.label
    }

    /// The slot metrics resolved to (metric, value) for this run, unavailable ones showing "—".
    /// Carrying the metric lets the data-rich layouts pin its icon beside the value.
    private var resolvedStats: [(metric: StatMetric, value: String)] {
        statSlots.map { (metric: $0, value: metricValue($0) ?? "—") }
    }

    private var statRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(resolvedStats.enumerated()), id: \.offset) { index, item in
                if statDividerShown(resolvedStats, index) { statDivider }
                stat(item.metric, item.value)
            }
        }
    }

    @ViewBuilder
    private func stat(_ metric: StatMetric, _ value: String) -> some View {
        if metric == .none {
            Color.clear.frame(maxWidth: .infinity)   // blank column
        } else {
            VStack(spacing: 8) {
                Text(value)
                    .font(.system(size: ts(32), weight: .bold))
                    .foregroundStyle(inkColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(metric.label)
                    .font(.system(size: ts(15), weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(subtleColor)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func editorialStat(_ metric: StatMetric, _ value: String) -> some View {
        if metric == .none {
            Color.clear.frame(width: ts(52), height: 1)   // a blank gap in the left-aligned row
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: metric.icon)
                        .font(.system(size: ts(13), weight: .semibold))
                        .foregroundStyle(accentColor)
                    Text(value)
                        .font(.system(size: ts(30), weight: .bold))
                        .foregroundStyle(inkColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(metric.label)
                    .font(.system(size: ts(14), weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(subtleColor)
            }
        }
    }

    private var statDivider: some View {
        Rectangle().fill(subtleColor.opacity(0.35)).frame(width: 1, height: 42)
    }

    private func weatherText(_ weather: String, leading: Bool) -> some View {
        Text(weather.uppercased())
            .font(.system(size: ts(19), weight: .medium))
            .tracking(4)
            .foregroundStyle(subtleColor)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    /// A wide-tracked uppercase caption from the non-empty parts, joined by "·".
    private func metaLine(_ parts: [String], leading: Bool) -> some View {
        let text = parts.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        return Text(text.uppercased())
            .font(.system(size: ts(19), weight: .semibold))
            .tracking(3)
            .foregroundStyle(subtleColor)
            .multilineTextAlignment(leading ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    // MARK: Content

    private var heroNumber: String {
        Format.distanceValue(run.distance).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var placeLine: String {
        guard showLocation else { return "" }
        if let locationOverride, !locationOverride.isEmpty { return locationOverride }
        return [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A filled area silhouette of an elevation series, drawn left→right and baselined at the bottom
/// of its rect. Values are normalized within their own min/max so any run fills the band.
struct ElevationProfileShape: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 0
        let span = max(maxV - minV, 1)

        func point(_ i: Int) -> CGPoint {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(samples.count - 1)
            let norm = (samples[i] - minV) / span
            // Keep a little headroom so the peak doesn't touch the top edge.
            let y = rect.maxY - CGFloat(norm) * rect.height * 0.88 - rect.height * 0.06
            return CGPoint(x: x, y: y)
        }

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in samples.indices { path.addLine(to: point(i)) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The ridge line of an elevation series — the open top edge, matching `ElevationProfileShape`'s
/// geometry so a stroke sits exactly atop its fill.
struct ElevationLineShape: Shape {
    let samples: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else { return path }
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 0
        let span = max(maxV - minV, 1)

        func point(_ i: Int) -> CGPoint {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(samples.count - 1)
            let norm = (samples[i] - minV) / span
            let y = rect.maxY - CGFloat(norm) * rect.height * 0.88 - rect.height * 0.06
            return CGPoint(x: x, y: y)
        }

        path.move(to: point(0))
        for i in samples.indices.dropFirst() { path.addLine(to: point(i)) }
        return path
    }
}
