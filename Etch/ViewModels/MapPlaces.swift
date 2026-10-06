import Foundation

/// What to call a group of activities on the map.
///
/// The map's count bubbles answered "how many" and never "where" — "557" restates a number the
/// header already carries, while the one thing the reader actually recognises, *Phoenix*, was
/// sitting unused on every run in the cluster.
///
/// Pure values in, values out, so the behavioural check drives the same functions the map draws
/// from rather than a restatement of them.
enum MapPlaces {

    /// Where an activity started, in the most specific form that is actually known: the town,
    /// else the region, else the country. Nil when a run carries no place at all — an indoor
    /// session hand-placed on the map has coordinates but no geocode.
    static func name(city: String?, state: String?, country: String?) -> String? {
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return city
        }
        if let state = PlaceNames.canonicalState(state)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty {
            return state
        }
        if let country = PlaceNames.canonicalCountry(country)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            return country
        }
        return nil
    }

    /// The name most of a cluster agrees on.
    ///
    /// A grid cell straddling a city line should read as the place most of it is in, not whichever
    /// activity happened to sort first. Ties break alphabetically so the same cell always reads
    /// the same way rather than flickering between two names as the map rebuilds.
    static func dominant(_ names: [String]) -> String? {
        let cleaned = names.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for name in cleaned { counts[name, default: 0] += 1 }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Below this a cluster is an accident of zoom rather than a place, and naming every pair of
    /// activities would print the same town a dozen times down one street.
    static let namingThreshold = 5

    /// The diameter of a count bubble, in points.
    ///
    /// Area tracks quantity — the radius follows the square root of the share, so a place with
    /// four times the activity draws twice as wide. The fixed tiers this replaces capped at 58
    /// points, which drew 316 and 557 at exactly the same size while giving 4 and 23 visibly
    /// different discs: the encoding exaggerated the trivial gap and erased the real one.
    static func diameter(count: Int, total: Int) -> Double {
        guard count > 0, total > 0 else { return 26 }
        let share = min(1, Double(count) / Double(total))
        return min(64, max(26, 26 + 38 * share.squareRoot())).rounded()
    }
}
