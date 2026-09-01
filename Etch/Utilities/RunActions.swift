import Foundation
import MapKit

/// Sharing and navigation actions for an activity, shared by the run detail, the search tiles, and
/// anywhere else a run can be acted on — so the share text and the "open in Apple Maps" behaviour
/// stay identical everywhere.
extension Run {

    /// Importer app prefixes that eat the title before it says anything ("Nike Run Club: 9 Week
    /// Training…" truncates to "Nike Run Club: 9 We…" in a list row). Only known importer names are
    /// stripped — a colon in the user's own title is left alone.
    private static let importerPrefixes = [
        "Nike Run Club: ", "Nike Training Club: ", "Nike Run Club - ",
        "Strava: ", "Runkeeper: ", "MapMyRun: ", "Garmin Connect: "
    ]

    /// The activity's name for list rows: the stored name with any known importer prefix stripped,
    /// so the line leads with the workout, not the app it came from. The detail view keeps the full
    /// stored `name`, so the source remains visible where there's room for it.
    var displayName: String {
        for prefix in Self.importerPrefixes where name.hasPrefix(prefix) {
            let trimmed = name.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return name
    }

    /// A tidy text summary of the activity for the system share sheet (name, date, place, and the
    /// key stats). Races lead with a checkered flag.
    var shareSummary: String {
        var lines: [String] = [isRace ? "🏁 \(name)" : name, Format.dateTime(startDate)]
        if !placeLabel.isEmpty { lines.append(placeLabel) }
        lines.append("")
        lines.append("Distance  \(Format.distance(distance, decimals: 2))")
        lines.append("Time  \(Format.duration(movingTime))")
        if distance > 0 {
            let secondsPerKm = Double(movingTime) / (distance / 1000)
            lines.append("Pace  \(Format.pace(secondsPerKm: secondsPerKm))")
        }
        if elevationGain > 0 {
            lines.append("Elevation  \(Format.elevationGain(elevationGain))")
        }
        lines.append("")
        lines.append("Tracked with Etch")
        return lines.joined(separator: "\n")
    }

    /// True when the activity has a location that can be opened in Apple Maps.
    var hasMapLocation: Bool { startCoordinate != nil }

    /// A universal Apple Maps link to where the activity happened. Opens the Maps app on Apple
    /// platforms and maps.apple.com anywhere else, so a shared activity is one tap from the place —
    /// and the link still works for whoever receives it.
    var appleMapsURL: URL? {
        guard let coordinate = startCoordinate else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: name.isEmpty ? "Activity" : name)
        ]
        return components?.url
    }

    /// The activity's start point as an Apple Maps place, tagged with the run's name.
    var mapItem: MKMapItem? {
        guard let coordinate = startCoordinate else { return nil }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }

    /// Opens the activity's location in Apple Maps — as a dropped place, or with driving directions
    /// to its start point when `directions` is true. No-op for an activity with no location.
    func openInAppleMaps(directions: Bool = false) {
        guard let item = mapItem else { return }
        let options = directions
            ? [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
            : nil
        item.openInMaps(launchOptions: options)
    }
}
