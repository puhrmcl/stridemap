import Foundation

/// The records a history holds, as data rather than as rows.
///
/// Achievements drew these inline — six `if let`s, each hand-composing an icon, a title and a
/// formatted value — which was fine while Achievements was the only screen that knew what a
/// record was. Search is the second, and two screens deriving the same superlatives independently
/// is how "Furthest" on one becomes "Longest Distance" on the other.
///
/// So the list is computed once here and rendered twice.
extension RunStatistics {

    /// One superlative: what it is, what it reads, and the activity that holds it.
    struct Record: Identifiable {
        enum Group { case superlative, personalBest }

        let title: String
        let symbol: String
        /// The figure, already formatted for display.
        let value: String
        /// The line beneath — usually the activity's name.
        let detail: String
        let run: Run
        let group: Group
        /// Other words that should find this record.
        ///
        /// A record is looked for by a description rather than by its name: nobody types
        /// "Highest Climb", they type "climb", or "elevation", or "biggest". And "farthest" is
        /// how half of the English-speaking world spells the word this app renders as "Furthest".
        let aliases: [String]

        var id: String { "\(title)-\(run.id.uuidString)" }

        /// Everything a search should match against, lowercased once.
        var haystack: String {
            ([title, value, detail, run.name] + aliases).joined(separator: " ").lowercased()
        }
    }

    /// Every record this history holds, superlatives first.
    ///
    /// `usesPace` gates the pace-based ones. Pace records are a running concept — a hike's
    /// "fastest pace" is a number about terrain, not about effort — which is the same rule
    /// Achievements has always applied to the rows themselves.
    func records(usesPace: Bool) -> [Record] {
        var out: [Record] = []

        if let furthest = longestRun {
            out.append(Record(
                title: "Furthest", symbol: "arrow.left.and.right",
                value: Format.distance(furthest.distance), detail: furthest.name,
                run: furthest, group: .superlative,
                aliases: ["farthest", "longest distance", "distance", "record", "biggest"]
            ))
        }
        if let longest = longestDurationRun {
            out.append(Record(
                title: "Longest", symbol: "clock",
                value: Format.duration(longest.movingTime), detail: longest.name,
                run: longest, group: .superlative,
                aliases: ["longest time", "duration", "time", "record"]
            ))
        }
        if let climb = highestClimb {
            out.append(Record(
                title: "Highest Climb", symbol: "mountain.2",
                value: Format.elevation(climb.elevationGain), detail: climb.name,
                run: climb, group: .superlative,
                aliases: ["climb", "elevation", "gain", "highest", "biggest climb",
                          "most elevation", "record", "vert"]
            ))
        }
        if usesPace, let fastest = fastestRun {
            out.append(Record(
                title: "Fastest Pace", symbol: "bolt.fill",
                value: Format.pace(secondsPerKm: fastest.paceSecondsPerKm), detail: fastest.name,
                run: fastest, group: .superlative,
                aliases: ["fastest", "quickest", "pace", "speed", "record"]
            ))
        }
        if let north = northernmostRun {
            out.append(Record(
                title: "Northernmost", symbol: "arrow.up",
                value: north.placeLabel.isEmpty ? "—" : north.placeLabel, detail: north.name,
                run: north, group: .superlative,
                aliases: ["north", "furthest north", "record"]
            ))
        }
        if let south = southernmostRun {
            out.append(Record(
                title: "Southernmost", symbol: "arrow.down",
                value: south.placeLabel.isEmpty ? "—" : south.placeLabel, detail: south.name,
                run: south, group: .superlative,
                aliases: ["south", "furthest south", "record"]
            ))
        }

        if usesPace {
            for pr in personalRecords {
                out.append(Record(
                    title: pr.label, symbol: "stopwatch",
                    value: Format.duration(pr.time),
                    detail: "\(Format.pace(secondsPerKm: pr.run.paceSecondsPerKm)) pace",
                    run: pr.run, group: .personalBest,
                    aliases: ["pb", "pr", "personal best", "personal record", "best", "record",
                              "fastest \(pr.label)"]
                ))
            }
        }

        return out
    }
}
