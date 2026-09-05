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

    /// What missing history is allowed to do to a claim.
    enum ClaimWorld: String, Hashable {
        /// Missing data cannot falsify the claim because the record itself is the subject.
        case closed
        /// Missing data can only make the quantity larger (for example, "at least 10 states").
        case floor
        /// Missing data could falsify the claim (for example, "your first marathon").
        case open
    }

    enum ConfidenceBand: String, Hashable {
        case high
        case medium
        case low
    }

    struct Confidence: Hashable {
        let value: Double
        let band: ConfidenceBand
        let reasons: [String]

        init(_ value: Double, reasons: [String]) {
            let clamped = min(1, max(0, value))
            self.value = clamped
            self.band = clamped >= 0.82 ? .high : (clamped >= 0.55 ? .medium : .low)
            self.reasons = reasons
        }
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
        let confidence: Confidence
        let claimWorld: ClaimWorld
        let evidence: [String]

        /// Identity is structural. Copy changes must never orphan user feedback.
        var id: String {
            "\(kind.rawValue)-\(run?.id.uuidString ?? "history")-\(claimWorld.rawValue)"
        }
    }

    private let runs: [Run]
    private let chronological: [Run]
    private let calendar: Calendar
    private let referenceDate: Date

    init(runs: [Run], calendar: Calendar = .current, referenceDate: Date = Date()) {
        self.runs = runs.filter { !$0.isHidden && !$0.excludedFromTotals }
        self.chronological = self.runs.sorted { $0.startDate < $1.startDate }
        self.calendar = calendar
        self.referenceDate = referenceDate
    }

    /// Confidence that the imported record is broad enough to support an open-world claim.
    /// A bulk backfill is useful history, but it is not proof that the earliest imported event
    /// was the first event in the person's life.
    private func openWorldConfidence(for run: Run) -> Confidence {
        let ageAtImport = max(0, run.importedAt.timeIntervalSince(run.startDate))
        let witnessed = ageAtImport <= 7 * 86_400
        let horizon = chronological.first?.startDate ?? run.startDate
        let yearsFromHorizon = max(0, calendar.dateComponents([.day], from: horizon, to: run.startDate).day ?? 0) / 365

        var score = witnessed ? 0.78 : 0.34
        var reasons = [witnessed ? "Activity imported close to when it happened" : "Activity appears to be historical/backfilled data"]
        if yearsFromHorizon >= 2 {
            score += 0.12
            reasons.append("Claim occurs well after the beginning of the imported history")
        } else {
            reasons.append("Claim is close to the beginning of the imported history")
        }
        return Confidence(score, reasons: reasons)
    }

    private let closedWorldConfidence = Confidence(0.99, reasons: ["Claim is fully supported by the imported Etch record"])


    /// The strongest moments in this history, deduplicated and ranked.
    func insights(limit: Int = 12) -> [Insight] {
        guard !chronological.isEmpty else { return [] }
        var candidates: [Insight] = []
        candidates += firsts()
        // Race enumeration is intentionally not a meaning signal. A numbered list of finishes
        // is inventory, not interpretation.
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
                title: "Where your Etch record begins",
                story: first.placeLabel.isEmpty
                    ? "The earliest \(noun.lowercased()) in your Etch history."
                    : "The earliest \(noun.lowercased()) in your Etch history is in \(first.placeLabel).",
                symbol: "sparkles", run: first, significance: 62,
                confidence: openWorldConfidence(for: first), claimWorld: .open,
                evidence: ["Earliest \(noun.lowercased()) in imported history"]
            ))
        }

        if let firstRace = chronological.first(where: { $0.isRace }) {
            out.append(Insight(
                kind: .first, emotion: .pride,
                title: "Your earliest race in Etch",
                story: placeStory(prefix: "This is the earliest race in your imported Etch history", run: firstRace),
                symbol: "flag.checkered", run: firstRace, significance: 88,
                confidence: openWorldConfidence(for: firstRace), claimWorld: .open,
                evidence: ["Earliest activity marked as a race"]
            ))
        }
        return out
    }

    // MARK: - Race & records

    private func recordMoments() -> [Insight] {
        let stats = RunStatistics(runs)
        var out: [Insight] = []

        if let run = stats.longestRun {
            out.append(Insight(
                kind: .record, emotion: .perseverance,
                title: "Your furthest effort",
                story: "\(Format.distance(run.distance)) — farther than any other activity in this history.",
                symbol: "arrow.left.and.right", run: run, significance: 86,
                confidence: closedWorldConfidence, claimWorld: .closed,
                evidence: ["Maximum distance in history"]
            ))
        }
        if let run = stats.highestClimb, run.elevationGain > 0 {
            out.append(Insight(
                kind: .record, emotion: .perseverance,
                title: "Your biggest climb",
                story: "\(Format.elevation(run.elevationGain)) of climbing — your highest recorded ascent.",
                symbol: "mountain.2", run: run, significance: 80,
                confidence: closedWorldConfidence, claimWorld: .closed,
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
                confidence: closedWorldConfidence, claimWorld: .closed,
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
                        title: "\(country), in your Etch history",
                        story: "This is the earliest \(country) activity currently in your Etch record.",
                        symbol: "globe.americas.fill", run: run, significance: 72,
                        confidence: openWorldConfidence(for: run), claimWorld: .open,
                        evidence: ["Earliest located activity in \(country) within imported history"]
                    ))
                }
            }
            if let state = PlaceNames.canonicalState(run.state), !state.isEmpty,
               seenStates.insert(state).inserted, seenStates.count > 1 {
                out.append(Insight(
                    kind: .newPlace, emotion: .discovery,
                    title: "\(state), in your Etch history",
                    story: "This is the earliest \(state) activity currently in your Etch record.",
                    symbol: "map.fill", run: run, significance: 66,
                    confidence: openWorldConfidence(for: run), claimWorld: .open,
                    evidence: ["Earliest located activity in \(state) within imported history"]
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
                    confidence: closedWorldConfidence, claimWorld: .floor,
                    evidence: ["Cumulative distance crossed \(km) km"]
                ))
            }
        }
        return out
    }

    // MARK: - Time

    private func anniversaries() -> [Insight] {
        guard let first = chronological.first else { return [] }
        let years = calendar.dateComponents([.year], from: first.startDate, to: referenceDate).year ?? 0
        guard years >= 1 else { return [] }

        return [Insight(
            kind: .anniversary, emotion: .nostalgia,
            title: "\(years) \(years == 1 ? "year" : "years") in motion",
            story: "Your Etch history reaches back to \(first.startDate.formatted(date: .abbreviated, time: .omitted)).",
            symbol: "clock.arrow.circlepath", run: first, significance: min(78, 60 + years * 2),
            confidence: closedWorldConfidence, claimWorld: .closed,
            evidence: ["Elapsed years since earliest imported activity"]
        )]
    }

    private func placeStory(prefix: String, run: Run) -> String {
        run.placeLabel.isEmpty ? "\(prefix)." : "\(prefix) in \(run.placeLabel)."
    }
}
