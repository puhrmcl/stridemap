import SwiftUI
import SwiftData

/// Etch Studio's home inside the app — the "Make Lasting" surface. A calm, editorial hub for
/// turning a run, race, or favourite into art, plus the entry point for prints. Not a
/// configurator or a shop: the artwork leads, commerce stays quiet.
struct StudioHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]

    /// The run whose Studio composition sheet is presented.
    @State private var studioRun: Run?
    @State private var showPrints = false
    /// The aggregate map-print kind whose sheet is presented.
    @State private var mapPrintKind: MapPrintKind?

    private var stats: RunStatistics { RunStatistics(runs) }
    /// Only runs with a route make good art.
    private var mapped: [Run] { runs.filter(\.hasRoute) }

    var body: some View {
        NavigationStack {
            Group {
                if mapped.isEmpty {
                    ContentUnavailableView(
                        "Nothing to etch yet",
                        systemImage: "photo.artframe",
                        description: Text("Runs with a map become art here. Sync or import your history to begin.")
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 30) {
                            intro
                            if !milestones.isEmpty { subjectRow("Milestones", milestones) }
                            let races = mapped.filter(\.isRace)
                            if !races.isEmpty { subjectRow("Races", races.map { ($0, nil) }) }
                            let favorites = mapped.filter(\.isFavorite)
                            if !favorites.isEmpty { subjectRow("Favorites", favorites.map { ($0, nil) }) }
                            subjectRow("Recent", Array(mapped.prefix(12)).map { ($0, nil) })
                            mapPrintsSection
                            printsBand
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle("Etch Studio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $studioRun) { StudioView(run: $0) }
            .sheet(item: $mapPrintKind) { MapPrintView(runs: runs, kind: $0) }
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Make it lasting.")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Turn a run, a race, or a favorite into gallery-grade art.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Subject rows

    /// The standout runs, each with a small label — the most Studio-worthy subjects.
    private var milestones: [(Run, String?)] {
        var out: [(Run, String?)] = []
        if let r = stats.longestRun, r.hasRoute { out.append((r, "Furthest")) }
        if let r = stats.longestDurationRun, r.hasRoute { out.append((r, "Longest")) }
        if let r = stats.fastestRun, r.hasRoute { out.append((r, "Fastest")) }
        if let r = stats.highestClimb, r.hasRoute { out.append((r, "Highest")) }
        var seen = Set<UUID>()
        return out.filter { seen.insert($0.0.id).inserted }
    }

    private func subjectRow(_ title: String, _ items: [(Run, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.0.id) { run, caption in
                        Button { studioRun = run } label: { card(run, caption: caption) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func card(_ run: Run, caption: String?) -> some View {
        RunMonthTile(run: run, corner: 16)
            .frame(width: 168, height: 210)
            .overlay(alignment: .topLeading) {
                if let caption {
                    Text(caption.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.accent, in: .capsule)
                        .padding(10)
                }
            }
    }

    // MARK: Full-map prints (the whole history as one poster)

    private var mapPrintsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Full-Map Prints")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MapPrintKind.allCases) { kind in
                        Button { mapPrintKind = kind } label: { mapPrintCard(kind) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func mapPrintCard(_ kind: MapPrintKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text(kind.name)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            Text(kind.descriptor)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 200, height: 180, alignment: .leading)
        .background(Theme.accent.opacity(0.06), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent.opacity(0.15), lineWidth: 1))
    }

    // MARK: Prints (entry point — fulfillment lands with the Prodigi backend)

    private var printsBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prints")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Button { showPrints = true } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gallery prints, framed art & canvas", systemImage: "photo.artframe")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("Museum-grade paper, hardwood frames, and canvas — shipped to your door.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPrints) { PrintShopView(subjectTitle: nil) }
        }
        .padding(.horizontal, 20)
    }
}
