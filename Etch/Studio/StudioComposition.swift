import SwiftUI

/// How the run's data is arranged beneath the art — chosen independently of the edition.
enum StudioLayout: String, CaseIterable, Identifiable {
    case classic, minimal, editorial, grid
    var id: String { rawValue }
    var name: String {
        switch self {
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        case .editorial: return "Editorial"
        case .grid: return "4-Up"
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

/// Where the run data sits relative to the art in landscape. Ignored in portrait (always bottom).
enum StudioDataPlacement: String, CaseIterable, Identifiable {
    case side, bottom
    var id: String { rawValue }
    var name: String { self == .side ? "Data Side" : "Data Bottom" }
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
    var dataPlacement: StudioDataPlacement = .side
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
    /// User overrides; nil falls back to the edition's palette.
    var routeOverride: Color? = nil
    var textOverride: Color? = nil
    var groundOverride: Color? = nil

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    /// Footer column width in landscape when the data sits beside the art.
    static let landscapeFooterWidth: CGFloat = 640
    /// Wide art size when landscape sets the data across the bottom.
    static let wideArtWidth: CGFloat = 1640
    static let wideArtHeight: CGFloat = 920

    /// The art panel's pixel size for an orientation + placement.
    static func artSize(_ orientation: StudioOrientation, _ placement: StudioDataPlacement) -> CGSize {
        (orientation == .landscape && placement == .bottom)
            ? CGSize(width: wideArtWidth, height: wideArtHeight)
            : CGSize(width: width, height: artHeight)
    }

    /// Nominal poster size — used for print-scale math and preview aspect ratios. The rendered
    /// footer height is dynamic; the constants below are the across-the-bottom allowances.
    static func nominalSize(_ orientation: StudioOrientation, _ placement: StudioDataPlacement) -> CGSize {
        switch (orientation, placement) {
        case (.portrait, _):          return CGSize(width: width, height: artHeight + 620)
        case (.landscape, .side):     return CGSize(width: width + landscapeFooterWidth, height: artHeight)
        case (.landscape, .bottom):   return CGSize(width: wideArtWidth, height: wideArtHeight + 540)
        }
    }

    private var routeColor: Color { routeOverride ?? edition.route }
    private var groundColor: Color { groundOverride ?? edition.ground }

    /// Type colour that stays legible on a user-chosen ground: an explicit text pick always
    /// wins; otherwise, when the ground is overridden, derive ink/subtle from its luminance.
    private var autoInk: Color { groundColor.isDarkGround ? Theme.Palette.bone : Theme.Palette.ink }
    private var inkColor: Color {
        if let textOverride { return textOverride }
        return groundOverride != nil ? autoInk : edition.ink
    }
    private var subtleColor: Color {
        if let textOverride { return textOverride.opacity(0.6) }
        return groundOverride != nil ? autoInk.opacity(0.6) : edition.subtle
    }

    private var artDimensions: CGSize { Self.artSize(orientation, dataPlacement) }
    /// Landscape with the data column beside the art (vs. above/below it).
    private var isSideLayout: Bool { orientation == .landscape && dataPlacement == .side }

    /// The elevation strip only fits under the art in portrait.
    private var hasElevationStrip: Bool {
        showElevationProfile && elevationSamples.count > 1 && orientation == .portrait
    }

    var body: some View {
        Group {
            if isSideLayout {
                HStack(spacing: 0) {
                    art
                    footer
                }
            } else {
                VStack(spacing: 0) {
                    art
                    if hasElevationStrip { elevationBand }
                    footer
                }
            }
        }
        .background(groundColor)
    }

    /// Whole distance units (miles/km) for the profile's markers.
    private var distanceUnitCount: Int { max(0, Int(Format.distanceValue(run.distance))) }

    /// An integrated elevation band: a labelled, gradient-filled profile with a crisp ridge line,
    /// a baseline, and mile/km tick markers — styled to match the footer rather than sit apart.
    private var elevationBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ELEVATION  ·  \(UnitSystem.current.label.uppercased())")
                .font(.system(size: 15, weight: .semibold))
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
        .padding(.horizontal, 70)
        .padding(.top, 26)
        .padding(.bottom, 10)
        .frame(width: Self.width)
        .background(groundColor)
    }

    // MARK: Art panel

    private var art: some View {
        ZStack {
            groundColor
            if edition.isPhoto {
                // Memory: the photograph is the art — a single cover photo or a tasteful grid.
                // The route is off by default, and can be etched over the photo on request.
                photoPanel
                if showMemoryRoute, run.coordinates.count > 1 {
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
                    .font(.system(size: 130, weight: .semibold))
                    .foregroundStyle(subtleColor)
            }
        }
        .frame(width: artDimensions.width, height: artDimensions.height)
        .clipped()
    }

    // MARK: Photo panel (Memory)

    /// Arranges the run's photos: a single filling image, or a magazine grid (2 = diptych,
    /// 3 = one over two, 4 = 2×2). Gaps show the edition ground so the grid reads as a set.
    @ViewBuilder private var photoPanel: some View {
        let photos = photoLayout == .single ? Array(photoImages.prefix(1))
                                            : Array(photoImages.prefix(4))
        if photos.isEmpty {
            Image(systemName: "photo")
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(subtleColor)
        } else if photos.count == 1 {
            photoCell(photos[0])
        } else if photos.count == 2 {
            HStack(spacing: gridGap) { photoCell(photos[0]); photoCell(photos[1]) }
        } else if photos.count == 3 {
            VStack(spacing: gridGap) {
                photoCell(photos[0])
                HStack(spacing: gridGap) { photoCell(photos[1]); photoCell(photos[2]) }
            }
        } else {
            VStack(spacing: gridGap) {
                HStack(spacing: gridGap) { photoCell(photos[0]); photoCell(photos[1]) }
                HStack(spacing: gridGap) { photoCell(photos[2]); photoCell(photos[3]) }
            }
        }
    }

    private var gridGap: CGFloat { 12 }

    private func photoCell(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
    }

    private var routeArt: some View {
        ZStack {
            if let casing = edition.casing {
                RouteShape(coordinates: run.coordinates)
                    .stroke(casing.opacity(0.9), style: stroke(edition.routeWidth * 1.7))
            }
            RouteShape(coordinates: run.coordinates)
                .stroke(routeColor, style: stroke(edition.routeWidth))
        }
    }

    private func stroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    // MARK: Footer — arranged by layout

    private var footer: some View {
        Group {
            switch layout {
            case .classic: classicFooter
            case .minimal: minimalFooter
            case .editorial: editorialFooter
            case .grid: gridFooter
            }
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
            Rectangle().fill(subtleColor.opacity(0.4)).frame(width: 90, height: 2).padding(.vertical, 6)
            statRow
            metaLine([dateText], leading: false).padding(.top, 6)
        }
    }

    /// The most restrained: just the statement and one quiet caption line.
    private var minimalFooter: some View {
        VStack(spacing: 16) {
            title(leading: false)
            heroBlock(leading: false)
            metaLine([placeLine, dateText], leading: false)
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
                        editorialStat(item.label, item.value)
                    }
                }
                if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: true) }
                metaLine([placeLine, dateText], leading: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showEditorialPhoto, let photo = photoImages.first {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 300, height: 380)
                    .clipShape(.rect(cornerRadius: 12))
            }
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
                    if index > 0 { statDivider }
                    gridStat(item.label, item.value)
                }
            }
            if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: false) }
            metaLine([dateText], leading: false).padding(.top, 4)
        }
    }

    /// The Headline metric plus the three slot metrics, for the 4-Up layout.
    private var fourStats: [(label: String, value: String)] {
        [(label: heroMetric.label, value: heroMetric.value(for: run) ?? "—")] + resolvedStats
    }

    private func gridStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(inkColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(subtleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
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

    private func title(leading: Bool) -> some View {
        Text(titleText.uppercased())
            .font(.system(size: 26, weight: .semibold))
            .tracking(4)
            .foregroundStyle(subtleColor)
            .lineLimit(2)
            .multilineTextAlignment(leading ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    private func heroBlock(leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: 6) {
            Text(heroValue)
                .font(.system(size: 150, weight: .bold))
                .tracking(-2)
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(heroCaption)
                .font(.system(size: 24, weight: .semibold))
                .tracking(8)
                .foregroundStyle(edition.accent)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    /// The headline value. Distance keeps the signature bare number ("26.22"); any other chosen
    /// metric shows its full formatted value.
    private var heroValue: String {
        heroMetric == .distance ? heroNumber : (heroMetric.value(for: run) ?? "—")
    }

    /// The caption beneath the headline. Distance shows the unit; others show the metric's label.
    private var heroCaption: String {
        heroMetric == .distance ? UnitSystem.current.label.uppercased() : heroMetric.label
    }

    /// The slot metrics resolved to (label, value) for this run, unavailable ones showing "—".
    private var resolvedStats: [(label: String, value: String)] {
        statSlots.map { (label: $0.label, value: $0.value(for: run) ?? "—") }
    }

    private var statRow: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(resolvedStats.enumerated()), id: \.offset) { index, item in
                if index > 0 { statDivider }
                stat(item.label, item.value)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(inkColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(subtleColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func editorialStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .tracking(2)
                .foregroundStyle(subtleColor)
        }
    }

    private var statDivider: some View {
        Rectangle().fill(subtleColor.opacity(0.35)).frame(width: 1, height: 42)
    }

    private func weatherText(_ weather: String, leading: Bool) -> some View {
        Text(weather.uppercased())
            .font(.system(size: 19, weight: .medium))
            .tracking(4)
            .foregroundStyle(subtleColor)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    /// A wide-tracked uppercase caption from the non-empty parts, joined by "·".
    private func metaLine(_ parts: [String], leading: Bool) -> some View {
        let text = parts.filter { !$0.isEmpty }.joined(separator: "  ·  ")
        return Text(text.uppercased())
            .font(.system(size: 19, weight: .semibold))
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
        [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
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
