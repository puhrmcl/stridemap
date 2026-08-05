import SwiftUI
import SwiftData
import MapKit

/// An automatically generated yearly recap with an animated playback of every run being
/// drawn across the map, in the order they happened.
struct YearInReviewView: View {
    let year: Int
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .forward) private var allRuns: [Run]

    @State private var revealed = 0
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?

    private var runs: [Run] {
        allRuns.filter { Calendar.current.component(.year, from: $0.startDate) == year && $0.hasRoute }
    }
    private var stats: RunStatistics { RunStatistics(runs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    playbackMap
                    headline
                    grid
                    superlatives
                }
                .padding(20)
            }
            .navigationTitle(String(year))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { stop(); dismiss() }
                }
            }
            .onDisappear { stop() }
            .onAppear { revealed = runs.count }
        }
    }

    // MARK: Playback

    private var playbackMap: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .region(overallRegion), interactionModes: []) {
                ForEach(Array(runs.prefix(revealed).enumerated()), id: \.element.activityID) { index, run in
                    let coords = run.coordinates
                    if coords.count > 1 {
                        let fraction = Double(index) / Double(max(runs.count - 1, 1))
                        MapPolyline(coordinates: coords)
                            .stroke(
                                Theme.Route.color(forAgeFraction: 1 - fraction),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 300)
            .clipShape(.rect(cornerRadius: Theme.cardRadius))

            playButton
                .padding(.bottom, 14)
        }
    }

    private var playButton: some View {
        Button {
            isPlaying ? stop() : play()
        } label: {
            Label(isPlaying ? "Stop" : "Play \(runs.count) runs", systemImage: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .glassBackground(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    private func play() {
        stop()
        isPlaying = true
        revealed = 0
        let total = runs.count
        guard total > 0 else { isPlaying = false; return }
        // Reveal all runs over ~5 seconds regardless of count.
        let step = max(1, total / 120)
        let delay = UInt64(5_000_000_000 / UInt64(max(total, 1)))
        playbackTask = Task { @MainActor in
            while revealed < total {
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    revealed = min(revealed + step, total)
                }
                try? await Task.sleep(nanoseconds: delay)
            }
            isPlaying = false
        }
    }

    private func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        revealed = runs.count
    }

    // MARK: Stats

    private var headline: some View {
        VStack(spacing: 6) {
            Text(Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0))))
                .font(.system(size: 60, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text("\(UnitSystem.current.label.lowercased()) run in \(String(year))")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: stats.totalRuns.formatted(), label: "Runs", systemName: "figure.run", accent: true)
            StatTile(value: stats.cities.count.formatted(), label: "Cities", systemName: "building.2")
            StatTile(value: stats.states.count.formatted(), label: "States", systemName: "map")
            StatTile(value: "\(stats.totalMovingTime / 3600)h", label: "Time Moving", systemName: "stopwatch")
        }
    }

    private var superlatives: some View {
        VStack(spacing: 10) {
            if let longest = stats.longestRun {
                SuperlativeRow(icon: "arrow.left.and.right", title: "Longest Run", value: Format.distance(longest.distance), subtitle: longest.name)
            }
            if let climb = stats.highestClimb {
                SuperlativeRow(icon: "mountain.2", title: "Highest Climb", value: Format.elevation(climb.elevationGain), subtitle: climb.name)
            }
            if let visited = stats.mostVisitedArea {
                SuperlativeRow(icon: "star.fill", title: "Favorite Route", value: "\(visited.count)×", subtitle: visited.label)
            }
        }
    }

    private var overallRegion: MKCoordinateRegion {
        guard !runs.isEmpty else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.8, longitude: -98.5), span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30))
        }
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for run in runs {
            minLat = min(minLat, run.minLatitude); maxLat = max(maxLat, run.maxLatitude)
            minLon = min(minLon, run.minLongitude); maxLon = max(maxLon, run.maxLongitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.3 + 0.05, longitudeDelta: (maxLon - minLon) * 1.3 + 0.05)
        )
    }
}
