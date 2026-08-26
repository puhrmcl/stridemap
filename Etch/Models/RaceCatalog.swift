import Foundation
import CoreLocation

/// A curated library of well-known events — marathons, halves, gran fondos, ultras and summits —
/// so someone who ran a race but never tracked it on a watch can still add it: pick the event,
/// give the date and the finish time, and get a real activity (and a Studio poster) out of it.
///
/// This is a *bundled catalog*, not an integration: there is no marathon API that hands you course
/// geometry, so each entry is curated by hand. What the library supplies is identity, place,
/// official distance and a calendar slot. What it deliberately does **not** supply is an invented
/// route — a course that reroutes yearly is not something to guess on a participant's behalf.
///
/// Routes come from files, in this order of preference:
/// 1. the participant's own GPX/TCX/FIT, which is the line they actually covered;
/// 2. an official course file bundled under `Etch/Resources/Courses` (see `CourseLibrary`);
/// 3. nothing — the activity is honestly route-less until one of the above arrives.
///
/// Adding an official course is a file drop, not a code change, which is what makes filling in a
/// hundred events tractable. `docs/event-library.md` tracks which entries still need one.
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

/// Where an event's drawn route comes from, and how much it can be trusted.
enum CourseSource {
    /// An official or participant-supplied file bundled with the app. Trustworthy.
    case file
    /// Hand-traced from public geography: recognisable in shape, not survey-accurate.
    case traced
    /// No geometry — the participant attaches their own, or the activity carries no route.
    case none

    var isDrawable: Bool { self != .none }
}

struct RaceEvent: Identifiable {
    let id: String
    let name: String
    let city: String
    let state: String?
    let country: String
    var discipline: EventDiscipline = .run
    /// Official distance in metres (a marathon is 42.195 km regardless of a runner's GPS).
    /// For trails and summits this is the commonly-cited round-trip length.
    let distanceMeters: Double
    /// The event's usual calendar slot, used to pre-fill the date and to order the "upcoming" list.
    let typicalMonth: Int
    let typicalDay: Int
    /// The start line or trailhead — approximate, and the only geography most entries carry. It
    /// places the activity on the map and in the right city.
    var start: CLLocationCoordinate2D? = nil
    /// Hand-traced geometry for the handful of events carrying it. A bundled course file always
    /// wins over this.
    var tracedCourse: [CLLocationCoordinate2D] = []

    /// Where this event's route would come from today.
    var courseSource: CourseSource {
        if CourseLibrary.hasCourse(for: id) { return .file }
        return tracedCourse.isEmpty ? .none : .traced
    }

    /// True when the library can draw this event's route without the participant's own file.
    var hasCourse: Bool { courseSource.isDrawable }

    /// The route to draw for a given year — a bundled file first, then the traced fallback.
    func course(for year: Int) -> [CLLocationCoordinate2D] {
        if let bundled = CourseLibrary.course(for: id, year: year) { return bundled.coordinates }
        return tracedCourse
    }

    /// The elevation profile that came with a bundled course file, when it carried one.
    func courseElevations(for year: Int) -> [Double] {
        CourseLibrary.course(for: id, year: year)?.elevations ?? []
    }

    /// "Boston, MA · 26.2 mi" — the picker's supporting line.
    var summary: String {
        let place = [city, state].compactMap { $0 }.joined(separator: ", ")
        return "\(place) · \(Format.distance(distanceMeters, decimals: 1))"
    }

    /// The event's slot in a given year, clamped to a valid day.
    func defaultDate(for year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = typicalMonth
        components.day = typicalDay
        components.hour = 8
        return Calendar.current.date(from: components) ?? Date()
    }

    /// The next time this event comes around — this year's slot if it hasn't passed, else next
    /// year's. Dates are the usual slot, not the published one: an event moves by a week or two.
    func nextOccurrence(after date: Date = Date()) -> Date {
        let year = Calendar.current.component(.year, from: date)
        let thisYear = defaultDate(for: year)
        return thisYear >= date ? thisYear : defaultDate(for: year + 1)
    }

    /// The most recent time it came around — the sensible default when adding a race you ran.
    func lastOccurrence(before date: Date = Date()) -> Date {
        let year = Calendar.current.component(.year, from: date)
        let thisYear = defaultDate(for: year)
        return thisYear <= date ? thisYear : defaultDate(for: year - 1)
    }
}

enum RaceCatalog {

    /// Every curated event. Coordinates are approximate start lines and trailheads; distances are
    /// the nominal published figures. Both are for placing and naming an activity, not measuring
    /// one — the measurement comes from a route file.
    static let events: [RaceEvent] = running + cycling + hiking

    /// Events grouped for the picker, in the order the library presents them.
    static func grouped() -> [(discipline: EventDiscipline, events: [RaceEvent])] {
        EventDiscipline.allCases.compactMap { discipline in
            let matching = events.filter { $0.discipline == discipline }
            return matching.isEmpty ? nil : (discipline, matching)
        }
    }

    /// An event and the next time it comes around.
    struct Upcoming: Identifiable {
        let event: RaceEvent
        let date: Date
        var id: String { event.id }
    }

    /// The events coming around soonest, by their usual calendar slot. This is the library's
    /// answer to "what's next" — it knows nothing about entries or start lists, only the calendar.
    static func upcoming(from date: Date = Date(), limit: Int = 6,
                         discipline: EventDiscipline? = nil) -> [Upcoming] {
        events
            .filter { discipline == nil || $0.discipline == discipline }
            .map { Upcoming(event: $0, date: $0.nextOccurrence(after: date)) }
            .sorted { $0.date < $1.date }
            .prefix(limit)
            .map { $0 }
    }

    static func event(id: String) -> RaceEvent? { events.first { $0.id == id } }

    /// How much of the library can draw its own route — reported by the course-coverage check so
    /// the gap stays visible rather than quietly permanent.
    static func courseCoverage() -> (withCourse: Int, total: Int) {
        (events.filter(\.hasCourse).count, events.count)
    }

    // MARK: - Distances

    private static let marathon = 42_195.0
    private static let half = 21_097.5
    private static let tenK = 10_000.0
    private static let fiftyMiles = 80_467.0
    private static let hundredMiles = 160_934.0

    private static func event(_ id: String, _ name: String, _ city: String, _ state: String?,
                              _ country: String = "United States",
                              _ discipline: EventDiscipline, _ distance: Double,
                              _ month: Int, _ day: Int,
                              _ lat: Double, _ lon: Double,
                              traced: [CLLocationCoordinate2D] = []) -> RaceEvent {
        RaceEvent(id: id, name: name, city: city, state: state, country: country,
                  discipline: discipline, distanceMeters: distance,
                  typicalMonth: month, typicalDay: day,
                  start: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                  tracedCourse: traced)
    }

    private static func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Running

    private static let running: [RaceEvent] = [
        // ── The majors and the traced courses
        event("boston", "Boston Marathon", "Boston", "MA", "United States", .run, marathon, 4, 20, 42.2296, -71.5214,
              traced: [c(42.2296, -71.5214), c(42.2612, -71.4795), c(42.2793, -71.4162), c(42.2836, -71.3487),
                       c(42.2967, -71.2925), c(42.3126, -71.2560), c(42.3300, -71.2124), c(42.3390, -71.1660),
                       c(42.3467, -71.1300), c(42.3499, -71.0784)]),
        event("nyc", "New York City Marathon", "New York", "NY", "United States", .run, marathon, 11, 2, 40.6021, -74.0547,
              traced: [c(40.6021, -74.0547), c(40.6350, -73.9960), c(40.6782, -73.9770), c(40.7180, -73.9580),
                       c(40.7440, -73.9540), c(40.7570, -73.9620), c(40.7810, -73.9490), c(40.8080, -73.9330),
                       c(40.7940, -73.9540), c(40.7690, -73.9760)]),
        event("chicago", "Chicago Marathon", "Chicago", "IL", "United States", .run, marathon, 10, 12, 41.8757, -87.6210,
              traced: [c(41.8757, -87.6210), c(41.8900, -87.6280), c(41.9250, -87.6520), c(41.9100, -87.6650),
                       c(41.8820, -87.6470), c(41.8650, -87.6690), c(41.8480, -87.6660), c(41.8340, -87.6320),
                       c(41.8570, -87.6240), c(41.8757, -87.6205)]),
        // Mesa's course is a real verified GPX, and it lives in Etch/Resources/Courses/mesa.gpx.
        event("mesa", "Mesa Marathon", "Mesa", "AZ", "United States", .run, marathon, 2, 7, 33.4833, -111.6229),
        event("london", "London Marathon", "London", nil, "United Kingdom", .run, marathon, 4, 26, 51.4676, 0.0090),
        event("berlin", "Berlin Marathon", "Berlin", nil, "Germany", .run, marathon, 9, 27, 52.5145, 13.3501),
        event("tokyo", "Tokyo Marathon", "Tokyo", nil, "Japan", .run, marathon, 3, 1, 35.6895, 139.6917),
        event("sydney", "Sydney Marathon", "Sydney", nil, "Australia", .run, marathon, 8, 31, -33.8523, 151.2108),

        // ── International marathons
        event("paris", "Paris Marathon", "Paris", nil, "France", .run, marathon, 4, 12, 48.8738, 2.2950),
        event("amsterdam", "Amsterdam Marathon", "Amsterdam", nil, "Netherlands", .run, marathon, 10, 18, 52.3138, 4.8522),
        event("valencia", "Valencia Marathon", "Valencia", nil, "Spain", .run, marathon, 12, 6, 39.4699, -0.3763),
        event("barcelona", "Barcelona Marathon", "Barcelona", nil, "Spain", .run, marathon, 3, 15, 41.3690, 2.1527),
        event("rome", "Rome Marathon", "Rome", nil, "Italy", .run, marathon, 3, 22, 41.8902, 12.4922),
        event("dublin", "Dublin Marathon", "Dublin", nil, "Ireland", .run, marathon, 10, 26, 53.3498, -6.2603),
        event("copenhagen", "Copenhagen Marathon", "Copenhagen", nil, "Denmark", .run, marathon, 5, 10, 55.6761, 12.5683),
        event("stockholm", "Stockholm Marathon", "Stockholm", nil, "Sweden", .run, marathon, 5, 30, 59.3293, 18.0686),
        event("athens", "Athens Authentic Marathon", "Marathon", nil, "Greece", .run, marathon, 11, 8, 38.1533, 23.9575),
        event("toronto", "Toronto Waterfront Marathon", "Toronto", nil, "Canada", .run, marathon, 10, 18, 43.6532, -79.3832),
        event("cape-town", "Cape Town Marathon", "Cape Town", nil, "South Africa", .run, marathon, 10, 18, -33.9249, 18.4241),

        // ── US marathons
        event("marine-corps", "Marine Corps Marathon", "Arlington", "Virginia", "United States", .run, marathon, 10, 25, 38.8895, -77.0353),
        event("los-angeles", "Los Angeles Marathon", "Los Angeles", "California", "United States", .run, marathon, 3, 8, 34.0669, -118.2437),
        event("big-sur", "Big Sur International Marathon", "Big Sur", "California", "United States", .run, marathon, 4, 26, 36.2704, -121.8081),
        event("grandmas", "Grandma's Marathon", "Duluth", "Minnesota", "United States", .run, marathon, 6, 20, 46.7867, -91.9962),
        event("houston", "Houston Marathon", "Houston", "Texas", "United States", .run, marathon, 1, 18, 29.7523, -95.3595),
        event("philadelphia", "Philadelphia Marathon", "Philadelphia", "Pennsylvania", "United States", .run, marathon, 11, 22, 39.9656, -75.1810),
        event("twin-cities", "Twin Cities Marathon", "Minneapolis", "Minnesota", "United States", .run, marathon, 10, 4, 44.9778, -93.2650),
        event("honolulu", "Honolulu Marathon", "Honolulu", "Hawaii", "United States", .run, marathon, 12, 13, 21.2793, -157.8292),
        event("cim", "California International Marathon", "Folsom", "California", "United States", .run, marathon, 12, 6, 38.6780, -121.1760),
        event("st-george", "St. George Marathon", "St. George", "Utah", "United States", .run, marathon, 10, 3, 37.4136, -113.2394),
        event("eugene", "Eugene Marathon", "Eugene", "Oregon", "United States", .run, marathon, 4, 26, 44.0521, -123.0868),
        event("portland", "Portland Marathon", "Portland", "Oregon", "United States", .run, marathon, 10, 4, 45.5152, -122.6784),
        event("detroit", "Detroit Free Press Marathon", "Detroit", "Michigan", "United States", .run, marathon, 10, 18, 42.3314, -83.0458),
        event("napa-valley", "Napa Valley Marathon", "Calistoga", "California", "United States", .run, marathon, 3, 1, 38.5788, -122.5797),
        event("steamtown", "Steamtown Marathon", "Scranton", "Pennsylvania", "United States", .run, marathon, 10, 11, 41.6484, -75.4685),
        event("disney", "Walt Disney World Marathon", "Orlando", "Florida", "United States", .run, marathon, 1, 11, 28.3852, -81.5639),
        event("rnr-arizona", "Rock 'n' Roll Arizona Marathon", "Phoenix", "Arizona", "United States", .run, marathon, 1, 18, 33.4484, -112.0740),
        event("sedona", "Sedona Marathon", "Sedona", "Arizona", "United States", .run, marathon, 2, 7, 34.8697, -111.7610),
        event("whiskey-row", "Whiskey Row Marathon", "Prescott", "Arizona", "United States", .run, marathon, 5, 2, 34.5400, -112.4685),
        event("revel-mt-charleston", "REVEL Mt. Charleston Marathon", "Las Vegas", "Nevada", "United States", .run, marathon, 4, 25, 36.2560, -115.6480),

        // ── Half marathons
        event("nyc-half", "United Airlines NYC Half", "New York", "New York", "United States", .run, half, 3, 15, 40.6602, -73.9690),
        event("brooklyn-half", "Brooklyn Half", "Brooklyn", "New York", "United States", .run, half, 5, 16, 40.6782, -73.9442),
        event("boston-half", "Boston Half Marathon", "Boston", "Massachusetts", "United States", .run, half, 10, 11, 42.3601, -71.0942),
        event("chicago-half", "Chicago Half Marathon", "Chicago", "Illinois", "United States", .run, half, 9, 27, 41.8570, -87.6120),
        event("philadelphia-half", "Philadelphia Half Marathon", "Philadelphia", "Pennsylvania", "United States", .run, half, 11, 21, 39.9656, -75.1810),
        event("great-north-run", "Great North Run", "Newcastle upon Tyne", nil, "United Kingdom", .run, half, 9, 13, 54.9783, -1.6178),
        event("indy-mini", "500 Festival Mini-Marathon", "Indianapolis", "Indiana", "United States", .run, half, 5, 2, 39.7684, -86.1581),
        event("mesa-half", "Mesa Half Marathon", "Mesa", "Arizona", "United States", .run, half, 2, 7, 33.4370, -111.7710),
        event("rnr-arizona-half", "Rock 'n' Roll Arizona Half", "Phoenix", "Arizona", "United States", .run, half, 1, 18, 33.4484, -112.0740),
        event("rnr-san-diego-half", "Rock 'n' Roll San Diego Half", "San Diego", "California", "United States", .run, half, 6, 7, 32.7157, -117.1611),
        event("rnr-las-vegas-half", "Rock 'n' Roll Las Vegas Half", "Las Vegas", "Nevada", "United States", .run, half, 2, 22, 36.1147, -115.1728),
        event("rnr-nashville-half", "Rock 'n' Roll Nashville Half", "Nashville", "Tennessee", "United States", .run, half, 4, 25, 36.1627, -86.7816),
        event("flying-pig-half", "Flying Pig Half Marathon", "Cincinnati", "Ohio", "United States", .run, half, 5, 3, 39.1031, -84.5120),
        event("disney-princess-half", "Disney Princess Half Marathon", "Orlando", "Florida", "United States", .run, half, 2, 22, 28.3852, -81.5639),
        event("san-francisco-half", "San Francisco Half Marathon", "San Francisco", "California", "United States", .run, half, 7, 26, 37.8080, -122.4177),

        // ── 10K and other road distances
        event("peachtree", "Peachtree Road Race", "Atlanta", "Georgia", "United States", .run, tenK, 7, 4, 33.8121, -84.3963),
        event("bolder-boulder", "BOLDERBoulder 10K", "Boulder", "Colorado", "United States", .run, tenK, 5, 25, 40.0150, -105.2705),
        event("crescent-city", "Crescent City Classic 10K", "New Orleans", "Louisiana", "United States", .run, tenK, 4, 4, 29.9663, -90.0600),
        event("cooper-river", "Cooper River Bridge Run 10K", "Mount Pleasant", "South Carolina", "United States", .run, tenK, 4, 4, 32.8790, -79.9070),
        event("beach-to-beacon", "Beach to Beacon 10K", "Cape Elizabeth", "Maine", "United States", .run, tenK, 8, 1, 43.5620, -70.2030),
        event("monument-avenue", "Monument Avenue 10K", "Richmond", "Virginia", "United States", .run, tenK, 4, 11, 37.5538, -77.4700),
        event("bay-to-breakers", "Bay to Breakers", "San Francisco", "California", "United States", .run, 12_000, 5, 17, 37.7749, -122.4194),
        event("bloomsday", "Lilac Bloomsday 12K", "Spokane", "Washington", "United States", .run, 12_000, 5, 3, 47.6588, -117.4260),
        event("falmouth", "Falmouth Road Race", "Falmouth", "Massachusetts", "United States", .run, 11_265, 8, 16, 41.5623, -70.6389),
        event("cherry-blossom", "Cherry Blossom Ten Mile", "Washington", "District of Columbia", "United States", .run, 16_093, 4, 5, 38.8895, -77.0353),
        event("broad-street", "Broad Street Run", "Philadelphia", "Pennsylvania", "United States", .run, 16_093, 5, 3, 40.0380, -75.1420),
        event("manchester-road-race", "Manchester Road Race", "Manchester", "Connecticut", "United States", .run, 7_641, 11, 26, 41.7759, -72.5215),
        event("carlsbad-5000", "Carlsbad 5000", "Carlsbad", "California", "United States", .run, 5_000, 4, 5, 33.1581, -117.3506),

        // ── Ultras and trail
        event("western-states", "Western States 100", "Olympic Valley", "California", "United States", .run, hundredMiles, 6, 27, 39.1968, -120.2357),
        event("leadville-100", "Leadville Trail 100 Run", "Leadville", "Colorado", "United States", .run, hundredMiles, 8, 15, 39.2508, -106.2925),
        event("hardrock", "Hardrock 100", "Silverton", "Colorado", "United States", .run, hundredMiles, 7, 10, 37.8119, -107.6645),
        event("javelina-jundred", "Javelina Jundred", "Fountain Hills", "Arizona", "United States", .run, hundredMiles, 10, 24, 33.6870, -111.7010),
        event("black-canyon-100k", "Black Canyon Ultras 100K", "Mayer", "Arizona", "United States", .run, 100_000, 2, 14, 34.3980, -112.2380),
        event("cocodona-250", "Cocodona 250", "Black Canyon City", "Arizona", "United States", .run, 402_336, 5, 4, 34.0700, -112.1500),
        event("utmb", "UTMB Mont-Blanc", "Chamonix", nil, "France", .run, 171_000, 8, 28, 45.9237, 6.8694),
        event("badwater", "Badwater 135", "Death Valley", "California", "United States", .run, 217_262, 7, 6, 36.2300, -116.7660),
        event("jfk-50", "JFK 50 Mile", "Boonsboro", "Maryland", "United States", .run, fiftyMiles, 11, 21, 39.4143, -77.7311),
        event("comrades", "Comrades Marathon", "Pietermaritzburg", nil, "South Africa", .run, 89_000, 6, 14, -29.6006, 30.3794),
        event("two-oceans", "Two Oceans Marathon", "Cape Town", nil, "South Africa", .run, 56_000, 4, 18, -33.9628, 18.4700),
        event("pikes-peak-ascent", "Pikes Peak Ascent", "Manitou Springs", "Colorado", "United States", .run, 21_726, 9, 19, 38.8597, -104.9172),
        event("pikes-peak-marathon", "Pikes Peak Marathon", "Manitou Springs", "Colorado", "United States", .run, 42_195, 9, 20, 38.8597, -104.9172)
    ]

    // MARK: - Cycling

    private static let cycling: [RaceEvent] = [
        event("unbound-gravel", "Unbound Gravel 200", "Emporia", "Kansas", "United States", .ride, 321_869, 5, 30, 38.4039, -96.1817),
        event("sbt-grvl", "SBT GRVL", "Steamboat Springs", "Colorado", "United States", .ride, 232_000, 8, 16, 40.4850, -106.8317),
        event("belgian-waffle-ride", "Belgian Waffle Ride San Diego", "San Marcos", "California", "United States", .ride, 209_215, 4, 26, 33.1434, -117.1661),
        event("barry-roubaix", "Barry-Roubaix", "Hastings", "Michigan", "United States", .ride, 100_000, 3, 28, 42.6467, -85.2900),
        event("rebecca-private-idaho", "Rebecca's Private Idaho", "Ketchum", "Idaho", "United States", .ride, 160_934, 8, 30, 43.6805, -114.3637),
        event("crusher-in-the-tushar", "Crusher in the Tushar", "Beaver", "Utah", "United States", .ride, 111_045, 7, 11, 38.2766, -112.6410),
        event("leadville-100-mtb", "Leadville Trail 100 MTB", "Leadville", "Colorado", "United States", .ride, hundredMiles, 8, 8, 39.2508, -106.2925),
        event("el-tour-tucson", "El Tour de Tucson", "Tucson", "Arizona", "United States", .ride, hundredMiles, 11, 21, 32.2226, -110.9747),
        event("triple-bypass", "Triple Bypass", "Evergreen", "Colorado", "United States", .ride, 193_121, 7, 11, 39.6333, -105.3172),
        event("levis-granfondo", "Levi's GranFondo", "Santa Rosa", "California", "United States", .ride, hundredMiles, 10, 3, 38.4405, -122.7141),
        event("gfny", "Gran Fondo New York", "Fort Lee", "New Jersey", "United States", .ride, hundredMiles, 5, 17, 40.8509, -73.9701),
        event("gran-fondo-hincapie", "Gran Fondo Hincapie", "Greenville", "South Carolina", "United States", .ride, 130_000, 10, 24, 34.8526, -82.3940),
        event("hotter-n-hell", "Hotter'N Hell Hundred", "Wichita Falls", "Texas", "United States", .ride, hundredMiles, 8, 29, 33.9137, -98.4934),
        event("mt-washington-hillclimb", "Mt. Washington Auto Road Hillclimb", "Gorham", "New Hampshire", "United States", .ride, 12_231, 8, 15, 44.2619, -71.2536),
        event("mt-evans-hillclimb", "Mount Evans Hill Climb", "Idaho Springs", "Colorado", "United States", .ride, 45_000, 7, 25, 39.7425, -105.5136),
        event("assault-mt-mitchell", "Assault on Mt. Mitchell", "Spartanburg", "South Carolina", "United States", .ride, 164_154, 5, 18, 34.9496, -81.9320),
        event("etape-du-tour", "L'Étape du Tour", "Alpe d'Huez", nil, "France", .ride, 145_000, 7, 12, 45.0902, 6.0703),
        event("la-marmotte", "La Marmotte", "Le Bourg-d'Oisans", nil, "France", .ride, 174_000, 7, 4, 45.0553, 6.0300),
        event("maratona-dles-dolomites", "Maratona dles Dolomites", "La Villa", nil, "Italy", .ride, 138_000, 7, 5, 46.5470, 11.8830),
        event("whistler-gran-fondo", "RBC GranFondo Whistler", "Vancouver", nil, "Canada", .ride, 122_000, 9, 12, 49.2827, -123.1207)
    ]

    // MARK: - Hikes and summits

    private static let hiking: [RaceEvent] = [
        // ── Arizona
        event("camelback", "Camelback Mountain (Echo Canyon)", "Phoenix", "Arizona", "United States", .hike, 4_023, 3, 15, 33.5225, -111.9631),
        event("piestewa-peak", "Piestewa Peak (Summit Trail)", "Phoenix", "Arizona", "United States", .hike, 3_219, 3, 15, 33.5450, -112.0230),
        event("south-mountain-national", "South Mountain (National Trail)", "Phoenix", "Arizona", "United States", .hike, 12_875, 2, 15, 33.3400, -112.0700),
        event("flatiron", "Flatiron (Siphon Draw)", "Apache Junction", "Arizona", "United States", .hike, 8_690, 2, 15, 33.4520, -111.4790),
        event("four-peaks-brown", "Four Peaks (Brown's Peak)", "Payson", "Arizona", "United States", .hike, 14_484, 4, 15, 33.6800, -111.3300),
        event("humphreys-peak", "Humphreys Peak", "Flagstaff", "Arizona", "United States", .hike, 16_898, 8, 15, 35.3464, -111.6780),
        event("cathedral-rock", "Cathedral Rock", "Sedona", "Arizona", "United States", .hike, 1_931, 3, 15, 34.8200, -111.7920),
        event("devils-bridge", "Devil's Bridge", "Sedona", "Arizona", "United States", .hike, 6_759, 3, 15, 34.9020, -111.8140),
        event("west-fork-oak-creek", "West Fork of Oak Creek", "Sedona", "Arizona", "United States", .hike, 10_460, 10, 15, 34.9930, -111.7440),
        event("picacho-peak", "Picacho Peak (Hunter Trail)", "Picacho", "Arizona", "United States", .hike, 5_150, 2, 15, 32.6440, -111.4000),
        event("havasu-falls", "Havasu Falls", "Supai", "Arizona", "United States", .hike, 32_187, 5, 15, 36.1580, -112.7080),
        event("bright-angel", "Bright Angel Trail", "Grand Canyon", "Arizona", "United States", .hike, 30_578, 4, 15, 36.0574, -112.1436),
        event("rim-to-rim", "Grand Canyon Rim to Rim", "Grand Canyon", "Arizona", "United States", .hike, 38_624, 10, 10, 36.0544, -112.1401),

        // ── The West
        event("half-dome", "Half Dome", "Yosemite National Park", "California", "United States", .hike, 22_530, 7, 15, 37.7459, -119.5332),
        event("mount-whitney", "Mount Whitney", "Lone Pine", "California", "United States", .hike, 35_405, 8, 1, 36.5865, -118.2920),
        event("mount-shasta", "Mount Shasta (Avalanche Gulch)", "Mount Shasta", "California", "United States", .hike, 18_000, 6, 15, 41.3530, -122.2320),
        event("angels-landing", "Angels Landing", "Zion National Park", "Utah", "United States", .hike, 8_690, 5, 15, 37.2690, -112.9469),
        event("the-narrows", "The Narrows", "Zion National Park", "Utah", "United States", .hike, 15_127, 6, 15, 37.2982, -112.9481),
        event("delicate-arch", "Delicate Arch", "Moab", "Utah", "United States", .hike, 4_828, 4, 15, 38.7360, -109.5200),
        event("mount-timpanogos", "Mount Timpanogos", "American Fork", "Utah", "United States", .hike, 22_531, 8, 15, 40.4050, -111.6380),
        event("longs-peak", "Longs Peak", "Estes Park", "Colorado", "United States", .hike, 24_140, 8, 1, 40.2549, -105.6151),
        event("mount-elbert", "Mount Elbert", "Leadville", "Colorado", "United States", .hike, 15_288, 8, 1, 39.1178, -106.4453),
        event("quandary-peak", "Quandary Peak", "Breckenridge", "Colorado", "United States", .hike, 10_621, 8, 1, 39.3970, -106.0640),
        event("grays-torreys", "Grays and Torreys Peaks", "Georgetown", "Colorado", "United States", .hike, 13_679, 8, 1, 39.6600, -105.7700),
        event("mount-rainier-muir", "Mount Rainier (Camp Muir)", "Ashford", "Washington", "United States", .hike, 14_484, 7, 15, 46.7860, -121.7350),
        event("mount-si", "Mount Si", "North Bend", "Washington", "United States", .hike, 12_875, 6, 15, 47.4879, -121.7230),
        event("mount-st-helens", "Mount St. Helens (Monitor Ridge)", "Cougar", "Washington", "United States", .hike, 16_093, 7, 15, 46.1470, -122.1830),
        event("the-enchantments", "The Enchantments", "Leavenworth", "Washington", "United States", .hike, 29_000, 9, 15, 47.5560, -120.8250),
        event("mount-hood", "Mount Hood (Timberline)", "Government Camp", "Oregon", "United States", .hike, 12_875, 5, 15, 45.3311, -121.7110),
        event("kalalau", "Kalalau Trail", "Kauai", "Hawaii", "United States", .hike, 35_405, 5, 15, 22.2199, -159.5828),

        // ── The East
        event("mount-katahdin", "Mount Katahdin", "Millinocket", "Maine", "United States", .hike, 16_093, 9, 1, 45.9044, -68.9216),
        event("cadillac-north-ridge", "Cadillac Mountain (North Ridge)", "Bar Harbor", "Maine", "United States", .hike, 7_242, 8, 15, 44.3720, -68.2270),
        event("mount-washington", "Mount Washington (Tuckerman Ravine)", "Gorham", "New Hampshire", "United States", .hike, 13_518, 7, 15, 44.2571, -71.3033),
        event("mount-marcy", "Mount Marcy", "Lake Placid", "New York", "United States", .hike, 24_945, 8, 15, 44.1830, -73.9640),
        event("old-rag", "Old Rag Mountain", "Sperryville", "Virginia", "United States", .hike, 14_726, 5, 15, 38.5700, -78.2870),
        event("mount-mitchell", "Mount Mitchell", "Burnsville", "North Carolina", "United States", .hike, 9_656, 6, 15, 35.7650, -82.2650),
        event("guadalupe-peak", "Guadalupe Peak", "Salt Flat", "Texas", "United States", .hike, 13_679, 3, 15, 31.8910, -104.8280),

        // ── International
        event("mount-fuji", "Mount Fuji (Yoshida Trail)", "Fujiyoshida", nil, "Japan", .hike, 15_000, 8, 1, 35.3900, 138.7300),
        event("kilimanjaro", "Kilimanjaro (Machame Route)", "Moshi", nil, "Tanzania", .hike, 62_000, 8, 1, -3.1330, 37.2660),
        event("everest-base-camp", "Everest Base Camp Trek", "Lukla", nil, "Nepal", .hike, 130_000, 10, 15, 27.8060, 86.7130),
        event("ben-nevis", "Ben Nevis", "Fort William", nil, "United Kingdom", .hike, 17_000, 7, 15, 56.7969, -5.0037),
        event("snowdon", "Snowdon (Llanberis Path)", "Llanberis", nil, "United Kingdom", .hike, 14_484, 7, 15, 53.1200, -4.1280),
        event("table-mountain", "Table Mountain (Platteklip Gorge)", "Cape Town", nil, "South Africa", .hike, 5_472, 2, 15, -33.9550, 18.4050),
        event("tongariro", "Tongariro Alpine Crossing", "Tongariro", nil, "New Zealand", .hike, 19_400, 2, 15, -39.1330, 175.6200),
        event("roys-peak", "Roys Peak", "Wanaka", nil, "New Zealand", .hike, 16_000, 2, 15, -44.6480, 169.0700)
    ]

    // MARK: - Building a Run from a chosen event

    /// Creates the activity for a library entry with everything the participant recorded about it.
    /// A route they attached themselves always wins over the library's course — it's the line they
    /// actually covered.
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
        let elevations = attached.isEmpty ? event.courseElevations(for: year) : attachedElevations
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
            elevationGain: RouteMetrics.elevationGain(of: elevations),
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
        if !elevations.isEmpty { run.elevationSeries = elevations }
        if !attachedPaces.isEmpty { run.paceSeries = attachedPaces }
        // Without geometry the activity is honestly route-less: the detail page then offers to
        // place it on the map or import the participant's file.
        run.routeStatus = coordinates.isEmpty ? .unavailable : .available
        run.routeSource = .imported
        return run
    }
}
