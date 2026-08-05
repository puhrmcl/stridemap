import SwiftUI

/// Details for a single run, shown as a sheet when a route is tapped.
struct RunDetailView: View {
    let run: Run
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

                    openInStrava
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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
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
                metric("Type", run.sportType.replacingOccurrences(of: "Run", with: " Run").trimmingCharacters(in: .whitespaces), "figure.run")
            }
        }
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

    private var openInStrava: some View {
        Button {
            let appURL = URL(string: "strava://activities/\(run.activityID)")!
            let webURL = URL(string: "https://www.strava.com/activities/\(run.activityID)")!
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
