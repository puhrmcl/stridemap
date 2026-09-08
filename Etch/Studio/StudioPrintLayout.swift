import SwiftUI
import UIKit

/// Geometry and type fitting used by both preview and the full-resolution print renderer.
enum StudioPrintLayout {
    static func gallerySecondaryHeight(total: CGFloat, gutter: CGFloat, fraction: CGFloat) -> CGFloat {
        max(0, total - gutter) * min(1, max(0, fraction))
    }

    static func fittedAttributes(_ text: String, font: UIFont, color: UIColor,
                                 tracking: CGFloat, width: CGFloat) -> [NSAttributedString.Key: Any] {
        let original: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        let measured = (text as NSString).size(withAttributes: original).width
        let scale = min(1, max(1, width) / max(1, measured))
        return [.font: font.withSize(font.pointSize * scale),
                .kern: tracking * scale, .foregroundColor: color]
    }

    static func cityKey(for run: Run) -> String {
        [run.city, run.state, run.country]
            .map { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{1F}")
    }

    struct CityEntry: Equatable {
        let name: String
        let count: Int
        let metres: Double
    }

    /// A city name alone is not a place identity: Portland, Maine must not merge with Oregon.
    static func cityEntries(in runs: [Run]) -> [CityEntry] {
        struct Place {
            var city: String
            var suffix: String
            var count = 0
            var metres = 0.0
        }
        var places: [String: Place] = [:]
        for run in runs {
            let city = (run.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !city.isEmpty else { continue }
            let parts = [run.state, run.country].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let key = cityKey(for: run)
            var place = places[key] ?? Place(city: city, suffix: parts.joined(separator: ", "))
            place.count += 1
            place.metres += run.distance
            places[key] = place
        }
        let repeated = Dictionary(grouping: places.values, by: { $0.city.lowercased() })
        return places.values.map { place in
            let needsRegion = (repeated[place.city.lowercased()]?.count ?? 0) > 1 && !place.suffix.isEmpty
            return CityEntry(name: needsRegion ? "\(place.city), \(place.suffix)" : place.city,
                             count: place.count, metres: place.metres)
        }.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
