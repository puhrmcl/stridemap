import Foundation
import CoreLocation

/// A curated library of well-known race courses, so someone who ran a race but never tracked it
/// on a watch or app can still add it — pick the race and year, type in their finish time, and get
/// a real activity (and a Studio poster) with the official course drawn on the map.
///
/// This is a *bundled catalog*, not an integration: there is no marathon API that hands you course
/// geometry, so each course is curated by hand. The set that matters is small and famous, which is
/// what makes that tractable — the value of a race library is the handful of iconic races, not
/// comprehensiveness.
///
/// > Course geometry note: the polylines below are **approximate** representative courses traced
/// > from public geography, good enough to place and shape the route recognisably. They are not
/// > survey-accurate GPX and are shared across the offered years. The model already supports
/// > per-year geometry (`courses[year]`), so swapping in verified, year-specific GPX later is a
/// > data-only change with no code impact. Do not sell prints off these until they're verified.
struct RaceEvent: Identifiable {
    let id: String
    let name: String
    let city: String
    let state: String?
    let country: String
    /// Official race distance in metres (a marathon is 42.195 km regardless of a runner's GPS).
    let distanceMeters: Double
    /// A typical calendar slot, used only to pre-fill the date field for the chosen year.
    let typicalMonth: Int
    let typicalDay: Int
    /// Course geometry keyed by year. Today every offered year points at the same representative
    /// course; the shape is per-year so real courses that reroute can diverge later.
    let courses: [Int: [CLLocationCoordinate2D]]

    /// The years offered in the picker, most recent first.
    var years: [Int] { courses.keys.sorted(by: >) }

    /// The course for a year, falling back to the most recent available if that exact year is
    /// missing (so the picker never lands on an empty course).
    func course(for year: Int) -> [CLLocationCoordinate2D] {
        courses[year] ?? courses[years.first ?? year] ?? []
    }

    /// A sensible default date for the chosen year — the race's typical slot, clamped to a valid day.
    func defaultDate(for year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = typicalMonth
        components.day = typicalDay
        components.hour = 8
        return Calendar.current.date(from: components) ?? Date()
    }
}

enum RaceCatalog {

    /// The curated events, ordered as shown in the picker.
    static let events: [RaceEvent] = [boston, newYork, chicago, mesa]

    /// The years offered for every event — the most recent three.
    private static let offeredYears = [2026, 2025, 2024]

    private static func courses(_ waypoints: [CLLocationCoordinate2D]) -> [Int: [CLLocationCoordinate2D]] {
        Dictionary(uniqueKeysWithValues: offeredYears.map { ($0, waypoints) })
    }

    // MARK: - Building a Run from a chosen race

    /// Creates a `Run` for a library race with the runner's own inputs. The activity carries the
    /// official course and distance, is flagged as a race, and optionally kept out of aggregate
    /// totals. It behaves like any imported run everywhere downstream (map, timeline, Studio).
    static func makeRun(
        event: RaceEvent,
        year: Int,
        date: Date,
        finishSeconds: Int,
        countsInTotals: Bool
    ) -> Run {
        let coordinates = event.course(for: year)
        let box = RouteGeometry.boundingBox(of: coordinates, fallbackStart: coordinates.first)
        let run = Run(
            provider: .other("Race Library"),
            name: "\(event.name) \(year)",
            startDate: date,
            distance: event.distanceMeters,
            movingTime: finishSeconds,
            elapsedTime: finishSeconds,
            elevationGain: 0,
            summaryPolyline: PolylineDecoder.encode(coordinates),
            city: event.city,
            state: event.state,
            country: event.country,
            sportType: "Run",
            isRace: true,
            isTrail: false,
            excludedFromTotals: !countsInTotals,
            startLatitude: coordinates.first?.latitude,
            startLongitude: coordinates.first?.longitude,
            minLatitude: box.minLat,
            maxLatitude: box.maxLat,
            minLongitude: box.minLon,
            maxLongitude: box.maxLon
        )
        run.importMethod = .manual
        run.raceIsCustom = true
        run.sourceExternalID = "race:\(event.id):\(year)"
        run.routeStatus = .available
        run.routeSource = .imported
        return run
    }

    // MARK: - Curated courses (approximate representative geometry — see note above)

    private static func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Boston Marathon — point-to-point, Hopkinton to Boylston Street.
    private static let boston = RaceEvent(
        id: "boston", name: "Boston Marathon", city: "Boston", state: "MA", country: "United States",
        distanceMeters: 42_195, typicalMonth: 4, typicalDay: 15,
        courses: courses([
            c(42.2296, -71.5214), c(42.2612, -71.4795), c(42.2793, -71.4162), c(42.2836, -71.3487),
            c(42.2967, -71.2925), c(42.3126, -71.2560), c(42.3300, -71.2124), c(42.3390, -71.1660),
            c(42.3467, -71.1300), c(42.3499, -71.0784)
        ])
    )

    /// TCS New York City Marathon — Staten Island to Central Park across all five boroughs.
    private static let newYork = RaceEvent(
        id: "nyc", name: "New York City Marathon", city: "New York", state: "NY", country: "United States",
        distanceMeters: 42_195, typicalMonth: 11, typicalDay: 3,
        courses: courses([
            c(40.6021, -74.0547), c(40.6350, -73.9960), c(40.6782, -73.9770), c(40.7180, -73.9580),
            c(40.7440, -73.9540), c(40.7570, -73.9620), c(40.7810, -73.9490), c(40.8080, -73.9330),
            c(40.7940, -73.9540), c(40.7690, -73.9760)
        ])
    )

    /// Chicago Marathon — a loop out and back from Grant Park through the neighborhoods.
    private static let chicago = RaceEvent(
        id: "chicago", name: "Chicago Marathon", city: "Chicago", state: "IL", country: "United States",
        distanceMeters: 42_195, typicalMonth: 10, typicalDay: 13,
        courses: courses([
            c(41.8757, -87.6210), c(41.8900, -87.6280), c(41.9250, -87.6520), c(41.9100, -87.6650),
            c(41.8820, -87.6470), c(41.8650, -87.6690), c(41.8480, -87.6660), c(41.8340, -87.6320),
            c(41.8570, -87.6240), c(41.8757, -87.6205)
        ])
    )

    /// Mesa Marathon — point-to-point net downhill from the northeast foothills into downtown Mesa.
    private static let mesa = RaceEvent(
        id: "mesa", name: "Mesa Marathon", city: "Mesa", state: "AZ", country: "United States",
        distanceMeters: 42_195, typicalMonth: 2, typicalDay: 8,
        courses: courses([
            c(33.5170, -111.6360), c(33.4930, -111.6600), c(33.4700, -111.6830), c(33.4530, -111.7050),
            c(33.4400, -111.7350), c(33.4360, -111.7700), c(33.4300, -111.8000), c(33.4230, -111.8250),
            c(33.4155, -111.8320)
        ])
    )
}
