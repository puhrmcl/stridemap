import SwiftUI

/// Shared by every activity type. Recorded altitude takes priority over an explicitly labelled
/// terrain estimate; a missing route never masquerades as a flat elevation profile.
struct ElevationProfileView: View {
    let run: Run

    @State private var samples: [Double] = []
    @State private var phase: Phase = .loading
    @State private var estimated = false
    private enum Phase { case loading, loaded, failed, unavailable }

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
            case .unavailable:
                Text("No elevation profile was recorded for this activity.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .failed:
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash").foregroundStyle(.tertiary)
                    Text("Elevation profile couldn’t load. Try again when you have a connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                Button("Try again") { Task { await load() } }
            case .loaded:
                Text(estimated ? "Estimated terrain elevation" : "Recorded elevation")
                    .font(.caption).foregroundStyle(.secondary)
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
        estimated = false
        if recorded.count > 1 && recorded.allSatisfy({ $0.isFinite }) {
            samples = recorded
            phase = .loaded
            return
        }
        phase = .loading
        let coords = run.coordinates
        guard !run.isIndoor, coords.count > 1 else { phase = .unavailable; return }
        if let profile = await ElevationService.routeProfile(for: coords), profile.count > 1, profile.allSatisfy({ $0.isFinite }) {
            guard !Task.isCancelled else { return }
            estimated = true
            samples = profile
            phase = .loaded
        } else {
            phase = .failed
        }
    }
}
