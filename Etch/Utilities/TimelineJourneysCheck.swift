import SwiftUI
import CoreLocation

/// Proves trip detection and tile significance, on a simulator, in CI.
///
/// Trip detection is a claim about someone's life — "you were in Scotland for six days" — made
/// without being told, from coordinates alone. A false chapter is far worse than a missed one: it
/// puts a heading on an ordinary week, and the reader stops trusting the section. So most of what
/// is pinned here is restraint: that a long ride from the door is not travel, that an activity the
/// reader hid cannot invent a journey, that a rest day does not split one trip into two.
@MainActor
struct TimelineJourneysCheckView: View {

    static let expectedChecks = 22

    @State private var report = "Checking trips…"

    var body: some View {
        ScrollView { Text(report).font(.system(size: 11, design: .monospaced)).padding() }
            .task { run() }
    }

    private func run() {
        var results: [(String, Bool, String)] = []
        func expect(_ name: String, _ passed: Bool, _ note: String) {
            results.append((name, passed, note))
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Denver is home; the far coordinates are real places at honest distances from it.
        let denver = CLLocationCoordinate2D(latitude: 39.74, longitude: -104.98)
        let boulder = CLLocationCoordinate2D(latitude: 40.01, longitude: -105.27)   // ~40 km
        let moab = CLLocationCoordinate2D(latitude: 38.57, longitude: -109.55)      // ~400 km
        let edinburgh = CLLocationCoordinate2D(latitude: 55.95, longitude: -3.19)

        func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
        }

        func activity(_ date: Date, at place: CLLocationCoordinate2D?,
                      distance: Double = 10_000, name: String = "check",
                      city: String? = nil, state: String? = nil, country: String? = nil,
                      race: Bool = false, photos: Int = 0,
                      hidden: Bool = false, excluded: Bool = false) -> Run {
            let run = Run(provider: .healthKit, name: name, startDate: date, distance: distance,
                          movingTime: 3_600, elapsedTime: 3_600, elevationGain: 50,
                          summaryPolyline: "", sportType: "Run", isRace: race,
                          excludedFromTotals: excluded)
            run.activityType = .run
            run.isHidden = hidden
            run.startLatitude = place?.latitude
            run.startLongitude = place?.longitude
            run.city = city
            run.state = state
            run.country = country
            if photos > 0 { run.photoReferences = (0..<photos).map { "check-photo-\(name)-\($0)" } }
            return run
        }

        // A year of ordinary activity at home, so there is a home to be away from.
        var home: [Run] = []
        for week in 0..<30 {
            home.append(activity(day(2026, 1, 5).addingTimeInterval(Double(week) * 7 * 86_400),
                                 at: denver, city: "Denver", state: "Colorado",
                                 country: "United States"))
        }

        // ── Home

        expect("Home is found from the busiest area",
               TimelineJourneys.home(home).map {
                   TimelineJourneys.metres(from: $0, to: denver) < 20_000
               } ?? false,
               "the median inside the busiest cell, not the mean of everything")

        expect("A history with no coordinates has no home",
               TimelineJourneys.home([activity(day(2026, 2, 2), at: nil)]) == nil,
               "an indoor-only library cannot be given a location")

        // ── Restraint

        let nearby = home + [
            activity(day(2026, 3, 7), at: boulder, city: "Boulder", state: "Colorado",
                     country: "United States", distance: 60_000),
            activity(day(2026, 3, 8), at: boulder, city: "Boulder", state: "Colorado",
                     country: "United States", distance: 60_000)
        ]
        expect("A long day out is not a trip",
               TimelineJourneys.trips(in: nearby, calendar: calendar).isEmpty,
               "Boulder is ~40 km from Denver — inside the away threshold, however long the ride")

        let single = home + [activity(day(2026, 4, 4), at: boulder, city: "Boulder",
                                      state: "Colorado", country: "United States")]
        expect("One activity nearby is not a trip",
               TimelineJourneys.trips(in: single, calendar: calendar).isEmpty,
               "neither far enough nor repeated enough to be travel")

        // ── A real trip

        let moabTrip = home + [
            activity(day(2026, 5, 2), at: moab, city: "Moab", state: "Utah",
                     country: "United States", name: "moab-1", photos: 4),
            activity(day(2026, 5, 3), at: moab, city: "Moab", state: "Utah",
                     country: "United States", name: "moab-2", photos: 2),
            activity(day(2026, 5, 5), at: moab, city: "Moab", state: "Utah",
                     country: "United States", name: "moab-3")
        ]
        let trips = TimelineJourneys.trips(in: moabTrip, calendar: calendar)
        expect("Activities away from home become one trip", trips.count == 1,
               "three activities in Utah, ~400 km out")
        expect("A rest day does not split a trip", trips.first?.runs.count == 3,
               "2nd, 3rd and 5th May are one trip, not two — most people do not move every day away")
        expect("The trip is named for where it was", trips.first?.title == "Moab, Utah",
               "one town, so the town and its region")
        expect("The trip spans its real dates", trips.first?.days == 4,
               "2nd to 5th May inclusive")
        expect("Photographs are counted", trips.first?.photoCount == 6,
               "what makes a trip worth re-opening")
        expect("The trip id is stable across detections",
               trips.first?.id == TimelineJourneys.trips(in: moabTrip, calendar: calendar).first?.id,
               "a fresh id per detection would make every refresh a new chapter to SwiftUI")

        // ── Splitting, abroad, and ordering

        let twoTrips = moabTrip + [
            activity(day(2026, 8, 1), at: moab, city: "Moab", state: "Utah",
                     country: "United States", name: "late-1"),
            activity(day(2026, 8, 2), at: moab, city: "Moab", state: "Utah",
                     country: "United States", name: "late-2")
        ]
        expect("A long gap starts a new trip",
               TimelineJourneys.trips(in: twoTrips, calendar: calendar).count == 2,
               "May and August are two visits to one place, not one three-month stay")
        expect("Trips read oldest first",
               TimelineJourneys.trips(in: twoTrips, calendar: calendar).first?.start == day(2026, 5, 2),
               "the Timeline opens at its foot on the most recent thing")

        let abroad = home + [
            activity(day(2026, 6, 10), at: edinburgh, city: "Edinburgh", country: "Scotland",
                     name: "scot-1"),
            activity(day(2026, 6, 12), at: edinburgh, city: "Edinburgh", country: "Scotland",
                     name: "scot-2")
        ]
        expect("Abroad is named by its country",
               TimelineJourneys.trips(in: abroad, calendar: calendar).first?.title == "Scotland",
               "the country is what the reader remembers, not the suburb they started in")

        let destinationRace = home + [
            activity(day(2026, 7, 4), at: edinburgh, city: "Edinburgh", country: "Scotland",
                     name: "one-race", race: true)
        ]
        expect("A single far-flung activity is still a trip",
               TimelineJourneys.trips(in: destinationRace, calendar: calendar).count == 1,
               "a destination race is travel even if you only ran once while there")

        // ── Admission

        let hiddenAway = home + [
            activity(day(2026, 9, 1), at: moab, name: "h1", hidden: true),
            activity(day(2026, 9, 2), at: moab, name: "h2", hidden: true)
        ]
        expect("Hidden activities cannot invent a trip",
               TimelineJourneys.trips(in: hiddenAway, calendar: calendar).isEmpty,
               "an activity the reader removed from the app must not reappear as a chapter heading")

        let excludedAway = home + [
            activity(day(2026, 9, 1), at: moab, name: "e1", excluded: true),
            activity(day(2026, 9, 2), at: moab, name: "e2", excluded: true)
        ]
        expect("Excluded-from-totals cannot invent a trip",
               TimelineJourneys.trips(in: excludedAway, calendar: calendar).isEmpty,
               "the same contract every other derived surface keeps")

        expect("An empty history has no trips",
               TimelineJourneys.trips(in: [], calendar: calendar).isEmpty,
               "a new library opens on this tab too")

        // ── Significance and rows

        let month = [
            activity(day(2026, 2, 1), at: denver, distance: 5_000, name: "easy"),
            activity(day(2026, 2, 3), at: denver, distance: 42_195, name: "marathon", race: true),
            activity(day(2026, 2, 5), at: denver, distance: 8_000, name: "steady"),
            activity(day(2026, 2, 7), at: denver, distance: 6_000, name: "shoot", photos: 4),
            activity(day(2026, 2, 9), at: denver, distance: 5_000, name: "easy-2")
        ]
        let grades = TimelineJourneys.significance(in: month)
        expect("A race outranks its other reasons",
               grades[month[1].id] == .race,
               "the marathon is also the longest; a race is what it reads as")
        expect("A well-photographed day is featured",
               grades[month[3].id] == .photographed,
               "four pictures is a day worth more than a square")
        expect("An ordinary activity stays ordinary",
               grades[month[0].id] == .ordinary,
               "if everything is featured then nothing is")

        let rows = TimelineJourneys.rows(for: month, significance: grades)
        expect("Featured activities take the full width",
               rows.contains { if case .hero = $0 { return true } else { return false } },
               "the hierarchy the uniform grid refused to show")
        expect("Every activity survives the banding",
               rows.reduce(0) { total, row in
                   switch row {
                   case .hero: return total + 1
                   case .strip(let runs): return total + runs.count
                   }
               } == month.count,
               "banding rearranges the month, it never drops part of it")

        // ── The count is itself an assertion.

        if results.count != Self.expectedChecks {
            results.append(("Check count", false,
                            "expected \(Self.expectedChecks) checks, ran \(results.count)"))
        }

        var lines = ["timeline-journeys \(AppInfo.changeTag)"]
        for result in results {
            lines.append("\(result.1 ? "PASS" : "FAIL")  \(result.0) — \(result.2)")
        }
        lines.append("EXPECTED_CHECKS: \(Self.expectedChecks)")
        lines.append("RAN_CHECKS: \(results.count)")
        let ok = results.allSatisfy(\.1) && results.count == Self.expectedChecks
        lines.append(ok ? "RESULT: ALL PASS" : "RESULT: FAIL")
        report = lines.joined(separator: "\n")

        guard let directory = FileManager.default.urls(for: .documentDirectory,
                                                       in: .userDomainMask).first else { return }
        try? report.write(to: directory.appendingPathComponent("timeline-journeys-report.txt"),
                          atomically: true, encoding: .utf8)
    }
}
