import Foundation

/// Etch's interpretation layer.
///
/// Raw activity data answers *what happened*. MeaningEngine asks *why this moment may matter*.
/// The engine is intentionally deterministic and local: it produces evidence-backed candidates
/// that every surface can use consistently. A language model may eventually help phrase a story,
/// but it should never invent the significance.
///
/// v1 focuses on high-confidence facts already present in the library. The scoring model is
/// designed to grow into recency, photos, training arcs, anniversaries, relationships and
/// user-confirmed meaning without changing the UI contract.
struct MeaningEngine {

    enum Kind: String, Hashable {
        case first
        case personalBest
        case record
        case race
        case newPlace
        case distanceMilestone
        case anniversary
    }

    enum Emotion: String, Hashable {
        case pride
        case discovery
        case perseverance
        case nostalgia
    }

    struct Insight: Identifiable {
        let kind: Kind
        let emotion: Emotion
        let title: String
        let story: String
        let symbol: String
        let run: Run?
        /// 0...100. Used to rank, never shown as a gamified score.
        let significance: Int
        let evidence: [String]

        var id: String {
            "\(kind.rawValue)-\(run?.id.uuidString ?? title)-\(title)"
        }
    }

    private let runs: [Run]
    private let chronological: [Run]
    private let calendar: Calendar

    init(runs: [Run], calendar: Calendar = .current) {
        self.runs = runs.filter { !$0.isHidden && !$0.excludedFromTotals }
        self.chronological = self.runs.sorted { $0.startDate < $1.startDate }
        self.calendar = calendar
    }

    /// The strongest moments in this history, deduplicated and ranked.
    func insights(limit: Int = 12) -> [Insight] {
        guard !chronological.isEmpty else { return [] }
        var candidates: [Insight] = []
        candidates += firsts()
        candidates += raceMoments()
        candidates += recordMoments()
        candidates += placeFirsts()
        candidates += cumulativeDistanceMoments()
        candidates += anniversaries()

        // One activity can be meaningful for several reasons. Keep distinct stories, but avoid
        // repeating the exact same claim if multiple detectors reach it.
        var seen = Set<String>()
        let unique = candidates.filter { insight in
            let key = "\(insight.run?.id.uuidString ?? "history")|\(insight.title)"
            return seen.insert(key).inserted
        }

        return Array(unique.sorted {
            if $0.significance != $1.significance { return $0.significance > $1.significance }
            return ($0.run?.startDate ?? .distantPast) > ($1.run?.startDate ?? .distantPast)
        }.prefix(limit))
    }

    func insights(for run: Run) -> [Insight] {
        insights(limit: 100).filter { $0.run?.id == run.id }
    }

    // MARK: - Firsts

    private func firsts() -> [Insight] {
        var out: [Insight] = []
        let byType = Dictionary(grouping: chronological, by: \.activityType)
        for (_, activities) in byType {
            guard let first = activities.first else { continue }
            let noun = first.activityType.detailLabel
            out.append(Insight(
                kind: .first, emotion: .nostalgia,
                title: "Where your \(noun.lowercased()) story begins",
                story: first.placeLabel.isEmpty
                    ? "Your first \(noun.lowercased()) in Etch."
                    : "Your first \(noun.lowercased()) in Etch began in \(first.placeLabel).",
                symbol: "sparkles", run: first, significance: 62,
                evidence: ["Earliest \(noun.lowercased()) in imported history"]
            ))
        }

        if let firstRace = chronological.first(where: { $0.isRace }) {
            out.append(Insight(
                kind: .first, emotion: .pride,
                title: "Your first race",
                story: placeStory(prefix: "This is where your race history begins", run: firstRace),
                symbol: "flag.checkered", run: firstRace, significance: 88,
                evidence: ["Earliest activity marked as a race"]
            ))
        }
        return out
    }

    // MARK: - Race & records

    private func raceMoments() -> [Insight] {
        let races = chronological.filter(\.isRace)
        guard !races.isEmpty else { return [] }
        var out: [Insight] = []

        for (index, race) in races.enumerated() {
            if index > 0 {
                out.append(Insight(
                    kind: .race, emotion: .pride,
                    title: "Race \(index + 1)",
                    story: placeStory(prefix: "Another finish added to your story", run: race),
                    symbol: "flag.checkered", run: race,
                    significance: min(82, 68 + index * 2),
                    evidence: ["\(index + 1)th race chronologically"]
                ))
            }
        }
        return out
    }

    private func recordMoments() -> [Insight] {
        let stats = RunStatistics(runs)
        var out: [Insight] = []

        if let run = stats.longestRun {
            out.append(Insight(
                kind: .record, emotion: .perseverance,
                title: "Your furthest effort",
                story: "\(Format.distance(run.distance)) — farther than any other activity in this history.",
                symbol: "arrow.left.and.right", run: run, significance: 86,
                evidence: ["Maximum distance in history"]
            ))
        }
        if let run = stats.highestClimb, run.elevationGain > 0 {
            out.append(Insight(
                kind: .record, emotion: .perseverance,
                title: "Your biggest climb",
                story: "\(Format.elevation(run.elevationGain)) of climbing — your highest recorded ascent.",
                symbol: "mountain.2", run: run, significance: 80,
                evidence: ["Maximum elevation gain in history"]
            ))
        }

        for pr in stats.personalRecords {
            let isRace = pr.run.isRace
            out.append(Insight(
                kind: .personalBest, emotion: .pride,
                title: isRace ? "\(pr.label) PR" : "Your best \(pr.label)",
                story: "\(Format.duration(pr.time)) · \(Format.pace(secondsPerKm: pr.run.paceSecondsPerKm)) pace.",
                symbol: "stopwatch.fill", run: pr.run,
                significance: isRace ? 96 : 90,
                evidence: ["Fastest qualifying \(pr.label) in history"]
            ))
        }
        return out
    }

    // MARK: - Place

    private func placeFirsts() -> [Insight] {
        var seenStates = Set<String>()
        var seenCountries = Set<String>()
        var out: [Insight] = []

        for run in chronological {
            if let country = PlaceNames.canonicalCountry(run.country), !country.isEmpty,
               seenCountries.insert(country).inserted {
                // The first country is baseline, subsequent countries are discoveries.
                if seenCountries.count > 1 {
                    out.append(Insight(
                        kind: .newPlace, emotion: .discovery,
                        title: "A new country etched",
                        story: "\(country) became part of your map.",
                        symbol: "globe.americas.fill", run: run, significance: 88,
                        evidence: ["First located activity in \(country)"]
                    ))
                }
            }
            if let state = PlaceNames.canonicalState(run.state), !state.isEmpty,
               seenStates.insert(state).inserted, seenStates.count > 1 {
                out.append(Insight(
                    kind: .newPlace, emotion: .discovery,
                    title: "A new state etched",
                    story: "\(state) became part of your map.",
                    symbol: "map.fill", run: run, significance: 76,
                    evidence: ["First located activity in \(state)"]
                ))
            }
        }
        return out
    }

    // MARK: - Accumulation

    private func cumulativeDistanceMoments() -> [Insight] {
        // Universal kilometre thresholds internally; Format handles the user's display system.
        let thresholdsKm = [100, 250, 500, 1_000, 2_500, 5_000, 10_000]
        var crossed = Set<Int>()
        var total = 0.0
        var out: [Insight] = []

        for run in chronological {
            total += run.distance
            for km in thresholdsKm where !crossed.contains(km) && total >= Double(km) * 1_000 {
                crossed.insert(km)
                out.append(Insight(
                    kind: .distanceMilestone, emotion: .pride,
                    title: "\(km.formatted()) km etched",
                    story: "This activity carried your recorded history past \(km.formatted()) kilometres.",
                    symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                    run: run, significance: min(92, 66 + Int(log10(Double(km))) * 8),
                    evidence: ["Cumulative distance crossed \(km) km"]
                ))
            }
        }
        return out
    }

    // MARK: - Time

    private func anniversaries() -> [Insight] {
        guard let first = chronological.first else { return [] }
        let years = calendar.dateComponents([.year], from: first.startDate, to: Date()).year ?? 0
        guard years >= 1 else { return [] }

        return [Insight(
            kind: .anniversary, emotion: .nostalgia,
            title: "\(years) \(years == 1 ? "year" : "years") in motion",
            story: "Your Etch history reaches back to \(first.startDate.formatted(date: .abbreviated, time: .omitted)).",
            symbol: "clock.arrow.circlepath", run: first, significance: min(90, 68 + years * 3),
            evidence: ["Elapsed years since earliest imported activity"]
        )]
    }

    private func placeStory(prefix: String, run: Run) -> String {
        run.placeLabel.isEmpty ? "\(prefix)." : "\(prefix) in \(run.placeLabel)."
    }
}
