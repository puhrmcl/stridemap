import SwiftUI

/// The Etch Studio artwork itself: one parametric composition that renders any edition for a
/// run. Map editions receive a pre-rendered `mapImage`; paper editions (Minimal, Relief) draw
/// the route as vector art. Laid out at a fixed portrait size and rendered to an image for
/// preview and export.
///
/// Follows the brand's typographic hierarchy — a large distance statement, the "Etched." mark
/// as the single quiet signal, metadata in wide-tracked uppercase, and sparse metrics.
struct StudioComposition: View {
    let run: Run
    let edition: StudioEdition
    /// Pre-rendered map panel for map editions; nil for paper editions.
    var mapImage: UIImage?
    /// When on (and the run has weather), a quiet temperature/condition line is added.
    var includeWeather: Bool = false

    static let width: CGFloat = 1000
    static let artHeight: CGFloat = 1000
    static var size: CGSize { CGSize(width: width, height: artHeight + 620) }

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
            if edition.usesMap, let mapImage {
                Image(uiImage: mapImage).resizable().scaledToFill()
            } else if run.coordinates.count > 1 {
                routeArt.padding(130)
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: 130, weight: .semibold))
                    .foregroundStyle(edition.subtle)
            }
        }
        .frame(width: Self.width, height: Self.artHeight)
        .clipped()
    }

    /// Vector route for paper editions. Spectrum strokes with the edition's gradient for a
    /// single artful gesture; Minimal is a clean flat line.
    @ViewBuilder
    private var routeArt: some View {
        if let colors = edition.routeGradient {
            RouteShape(coordinates: run.coordinates)
                .stroke(
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: stroke(edition.routeWidth)
                )
        } else {
            RouteShape(coordinates: run.coordinates)
                .stroke(edition.route, style: stroke(edition.routeWidth))
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
                .foregroundStyle(edition.subtle)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            VStack(spacing: 6) {
                Text(heroNumber)
                    .font(.system(size: 150, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(edition.ink)
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
                    .foregroundStyle(edition.subtle)
                    .multilineTextAlignment(.center)
            }

            if includeWeather, let weather = run.weatherLine() {
                Text(weather.uppercased())
                    .font(.system(size: 19, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(edition.subtle)
            }

            Rectangle()
                .fill(edition.subtle.opacity(0.4))
                .frame(width: 90, height: 2)
                .padding(.vertical, 6)

            HStack(alignment: .top, spacing: 0) {
                stat("TIME", Format.duration(run.movingTime))
                statDivider
                stat("PACE", Format.pace(secondsPerKm: run.paceSecondsPerKm))
                statDivider
                stat("ELEV", Format.elevation(run.elevationGain))
            }

            HStack {
                Text(Format.date(run.startDate).uppercased())
                    .font(.system(size: 18, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(edition.subtle)
                Spacer()
                HStack(spacing: 8) {
                    Text("etch")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(edition.ink)
                    Text("STUDIO")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(3)
                        .foregroundStyle(edition.accent)
                }
            }
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
                .foregroundStyle(edition.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(edition.subtle)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(edition.subtle.opacity(0.35)).frame(width: 1, height: 42)
    }

    // MARK: Content

    private var heroNumber: String {
        Format.distanceValue(run.distance).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var placeLine: String {
        [run.city, run.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
