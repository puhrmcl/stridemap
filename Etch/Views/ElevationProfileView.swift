import SwiftUI

/// A filled elevation-over-distance chart for a route. Prefers the source's recorded altitude
/// stream (exact and instant); falls back to terrain sampled along the path (Open-Meteo, cached)
/// only when the run carries none. Elevation is the story of a hike, so hike/ride detail leads with
/// it — the climb, and the low and high points, the way AllTrails does. The terrain fallback needs
/// one network fetch (then cached), so it fails quietly to a short note when offline.
struct ElevationProfileView: View {
    let run: Run

    @State private var samples: [Double] = []
    @State private var phase: Phase = .loading
    private enum Phase { case loading, loaded, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Elevation", systemImage: "mountain.2")
                .font(.etch(.headline))

            switch phase {
            case .loading:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 130)
                    .overlay { ProgressView() }
            case .failed:
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash").foregroundStyle(.tertiary)
                    Text("Elevation profile needs a connection — it'll load next time you're online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            case .loaded:
                chart
                stats
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .task(id: run.id) { await load() }
    }

    private var chart: some View {
        GeometryReader { geo in
            chartBody(in: geo.size)
        }
        .frame(height: 130)
    }

    private func chartBody(in size: CGSize) -> some View {
        let pts = points(in: size)
        return ZStack {
            // Filled area under the trace.
            Path { p in
                guard let first = pts.first, let last = pts.last else { return }
                p.move(to: CGPoint(x: first.x, y: size.height))
                p.addLine(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: last.x, y: size.height))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.04)],
                                 startPoint: .top, endPoint: .bottom))
            // The elevation line itself.
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// Maps the elevation samples to points inside `size` — x by index, y by the min–max range.
    private func points(in size: CGSize) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let lo = samples.min() ?? 0
        let hi = samples.max() ?? 1
        let range = max(hi - lo, 1)
        return samples.indices.map { i in
            let x = CGFloat(i) / CGFloat(samples.count - 1) * size.width
            let y = size.height - CGFloat((samples[i] - lo) / range) * size.height
            return CGPoint(x: x, y: max(1, min(size.height - 1, y)))
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            profileStat("Gain", Format.elevation(run.elevationGain), "arrow.up.forward")
            if let hi = samples.max() {
                profileStat("High point", Format.elevation(hi), "arrow.up.to.line")
            }
            if let lo = samples.min() {
                profileStat("Low point", Format.elevation(lo), "arrow.down.to.line")
            }
        }
        .padding(.top, 2)
    }

    private func profileStat(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.etch(.subheadline, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        // Prefer the source-recorded altitude profile — the exact curve the device logged, and
        // instant (no network). Fall back to terrain sampled along the route (cached) only when
        // the source carried no elevation stream.
        let recorded = run.elevationSeries
        if recorded.count > 1 {
            samples = recorded
            phase = .loaded
            return
        }
        phase = .loading
        let coords = run.coordinates
        guard coords.count > 1 else { phase = .failed; return }
        if let profile = await ElevationService.routeProfile(for: coords), profile.count > 1 {
            samples = profile
            phase = .loaded
        } else {
            phase = .failed
        }
    }
}
