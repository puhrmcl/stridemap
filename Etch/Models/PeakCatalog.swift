import Foundation
import CoreLocation

/// The peak-bagging lists, loaded from `Resources/peak-lists.json`.
///
/// Data rather than code, for the reason `CourseLibrary` is: a list of fifty-eight summits is
/// tabular, it comes from somewhere else, and completing it should be a file drop rather than a
/// release. It is also the shape a second list arrives in — the 46ers, the NH48 — without a line
/// of Swift changing.
enum PeakCatalog {

    /// One summit on a list.
    struct Peak: Identifiable, Hashable, Decodable {
        let name: String
        /// Elevation in feet, exactly as the list publishes it. Feet rather than metres because
        /// that is the unit these lists are *named* in — a 14er is 14,000 feet, and converting to
        /// metres and back is how a 14,000 becomes a 13,999.
        let feet: Int
        let lat: Double
        let lon: Double

        var id: String { name }
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        var meters: Double { Double(feet) / 3.28084 }
        /// "14,267 ft" — the list's own unit, not the reader's. A 14er is a 14er in Munich.
        var label: String { "\(feet.formatted(.number.grouping(.automatic))) ft" }
    }

    private struct Document: Decodable {
        struct Entry: Decodable {
            let title: String
            let total: Int
            let peaks: [Peak]
        }
        let lists: [String: Entry]
    }

    private static let document: Document? = {
        guard let url = Bundle.main.url(forResource: "peak-lists", withExtension: "json")
                ?? Bundle.main.url(forResource: "peak-lists", withExtension: "json",
                                   subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Document.self, from: data)
        else { return nil }
        return decoded
    }()

    /// The summits bundled for a list — which may be fewer than the list actually has.
    static func peaks(_ list: PeakList) -> [Peak] {
        document?.lists[list.rawValue]?.peaks.sorted { $0.feet > $1.feet } ?? []
    }

    /// Whether every summit on the list is present.
    ///
    /// The gate the checklist poster hangs on. A piece whose whole content is "these are the
    /// fifty-eight, and here are the ones you stood on" cannot be printed from nine of them — it
    /// would be quietly wrong in a way the buyer discovers on their wall. Same rule the medal
    /// frame and the hanger follow: this shop does not list what it cannot make.
    static func isComplete(_ list: PeakList) -> Bool {
        peaks(list).count >= list.total
    }

    /// How many summits are still missing from the bundled data.
    static func missingCount(_ list: PeakList) -> Int {
        max(0, list.total - peaks(list).count)
    }
}

// MARK: - What you have climbed

/// A reader's standing against one list.
struct PeakListProgress {
    let list: PeakList
    /// The summits matched to an activity, highest first.
    let climbed: [PeakCatalog.Peak]
    /// The activity that reached each summit, by peak name — what the poster draws a route from.
    let runsByPeak: [String: Run]

    var count: Int { climbed.count }
    /// "9 of 58" — the denominator is the list's real total, never the bundled count, so an
    /// incomplete dataset can understate progress but can never overstate it.
    var label: String { "\(count) of \(list.total)" }
    var isEmpty: Bool { climbed.isEmpty }

    /// How close a hike has to start to a summit to count as having climbed it.
    ///
    /// Looser than the Summit Collection's 5 km, and deliberately: that radius is disambiguating
    /// between neighbouring peaks, while this is asking a yes/no question about one. Trailheads
    /// for a 14er sit several kilometres out and a couple of thousand feet down.
    static let matchRadius: Double = 8_000

    /// Works out which summits a history has reached.
    ///
    /// Two ways to match, because either alone misses real climbs. Geography is the honest test
    /// but needs a start coordinate, which imported and hand-added activities often lack. The name
    /// is the fallback, and a good one: people name a hike after the mountain, so "Quandary Peak"
    /// in a title is strong evidence. Geography wins where both are available.
    static func make(list: PeakList, runs: [Run]) -> PeakListProgress {
        let peaks = PeakCatalog.peaks(list)
        var matched: [String: Run] = [:]

        for peak in peaks {
            let summit = CLLocation(latitude: peak.lat, longitude: peak.lon)
            let byPlace = runs.filter { run in
                guard let lat = run.startLatitude, let lon = run.startLongitude else { return false }
                return CLLocation(latitude: lat, longitude: lon).distance(from: summit) < matchRadius
            }
            if let best = byPlace.max(by: { $0.elevationGain < $1.elevationGain }) {
                matched[peak.name] = best
                continue
            }
            // Names are compared case- and diacritic-insensitively, and the peak's name has to
            // appear whole: "Sunshine Peak" must not match a run called "Sunshine Canyon Loop".
            let needle = peak.name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                           locale: .current)
            if let named = runs.first(where: { run in
                run.name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                 locale: .current).contains(needle)
            }) {
                matched[peak.name] = named
            }
        }

        let climbed = peaks.filter { matched[$0.name] != nil }
        return PeakListProgress(list: list, climbed: climbed, runsByPeak: matched)
    }
}
