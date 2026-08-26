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
/// What kind of event this is — it decides the activity type the entry becomes, how the library
/// groups it, and the words the form uses ("finish time" reads differently on a summit).
enum EventDiscipline: String, CaseIterable, Identifiable, Sendable {
    case run, ride, hike
    var id: String { rawValue }

    var title: String {
        switch self {
        case .run:  return "Running"
        case .ride: return "Cycling"
        case .hike: return "Hikes & Summits"
        }
    }

    var icon: String {
        switch self {
        case .run:  return "figure.run"
        case .ride: return "bicycle"
        case .hike: return "mountain.2"
        }
    }

    /// The `Run.sportType` an entry of this kind becomes.
    var sportType: String {
        switch self {
        case .run:  return "Run"
        case .ride: return "Ride"
        case .hike: return "Hike"
        }
    }

    /// A summit isn't "a race you placed in" — the finisher fields only make sense competitively.
    var hasFinisherFields: Bool { self != .hike }
}

struct RaceEvent: Identifiable {
    let id: String
    let name: String
    let city: String
    let state: String?
    let country: String
    var discipline: EventDiscipline = .run
    /// Official race distance in metres (a marathon is 42.195 km regardless of a runner's GPS).
    /// For trails this is the commonly-cited round-trip length.
    let distanceMeters: Double
    /// A typical calendar slot, used only to pre-fill the date field for the chosen year.
    let typicalMonth: Int
    let typicalDay: Int
    /// The start line or trailhead — approximate, and the only geography most library entries
    /// carry. It places the activity on the map and in the right city; the *route* comes from the
    /// participant's own file, which is the honest source for a course that changes year to year.
    var start: CLLocationCoordinate2D? = nil
    /// Course geometry keyed by year, for the handful of events with a traced course. Empty means
    /// "no route until the participant attaches their file".
    var courses: [Int: [CLLocationCoordinate2D]] = [:]

    /// The years offered in the picker, most recent first. Events with no traced course still
    /// offer the standard recent years.
    var years: [Int] {
        courses.isEmpty ? RaceCatalog.offeredYears : courses.keys.sorted(by: >)
    }

    /// The course for a year, falling back to the most recent available. Empty when the library
    /// carries no geometry for this event.
    func course(for year: Int) -> [CLLocationCoordinate2D] {
        guard !courses.isEmpty else { return [] }
        return courses[year] ?? courses[courses.keys.sorted(by: >).first ?? year] ?? []
    }

    /// True when the library can draw this event's route without the participant's own file.
    var hasCourse: Bool { !courses.isEmpty }

    /// "Boston, MA · 26.2 mi" — the picker's supporting line.
    var summary: String {
        let place = [city, state].compactMap { $0 }.joined(separator: ", ")
        return "\(place) · \(Format.distance(distanceMeters, decimals: 1))"
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

    /// The curated events. The four with traced courses lead; the rest carry a start line or
    /// trailhead, an official distance, and a calendar slot — which is everything needed to
    /// create a real, correctly-placed activity. Their *route* comes from the participant's own
    /// file, because a course that reroutes yearly is not something to invent on their behalf.
    ///
    /// Coordinates are approximate start lines and trailheads; distances are the nominal
    /// published figures. Both are for placing and naming an activity, not for measuring one.
    static let events: [RaceEvent] = [boston, newYork, chicago, mesa] + library

    /// The years offered for every event — the most recent three.
    static let offeredYears = [2026, 2025, 2024]

    /// Events grouped for the picker, in the order the library presents them.
    static func grouped() -> [(discipline: EventDiscipline, events: [RaceEvent])] {
        EventDiscipline.allCases.compactMap { discipline in
            let matching = events.filter { $0.discipline == discipline }
            return matching.isEmpty ? nil : (discipline, matching)
        }
    }

    private static let marathon = 42_195.0
    private static let half = 21_097.5

    private static func event(_ id: String, _ name: String, _ city: String, _ state: String?,
                              _ country: String = "United States",
                              _ discipline: EventDiscipline, _ distance: Double,
                              _ month: Int, _ day: Int,
                              _ lat: Double, _ lon: Double) -> RaceEvent {
        RaceEvent(id: id, name: name, city: city, state: state, country: country,
                  discipline: discipline, distanceMeters: distance,
                  typicalMonth: month, typicalDay: day,
                  start: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    /// The library beyond the traced courses.
    private static let library: [RaceEvent] = [
        // ── Marathons
        event("london", "London Marathon", "London", nil, "United Kingdom", .run, marathon, 4, 27, 51.4676, 0.0090),
        event("berlin", "Berlin Marathon", "Berlin", nil, "Germany", .run, marathon, 9, 21, 52.5145, 13.3501),
        event("tokyo", "Tokyo Marathon", "Tokyo", nil, "Japan", .run, marathon, 3, 2, 35.6895, 139.6917),
        event("marine-corps", "Marine Corps Marathon", "Arlington", "Virginia", "United States", .run, marathon, 10, 26, 38.8895, -77.0353),
        event("los-angeles", "Los Angeles Marathon", "Los Angeles", "California", "United States", .run, marathon, 3, 16, 34.0669, -118.2437),
        event("big-sur", "Big Sur International Marathon", "Big Sur", "California", "United States", .run, marathon, 4, 27, 36.2704, -121.8081),
        event("grandmas", "Grandma's Marathon", "Duluth", "Minnesota", "United States", .run, marathon, 6, 21, 46.7867, -91.9962),
        event("houston", "Houston Marathon", "Houston", "Texas", "United States", .run, marathon, 1, 18, 29.7523, -95.3595),
        event("philadelphia", "Philadelphia Marathon", "Philadelphia", "Pennsylvania", "United States", .run, marathon, 11, 23, 39.9656, -75.1810),
        event("twin-cities", "Twin Cities Marathon", "Minneapolis", "Minnesota", "United States", .run, marathon, 10, 5, 44.9778, -93.2650),
        event("honolulu", "Honolulu Marathon", "Honolulu", "Hawaii", "United States", .run, marathon, 12, 14, 21.2793, -157.8292),

        // ── Half marathons and shorter
        event("rnr-san-diego-half", "Rock 'n' Roll San Diego Half", "San Diego", "California", "United States", .run, half, 6, 1, 32.7157, -117.1611),
        event("rnr-arizona-half", "Rock 'n' Roll Arizona Half", "Phoenix", "Arizona", "United States", .run, half, 1, 18, 33.4484, -112.0740),
        event("brooklyn-half", "Brooklyn Half", "Brooklyn", "New York", "United States", .run, half, 5, 17, 40.6782, -73.9442),
        event("peachtree", "Peachtree Road Race", "Atlanta", "Georgia", "United States", .run, 10_000, 7, 4, 33.8121, -84.3963),
        event("bolder-boulder", "BOLDERBoulder 10K", "Boulder", "Colorado", "United States", .run, 10_000, 5, 25, 40.0150, -105.2705),
        event("bay-to-breakers", "Bay to Breakers", "San Francisco", "California", "United States", .run, 12_000, 5, 17, 37.7749, -122.4194),
        event("falmouth", "Falmouth Road Race", "Falmouth", "Massachusetts", "United States", .run, 11_265, 8, 16, 41.5623, -70.6389),

        // ── Ultras and trail
        event("western-states", "Western States 100", "Olympic Valley", "California", "United States", .run, 160_934, 6, 27, 39.1968, -120.2357),
        event("leadville-100", "Leadville Trail 100", "Leadville", "Colorado", "United States", .run, 160_934, 8, 15, 39.2508, -106.2925),
        event("jfk-50", "JFK 50 Mile", "Boonsboro", "Maryland", "United States", .run, 80_467, 11, 21, 39.4143, -77.7311),
        event("pikes-peak-ascent", "Pikes Peak Ascent", "Manitou Springs", "Colorado", "United States", .run, 21_726, 9, 20, 38.8597, -104.9172),

        // ── Cycling
        event("unbound-gravel", "Unbound Gravel 200", "Emporia", "Kansas", "United States", .ride, 321_869, 5, 30, 38.4039, -96.1817),
        event("el-tour-tucson", "El Tour de Tucson", "Tucson", "Arizona", "United States", .ride, 160_934, 11, 21, 32.2226, -110.9747),
        event("triple-bypass", "Triple Bypass", "Evergreen", "Colorado", "United States", .ride, 193_121, 7, 11, 39.6333, -105.3172),
        event("levis-granfondo", "Levi's GranFondo", "Santa Rosa", "California", "United States", .ride, 160_934, 10, 3, 38.4405, -122.7141),
        event("gfny", "Gran Fondo New York", "Fort Lee", "New Jersey", "United States", .ride, 160_934, 5, 17, 40.8509, -73.9701),
        event("mt-washington-hillclimb", "Mt. Washington Auto Road Hillclimb", "Gorham", "New Hampshire", "United States", .ride, 12_231, 8, 15, 44.2619, -71.2536),
        event("assault-mt-mitchell", "Assault on Mt. Mitchell", "Spartanburg", "South Carolina", "United States", .ride, 164_154, 5, 18, 34.9496, -81.9320),
        event("etape-du-tour", "L'Étape du Tour", "Alpe d'Huez", nil, "France", .ride, 145_000, 7, 12, 45.0902, 6.0703),

        // ── Iconic hikes and summits
        event("half-dome", "Half Dome", "Yosemite National Park", "California", "United States", .hike, 22_530, 7, 15, 37.7459, -119.5332),
        event("angels-landing", "Angels Landing", "Zion National Park", "Utah", "United States", .hike, 8_690, 5, 15, 37.2690, -112.9469),
        event("the-narrows", "The Narrows", "Zion National Park", "Utah", "United States", .hike, 15_127, 6, 15, 37.2982, -112.9481),
        event("camelback", "Camelback Mountain (Echo Canyon)", "Phoenix", "Arizona", "United States", .hike, 4_023, 3, 15, 33.5225, -111.9631),
        event("humphreys-peak", "Humphreys Peak", "Flagstaff", "Arizona", "United States", .hike, 16_898, 8, 15, 35.3464, -111.6780),
        event("mount-whitney", "Mount Whitney", "Lone Pine", "California", "United States", .hike, 35_405, 8, 1, 36.5865, -118.2920),
        event("rim-to-rim", "Grand Canyon Rim to Rim", "Grand Canyon", "Arizona", "United States", .hike, 38_624, 10, 10, 36.0544, -112.1401),
        event("longs-peak", "Longs Peak", "Estes Park", "Colorado", "United States", .hike, 24_140, 8, 1, 40.2549, -105.6151),
        event("mount-elbert", "Mount Elbert", "Leadville", "Colorado", "United States", .hike, 15_288, 8, 1, 39.1178, -106.4453),
        event("mount-katahdin", "Mount Katahdin", "Millinocket", "Maine", "United States", .hike, 16_093, 9, 1, 45.9044, -68.9216),
        event("mount-washington", "Mount Washington (Tuckerman Ravine)", "Gorham", "New Hampshire", "United States", .hike, 13_518, 7, 15, 44.2571, -71.3033),
        event("kalalau", "Kalalau Trail", "Kauai", "Hawaii", "United States", .hike, 35_405, 5, 15, 22.2199, -159.5828),
        event("mount-si", "Mount Si", "North Bend", "Washington", "United States", .hike, 12_875, 6, 15, 47.4879, -121.7230),
        event("bright-angel", "Bright Angel Trail", "Grand Canyon", "Arizona", "United States", .hike, 30_578, 4, 15, 36.0574, -112.1436)
    ]

    private static func courses(_ waypoints: [CLLocationCoordinate2D]) -> [Int: [CLLocationCoordinate2D]] {
        Dictionary(uniqueKeysWithValues: offeredYears.map { ($0, waypoints) })
    }

    // MARK: - Building a Run from a chosen race

    /// Creates a `Run` for a library race with the runner's own inputs. The activity carries the
    /// official course and distance, is flagged as a race, and optionally kept out of aggregate
    /// totals. It behaves like any imported run everywhere downstream (map, timeline, Studio).
    /// Creates the activity for a library entry with everything the participant recorded about
    /// it. A route they attached themselves always wins over the library's traced course — it's
    /// the line they actually covered.
    static func makeRun(
        event: RaceEvent,
        year: Int,
        date: Date,
        finishSeconds: Int,
        countsInTotals: Bool,
        bibNumber: String = "",
        finishPlace: String = "",
        photoReferences: [String] = [],
        attachedRoute: [CLLocationCoordinate2D]? = nil,
        attachedElevations: [Double] = [],
        attachedPaces: [Double] = [],
        attachedDistance: Double? = nil
    ) -> Run {
        let attached = attachedRoute ?? []
        let coordinates = attached.isEmpty ? event.course(for: year) : attached
        let box = RouteGeometry.boundingBox(of: coordinates, fallbackStart: coordinates.first ?? event.start)
        // The official distance stands unless their own file measured the day.
        let distance = attached.isEmpty ? event.distanceMeters : (attachedDistance ?? event.distanceMeters)
        let run = Run(
            provider: .other("Race Library"),
            name: "\(event.name) \(year)",
            startDate: date,
            distance: distance,
            movingTime: finishSeconds,
            elapsedTime: finishSeconds,
            elevationGain: RouteMetrics.elevationGain(of: attachedElevations),
            summaryPolyline: PolylineDecoder.encode(coordinates),
            city: event.city,
            state: event.state,
            country: event.country,
            sportType: event.discipline.sportType,
            // A summit is an achievement, not a placing — flagging it as a race would put it in
            // the finisher collection and skew every race statistic.
            isRace: event.discipline != .hike,
            isTrail: event.discipline == .hike,
            excludedFromTotals: !countsInTotals,
            photoReferences: photoReferences,
            startLatitude: coordinates.first?.latitude ?? event.start?.latitude,
            startLongitude: coordinates.first?.longitude ?? event.start?.longitude,
            minLatitude: box.minLat,
            maxLatitude: box.maxLat,
            minLongitude: box.minLon,
            maxLongitude: box.maxLon
        )
        run.importMethod = .manual
        run.raceIsCustom = true
        run.sourceExternalID = "race:\(event.id):\(year)"
        run.bibNumber = bibNumber
        run.finishPlace = finishPlace
        if !attachedElevations.isEmpty { run.elevationSeries = attachedElevations }
        if !attachedPaces.isEmpty { run.paceSeries = attachedPaces }
        // Without geometry the activity is honestly route-less: the detail page then offers to
        // place it on the map or import the participant's file.
        run.routeStatus = coordinates.isEmpty ? .unavailable : .available
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
    /// This one is the **real, verified course** from the official 2026 GPX (mesamarathon.com), not
    /// the approximate geometry the note above describes; reused across the offered years.
    private static let mesa = RaceEvent(
        id: "mesa", name: "Mesa Marathon", city: "Mesa", state: "AZ", country: "United States",
        distanceMeters: 42_195, typicalMonth: 2, typicalDay: 7,
        courses: courses(mesaCourse)
    )

    /// Official 2026 Mesa Marathon course, 202 points (mesamarathon.com GPX export).
    private static let mesaCourse: [CLLocationCoordinate2D] = [
        c(33.483279, -111.622861), c(33.480101, -111.624724), c(33.478593, -111.625541),
        c(33.475764, -111.626721), c(33.469026, -111.62956), c(33.466186, -111.630501),
        c(33.46236, -111.631767), c(33.46215, -111.631876), c(33.462118, -111.632112),
        c(33.462516, -111.634457), c(33.46289, -111.635577), c(33.463466, -111.63667),
        c(33.465036, -111.638507), c(33.46548, -111.639121), c(33.465871, -111.640048),
        c(33.466041, -111.640907), c(33.46612, -111.642915), c(33.4662, -111.647744),
        c(33.4662, -111.64774), c(33.46622, -111.65413), c(33.466217, -111.654135),
        c(33.46622, -111.65413), c(33.46622, -111.65583), c(33.46626, -111.66123),
        c(33.46626, -111.661228), c(33.466312, -111.667266), c(33.466392, -111.671712),
        c(33.466398, -111.672232), c(33.466556, -111.672358), c(33.466867, -111.672356),
        c(33.468032, -111.672354), c(33.468546, -111.672321), c(33.469233, -111.672078),
        c(33.469514, -111.671912), c(33.469998, -111.67149), c(33.470385, -111.670993),
        c(33.47116, -111.669868), c(33.471433, -111.669541), c(33.472304, -111.668889),
        c(33.473332, -111.6682), c(33.473408, -111.668134), c(33.474006, -111.667429),
        c(33.477586, -111.661413), c(33.47824, -111.660737), c(33.478696, -111.660442),
        c(33.479742, -111.659884), c(33.481144, -111.659187), c(33.482091, -111.658672),
        c(33.483035, -111.65854), c(33.483823, -111.658676), c(33.484533, -111.659013),
        c(33.485324, -111.65962), c(33.485791, -111.660194), c(33.487605, -111.663226),
        c(33.48849, -111.663766), c(33.489808, -111.66451), c(33.490418, -111.665227),
        c(33.4908, -111.665854), c(33.491085, -111.666718), c(33.491267, -111.668717),
        c(33.491489, -111.671751), c(33.491703, -111.673082), c(33.491828, -111.674186),
        c(33.491681, -111.675612), c(33.491467, -111.67668), c(33.490852, -111.677861),
        c(33.4903, -111.678392), c(33.489654, -111.678811), c(33.489062, -111.679),
        c(33.487398, -111.679082), c(33.486981, -111.679138), c(33.484666, -111.679806),
        c(33.483902, -111.680046), c(33.481753, -111.680592), c(33.481211, -111.681085),
        c(33.480952, -111.681818), c(33.48094, -111.683687), c(33.481014, -111.683792),
        c(33.486076, -111.683921), c(33.489834, -111.684037), c(33.48992, -111.684152),
        c(33.489919, -111.686628), c(33.489786, -111.687227), c(33.489448, -111.687871),
        c(33.488649, -111.688666), c(33.487054, -111.690179), c(33.48576, -111.691407),
        c(33.484397, -111.692056), c(33.484087, -111.69244), c(33.483403, -111.693673),
        c(33.482685, -111.694794), c(33.482433, -111.695344), c(33.482188, -111.696081),
        c(33.48209, -111.696627), c(33.482081, -111.697142), c(33.482413, -111.699082),
        c(33.482261, -111.69992), c(33.482013, -111.700902), c(33.481896, -111.701335),
        c(33.481786, -111.701383), c(33.481533, -111.701326), c(33.481039, -111.701306),
        c(33.480639, -111.701324), c(33.476821, -111.701352), c(33.475377, -111.70137),
        c(33.471983, -111.701373), c(33.471698, -111.701377), c(33.468883, -111.701389),
        c(33.466987, -111.701474), c(33.466563, -111.701503), c(33.46647, -111.701596),
        c(33.466398, -111.710302), c(33.466436, -111.715419), c(33.466438, -111.723354),
        c(33.466442, -111.733168), c(33.466429, -111.739702), c(33.466437, -111.744108),
        c(33.46644, -111.745318), c(33.466434, -111.753045), c(33.466425, -111.759135),
        c(33.466412, -111.769168), c(33.46642, -111.77041), c(33.46625, -111.77058),
        c(33.461795, -111.770633), c(33.45745, -111.770722), c(33.45187, -111.770834),
        c(33.446584, -111.770892), c(33.443879, -111.770855), c(33.438502, -111.770935),
        c(33.437432, -111.770992), c(33.43729, -111.77114), c(33.437255, -111.774133),
        c(33.437256, -111.775577), c(33.437226, -111.779878), c(33.437089, -111.800804),
        c(33.437071, -111.805451), c(33.43701, -111.806987), c(33.436923, -111.807984),
        c(33.436724, -111.808831), c(33.435994, -111.810696), c(33.435719, -111.811638),
        c(33.435574, -111.812504), c(33.435549, -111.819405), c(33.435541, -111.822447),
        c(33.435389, -111.822632), c(33.434336, -111.822634), c(33.431149, -111.822722),
        c(33.430168, -111.822744), c(33.425977, -111.822834), c(33.421968, -111.822916),
        c(33.421375, -111.822923), c(33.421035, -111.822931), c(33.418172, -111.823032),
        c(33.417388, -111.823063), c(33.417303, -111.823166), c(33.417299, -111.827564),
        c(33.417321, -111.832944), c(33.417328, -111.834504), c(33.417327, -111.836455),
        c(33.417431, -111.836568), c(33.417728, -111.836575), c(33.41803, -111.836568),
        c(33.420768, -111.836533), c(33.421972, -111.836529), c(33.422202, -111.836535),
        c(33.422307, -111.836435), c(33.422351, -111.83192), c(33.422355, -111.831659),
        c(33.422498, -111.831518), c(33.430182, -111.831383), c(33.434682, -111.83131),
        c(33.434916, -111.831516), c(33.434933, -111.833393), c(33.434937, -111.834032),
        c(33.435128, -111.835718), c(33.435141, -111.838668), c(33.435158, -111.840226),
        c(33.43516, -111.84023), c(33.43512, -111.8408), c(33.43511, -111.84169),
        c(33.43509, -111.84311), c(33.43507, -111.84335), c(33.435069, -111.843347),
        c(33.434885, -111.843867), c(33.434685, -111.844119), c(33.434519, -111.844282),
        c(33.433876, -111.844506), c(33.433267, -111.844606), c(33.432682, -111.844651),
        c(33.429912, -111.844773), c(33.429729, -111.844769), c(33.42962, -111.844883),
        c(33.429573, -111.847684), c(33.429504, -111.852084), c(33.429455, -111.856443),
        c(33.429415, -111.861221), c(33.429483, -111.874246), c(33.42947, -111.874944),
        c(33.429466, -111.877446), c(33.429516, -111.877562), c(33.429635, -111.877611),
        c(33.43068, -111.87761)
    ]
}
