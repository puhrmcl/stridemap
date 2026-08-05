import SwiftUI

/// Details for a single run, shown as a sheet when a route is tapped.
struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    RunPreviewMap(run: run, interactive: true)
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))

                    metrics

                    sourceFooter

                    if run.isStravaLinked {
                        openInStrava
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading) {
                        Text(run.name).font(.headline).lineLimit(1)
                        if !run.placeLabel.isEmpty {
                            Text(run.placeLabel).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            run.isFavorite.toggle()
                        } label: {
                            Image(systemName: run.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(run.isFavorite ? Theme.accent : .secondary)
                        }
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metric("Distance", Format.distance(run.distance), "point.topleft.down.to.point.bottomright.curvepath")
                metric("Time", Format.duration(run.movingTime), "stopwatch")
            }
            HStack(spacing: 12) {
                metric("Pace", Format.pace(secondsPerKm: run.paceSecondsPerKm), "speedometer")
                metric("Elevation", Format.elevation(run.elevationGain), "mountain.2")
            }
            HStack(spacing: 12) {
                metric("Date", Format.date(run.startDate), "calendar")
                if let hr = run.averageHeartRate, hr > 0 {
                    metric("Avg HR", "\(Int(hr)) bpm", "heart")
                } else {
                    metric("Type", cleanSportType, "figure.run")
                }
            }
            // Optional rich metrics only appear when the source provided them.
            if hasSecondaryMetrics {
                HStack(spacing: 12) {
                    if let energy = run.activeEnergy, energy > 0 {
                        metric("Energy", "\(Int(energy)) kcal", "flame")
                    }
                    if let cadence = run.averageCadence, cadence > 0 {
                        metric("Cadence", "\(Int(cadence)) spm", "figure.run")
                    }
                }
            }
        }
    }

    private var hasSecondaryMetrics: Bool {
        (run.activeEnergy ?? 0) > 0 || (run.averageCadence ?? 0) > 0
    }

    private var cleanSportType: String {
        run.sportType.replacingOccurrences(of: "Run", with: " Run").trimmingCharacters(in: .whitespaces)
    }

    private func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
    }

    /// Subtle provenance line — where the workout originated. Deliberately quiet.
    private var sourceFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: run.displaySource.symbol)
            Text("Recorded with \(run.displaySource.label)")
            if let gear = run.gear, !gear.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Image(systemName: "shoe")
                Text(gear)
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }

    private var openInStrava: some View {
        Button {
            guard let id = run.stravaActivityID else { return }
            let appURL = URL(string: "strava://activities/\(id)")!
            let webURL = URL(string: "https://www.strava.com/activities/\(id)")!
            openURL(appURL) { accepted in
                if !accepted { openURL(webURL) }
            }
        } label: {
            Label("Open in Strava", systemImage: "arrow.up.right.square")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.accent, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}
