import SwiftUI

/// A framed print of a single run — the route as art over the brand's Bone background with
/// the title, place, date, and key stats. Designed at a fixed poster size and rendered to a
/// shareable image. This is "your achievements become etched."
struct RunPosterView: View {
    let run: Run
    /// A pre-rendered map+route panel (a muted MapKit snapshot with the route on top). When
    /// nil, the panel falls back to the route drawn on a plain Bone background.
    var mapImage: UIImage?

    /// Size of the map panel (poster width). The footer sits below at its natural height.
    static let routePanelSize = CGSize(width: 1000, height: 980)

    var body: some View {
        VStack(spacing: 0) {
            routePanel
            footer
        }
        .frame(width: Self.routePanelSize.width)
        .background(Theme.Palette.bone)
    }

    private var routePanel: some View {
        ZStack {
            Theme.Palette.bone
            if let mapImage {
                Image(uiImage: mapImage).resizable().scaledToFill()
            } else if run.coordinates.count > 1 {
                RouteShape(coordinates: run.coordinates)
                    .stroke(
                        Theme.Palette.blue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                    )
                    .padding(90)
            } else {
                Image(systemName: "figure.run")
                    .font(.system(size: 120, weight: .semibold))
                    .foregroundStyle(Theme.Palette.stone)
            }
        }
        .frame(width: Self.routePanelSize.width, height: Self.routePanelSize.height)
        .clipped()
    }

    private var footer: some View {
        VStack(spacing: 22) {
            Rectangle()
                .fill(Theme.Palette.stone)
                .frame(width: 64, height: 3)

            VStack(spacing: 8) {
                Text(run.name.uppercased())
                    .font(.system(size: 48, weight: .bold))
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(Theme.Palette.ink)
                if !run.placeLabel.isEmpty {
                    Text(run.placeLabel.uppercased())
                        .font(.system(size: 22, weight: .medium))
                        .tracking(5)
                        .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                }
            }

            HStack(alignment: .top, spacing: 0) {
                stat("DISTANCE", Format.distance(run.distance))
                statDivider
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
                    .foregroundStyle(Theme.Palette.ink.opacity(0.5))
                Spacer()
                Text("etch")
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundStyle(Theme.Palette.blue)
            }
            .padding(.top, 4)
        }
        .padding(60)
        .background(Theme.Palette.bone)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Theme.Palette.ink.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Theme.Palette.stone).frame(width: 1, height: 40)
    }
}

/// Presents a poster preview for a run with a share action. Renders the fixed-size poster to
/// an image once, shows it scaled to fit, and shares the PNG.
struct RunPosterExportView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss

    @State private var poster: UIImage?
    @State private var fileURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let poster {
                    ScrollView {
                        Image(uiImage: poster)
                            .resizable()
                            .scaledToFit()
                            .clipShape(.rect(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                            .padding(20)
                    }
                } else {
                    ProgressView("Creating poster…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Route Poster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if let fileURL {
                        ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .task { await render() }
        }
    }

    @MainActor
    private func render() async {
        guard poster == nil else { return }
        // Snapshot the run's area as a muted, brand-tinted map with the route drawn on top,
        // then compose it with the title block.
        let mapImage = await PosterMap.routePanel(for: run, size: RunPosterView.routePanelSize)
        let renderer = ImageRenderer(content: RunPosterView(run: run, mapImage: mapImage))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }
        poster = image
        if let data = image.pngData() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Etch-\(run.id.uuidString).png")
            try? data.write(to: url)
            fileURL = url
        }
    }
}
