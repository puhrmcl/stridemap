import SwiftUI

/// The Etch Studio artwork itself: one parametric composition that renders any edition for a
/// run. Image editions (map snapshot, contour field) receive a pre-rendered `panelImage`;
/// paper editions draw the route as vector art. Laid out at a fixed portrait size and rendered
/// to an image for preview and export.
///
/// Follows the brand's typographic hierarchy — a large distance statement, the "Etched." mark
/// as the single quiet signal, metadata in wide-tracked uppercase, and sparse metrics. Route
/// and text colours may be overridden per the user's choice while the edition supplies the
/// defaults.
struct StudioComposition: View {
    let run: Run
    let edition: StudioEdition
    /// Pre-rendered art panel (map snapshot or contour field); nil for paper editions.
    var panelImage: UIImage?
    /// When on (and the run has weather), a quiet temperature/condition line is added.
    var includeWeather: Bool = false
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

    /// Vector route for paper and contour editions: an optional casing under the route line.
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

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 20) {
            Text(run.name.uppercased())
                .font(.system(size: 26, weight: .semibold))
                .tracking(4)
                .foregroundStyle(subtleColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            VStack(spacing: 6) {
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

            if !placeLine.isEmpty {
                Text(placeLine.uppercased())
                    .font(.system(size: 22, weight: .medium))
                    .tracking(5)
                    .foregroundStyle(subtleColor)
                    .multilineTextAlignment(.center)
            }

            if includeWeather, let weather = run.weatherLine() {
                Text(weather.uppercased())
                    .font(.system(size: 19, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(subtleColor)
            }

            Rectangle()
                .fill(subtleColor.opacity(0.4))
                .frame(width: 90, height: 2)
                .padding(.vertical, 6)

            HStack(alignment: .top, spacing: 0) {
                stat("TIME", Format.duration(run.movingTime))
                statDivider
                stat("PACE", Format.pace(secondsPerKm: run.paceSecondsPerKm))
                statDivider
                stat("ELEV", Format.elevation(run.elevationGain))
            }

            Text(Format.date(run.startDate).uppercased())
                .font(.system(size: 18, weight: .semibold))
                .tracking(3)
                .foregroundStyle(subtleColor)
                .padding(.top, 6)
        }
        .padding(70)
        .frame(width: Self.width)
        .background(edition.ground)
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

    private var statDivider: some View {
        Rectangle().fill(subtleColor.opacity(0.35)).frame(width: 1, height: 42)
    }

    // MARK: Content

    private var heroNumber: String {
        Format.distanceValue(run.distance).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var placeLine: String {
        [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
