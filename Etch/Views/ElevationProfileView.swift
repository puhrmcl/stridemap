import SwiftUI

/// A filled elevation-over-distance chart for a route, drawn from terrain data sampled along the
/// path (Open-Meteo, cached). Elevation is the story of a hike, so hike/ride detail leads with it —
/// the climb, and the low and high points, the way AllTrails does. Fails quietly to a short note
/// when offline (the profile needs one network fetch, then it's cached forever).
struct ElevationProfileView: View {
    let run: Run

    @State private var samples: [Double] = []
    @State private var phase: Phase = .loading
    private enum Phase { case loading, loaded, failed }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Elevation", systemImage: "mountain.2")
                .font(.system(.headline, design: .rounded))

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
            let w = geo.size.width, h = geo.size.height
            let lo = samples.min() ?? 0
            let hi = samples.max() ?? 1
            let range = max(hi - lo, 1)
            func point(_ i: Int) -> CGPoint {
                let x = samples.count > 1 ? CGFloat(i) / CGFloat(samples.count - 1) * w : 0
                let y = h - CGFloat((samples[i] - lo) / range) * h
                return CGPoint(x: x, y: max(1, min(h - 1, y)))
            }
            ZStack {
                // Filled area under the trace.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    for i in samples.indices { p.addLine(to: point(i)) }
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                // The elevation line itself.
                Path { p in
                    for (n, i) in samples.indices.enumerated() {
                        let pt = point(i)
                        if n == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineJoin: .round, lineCap: .round))
            }
        }
        .frame(height: 130)
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
                .font(.system(.subheadline, design: .rounded).weight(.bold))
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
