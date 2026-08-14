import SwiftUI

/// How the run's data is arranged beneath the art — chosen independently of the edition.
enum StudioLayout: String, CaseIterable, Identifiable {
    case classic, minimal, editorial
    var id: String { rawValue }
    var name: String {
        switch self {
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        case .editorial: return "Editorial"
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
    var photoLayout: StudioPhotoLayout = .single
    /// User overrides; nil falls back to the edition's palette.
    var routeOverride: Color? = nil
    var textOverride: Color? = nil
    var groundOverride: Color? = nil

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    static var size: CGSize { CGSize(width: width, height: artHeight + 620) }

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

    var body: some View {
        VStack(spacing: 0) {
            art
            footer
        }
        .frame(width: Self.width)
        .background(groundColor)
    }

    // MARK: Art panel

    private var art: some View {
        ZStack {
            groundColor
            if edition.isPhoto {
                // Memory: the photograph is the art. No route overlaid — a single cover photo or
                // a tasteful grid, arranged clean; the run's data lives in the footer.
                photoPanel
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
        .frame(width: Self.width, height: Self.artHeight)
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

    private var gridGap: CGFloat { 6 }

    private func photoCell(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
            }
        }
        .padding(70)
        .frame(width: Self.width)
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
            metaLine([Format.date(run.startDate)], leading: false).padding(.top, 6)
        }
    }

    /// The most restrained: just the statement and one quiet caption line.
    private var minimalFooter: some View {
        VStack(spacing: 16) {
            title(leading: false)
            heroBlock(leading: false)
            metaLine([placeLine, Format.date(run.startDate)], leading: false)
        }
    }

    /// Left-aligned, gallery-label feel: title, distance, a compact stat line, place · date.
    private var editorialFooter: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(leading: true)
            heroBlock(leading: true)
            HStack(spacing: 28) {
                editorialStat("TIME", Format.duration(run.movingTime))
                editorialStat("PACE", Format.pace(secondsPerKm: run.paceSecondsPerKm))
                editorialStat("ELEV GAIN", Format.elevationGain(run.elevationGain))
            }
            if includeWeather, let weather = run.weatherLine() { weatherText(weather, leading: true) }
            metaLine([placeLine, Format.date(run.startDate)], leading: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Footer pieces

    private func title(leading: Bool) -> some View {
        Text(run.name.uppercased())
            .font(.system(size: 26, weight: .semibold))
            .tracking(4)
            .foregroundStyle(subtleColor)
            .lineLimit(2)
            .multilineTextAlignment(leading ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    private func heroBlock(leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: 6) {
            Text(heroNumber)
                .font(.system(size: 150, weight: .bold))
                .tracking(-2)
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("\(UnitSystem.current.label.uppercased()) ETCHED")
                .font(.system(size: 24, weight: .semibold))
                .tracking(8)
                .foregroundStyle(edition.accent)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

    private var statRow: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("TIME", Format.duration(run.movingTime))
            statDivider
            stat("PACE", Format.pace(secondsPerKm: run.paceSecondsPerKm))
            statDivider
            stat("ELEV GAIN", Format.elevationGain(run.elevationGain))
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
