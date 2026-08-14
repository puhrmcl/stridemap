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
    /// Pre-rendered art panel (map snapshot or photo); nil for paper editions.
    var panelImage: UIImage?
    var includeWeather: Bool = false
    var layout: StudioLayout = .classic
    /// User overrides; nil falls back to the edition's palette.
    var routeOverride: Color? = nil
    var textOverride: Color? = nil

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    static var size: CGSize { CGSize(width: width, height: artHeight + 620) }

    private var routeColor: Color { routeOverride ?? edition.route }
    private var inkColor: Color { textOverride ?? edition.ink }
    private var subtleColor: Color { textOverride.map { $0.opacity(0.6) } ?? edition.subtle }

    var body: some View {
        VStack(spacing: 0) {
            art
            footer
        }
        .frame(width: Self.width)
        .background(edition.ground)
    }

    // MARK: Art panel

    private var art: some View {
        ZStack {
            edition.ground
            if edition.usesImagePanel, let panelImage {
                Image(uiImage: panelImage).resizable().scaledToFill()
                // Map panels embed the route; the Memory photo does not, so the route is etched
                // over it — with a soft scrim so it reads on any photograph.
                if edition.isPhoto, run.coordinates.count > 1 {
                    LinearGradient(
                        colors: [.black.opacity(0.28), .clear, .black.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    )
                    routeArt.padding(120)
                }
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
        .background(edition.ground)
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
                editorialStat("ELEV", Format.elevation(run.elevationGain))
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
            stat("ELEV", Format.elevation(run.elevationGain))
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
