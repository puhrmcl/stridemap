import SwiftUI
import MapKit

/// Read-only catalog browsing: previewing an event never inserts an activity or changes a result.
struct EventLibraryOverview: View {
    let event: RaceEvent
    let year: Int
    var expanded = false
    @State private var showDetail = false
    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var courseLabel = "Loading course…"
    @State private var loaded = false
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.name).font(.etch(expanded ? .largeTitle : .title2, weight: .bold))
            mapPreview
            Label(courseLabel, systemImage: coordinates.count > 1 ? "point.topleft.down.to.point.bottomright.curvepath" : "mappin")
                .font(.etch(.caption)).foregroundStyle(.secondary)
            HStack {
                Label(event.discipline.title, systemImage: event.discipline.icon)
                Spacer()
                Text(Format.distance(event.distanceMeters, decimals: 1)).monospacedDigit()
            }.font(.etch(.subheadline, weight: .semibold))
            Text([event.city, event.state, event.country].compactMap { $0 }.joined(separator: ", "))
                .font(.etch(.subheadline)).foregroundStyle(.secondary)
            Text(event.libraryDescription).font(.etch(.body))
                .fixedSize(horizontal: false, vertical: true)
            if let summit = event.summitLabel {
                Label("Summit · \(summit)", systemImage: "mountain.2")
                    .font(.etch(.subheadline))
            }
            if let url = event.officialSite {
                Link(destination: url) {
                    Label("Official event website", systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44)
                }
                if let signup = event.registrationSite {
                    Link(destination: signup) {
                        Label("Registration & entry details", systemImage: "ticket")
                            .frame(minHeight: 44)
                    }
                }
                Text("Check the organizer’s site for current dates, course changes and entry availability.")
                    .font(.etch(.caption)).foregroundStyle(.secondary)
            }
            if !expanded {
                Button { showDetail = true } label: {
                    Label("Explore event & course", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(minHeight: 44)
                }
            }
        }
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                ScrollView {
                    EventLibraryOverview(event: event, year: year, expanded: true).padding(20)
                }
                .navigationTitle("Event details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showDetail = false } } }
            }
        }
        .task(id: "\(event.id)-\(year)") { loadCourse() }
    }

    private var mapPreview: some View {
        Map(position: $position, interactionModes: expanded ? .all : []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                if let first = coordinates.first { Marker("Course start", coordinate: first).tint(Theme.accent) }
                if let last = coordinates.last { Marker("Course finish", coordinate: last).tint(.orange) }
            } else if let start = event.start {
                Marker("Approximate event location", coordinate: start).tint(Theme.accent)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: expanded ? 340 : 210)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            if !loaded { ProgressView().padding(12).background(.regularMaterial, in: .capsule) }
        }
        .accessibilityLabel(coordinates.count > 1 ? "Course preview for \(event.name)" : "Event location for \(event.name)")
    }

    private func loadCourse() {
        loaded = false
        let bundled = CourseLibrary.course(for: event.id, year: year)
        let raw = bundled?.coordinates ?? event.tracedCourse
        coordinates = raw.filter { CLLocationCoordinate2DIsValid($0) }
        if coordinates.count > 1 {
            courseLabel = bundled == nil ? "Approximate traced course · may differ by year" : "Library course · confirm the route for your event year"
            position = .automatic
        } else {
            courseLabel = "Course not available · showing approximate event location"
            if let start = event.start {
                position = .region(MKCoordinateRegion(center: start,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))
            } else {
                position = .automatic
                courseLabel = "Course and location not available"
            }
        }
        loaded = true
    }
}

extension RaceEvent {
    var libraryDescription: String {
        switch id {
        case "mesa", "mesa-half":
            return "A road-running event in Mesa, Arizona, known for downhill courses and desert scenery. The event weekend includes multiple distances."
        case "boston":
            return "A historic road marathon from Hopkinton to Boston. Explore the course and check the Boston Athletic Association’s entry and qualification information."
        case "nyc":
            return "New York Road Runners’ flagship marathon, linking New York City’s five boroughs in one city-wide race."
        case "london":
            return "A major road marathon through London. The organizer’s site explains entry routes, including the ballot and charity places."
        default:
            let place = [city, state].compactMap { $0 }.joined(separator: ", ")
            return "\(name) is a \(discipline.title.lowercased()) entry in Etch’s library for \(place), \(country). The catalog distance is \(Format.distance(distanceMeters, decimals: 1)). Use the course preview to explore the route before adding your own activity details."
        }
    }

    // Verified against organizer websites on 2026-09-13; omit unknown URLs rather than guess.
    var officialSite: URL? {
        let address: String
        switch id {
        case "mesa", "mesa-half": address = "https://mesamarathon.com/"
        case "boston": address = "https://www.baa.org/races/boston-marathon/"
        case "boston-half": address = "https://www.baa.org/races/boston-half/"
        case "chicago": address = "https://www.chicagomarathon.com/"
        case "nyc": address = "https://www.nyrr.org/tcsnycmarathon"
        case "london": address = "https://www.londonmarathonevents.co.uk/london-marathon"
        case "rnr-san-diego-half": address = "https://www.runrocknroll.com/events/san-diego"
        default: return nil
        }
        return URL(string: address)
    }

    var registrationSite: URL? {
        switch id {
        case "mesa", "mesa-half": return URL(string: "https://mesamarathon.com/register")
        case "chicago": return URL(string: "https://www.chicagomarathon.com/apply/")
        default: return nil
        }
    }
}

/// Browsing an event opens its detail before changing the add form's selection.
struct EventLibraryBrowser: View {
    let year: Int
    let onSelect: (RaceEvent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ event: RaceEvent) -> Bool {
        searchText.isEmpty || "\(event.name) \(event.city) \(event.state ?? "") \(event.country)"
            .localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(RaceCatalog.grouped(), id: \.discipline) { group in
                    let events = group.events.filter { matches($0) }
                    if !events.isEmpty {
                        Section(group.discipline.title) {
                            ForEach(events) { event in
                                NavigationLink {
                                    EventLibrarySelection(event: event, year: year, onSelect: onSelect)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(event.name, systemImage: event.discipline.icon)
                                        Text(event.summary).font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 6)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Event or place")
            .overlay {
                if !RaceCatalog.events.contains(where: { matches($0) }) {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Event library")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct EventLibrarySelection: View {
    let event: RaceEvent
    let year: Int
    let onSelect: (RaceEvent) -> Void

    var body: some View {
        ScrollView {
            EventLibraryOverview(event: event, year: year, expanded: true).padding(20)
        }
        .navigationTitle("Event details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { onSelect(event) } label: {
                Text("Use this event").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.regularMaterial)
        }
    }
}
