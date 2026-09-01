import SwiftUI
import CoreLocation

/// One finished piece proposed for an activity: a complete recipe, named, ready to buy as-is.
struct StudioPick: Identifiable {
    let id: String
    let name: String
    /// One editorial line — what the piece is, never a spec.
    let line: String
    let config: PosterConfig
}

/// Chooses finished pieces for an activity — the design work the customer should never have to do.
///
/// Studio opened on a question ("What are we making?") when it should open on an answer. The
/// authored editions, the layout system and the print pipeline already exist; what was missing is
/// the merchandiser standing between them and the customer, reading the activity and putting the
/// right three or four pieces on the table. That is this file: pure functions from a `Run` to a
/// short list of complete `PosterConfig`s.
///
/// The reading order is the activity's, not the catalogue's. A marathon leads with the navy-and-
/// gold marathon print; a summit leads with the contour journals; an ordinary Tuesday run leads
/// with the house piece. Every pick carries data slots chosen for its discipline and an
/// orientation chosen from the route's own geometry, so the first render is the finished design —
/// customization is refinement, not assembly.
enum StudioCurator {

    static func picks(for run: Run) -> [StudioPick] {
        let orientation = bestOrientation(for: run)
        var picks: [StudioPick] = []

        func add(_ id: String, _ name: String, _ line: String,
                 _ build: (inout PosterConfig) -> Void) {
            var c = PosterConfig.makeDefault(for: run)
            c.orientation = orientation
            c.heroMetric = .distance
            c.dataSlots = dataSlots(for: run)
            build(&c)
            picks.append(StudioPick(id: id, name: name, line: line, config: c))
        }

        /// A map piece in an edition's authored colours — the designer's version of that
        /// edition, not a Look's approximation of it.
        func edition(_ id: String, _ name: String, _ line: String, style: MapStyle,
                     layout: MapLayout = .nameplate) {
            add(id, name, line) { c in
                c.family = .map
                c.mapStyle = style
                c.mapLayout = layout
                let e = style.edition
                c.groundColor = e.ground
                c.textColor = e.ink
                c.routeColor = e.route
                c.monochrome = false
            }
        }

        switch leadKind(for: run) {
        case .race:
            edition("harbor", "Harbor",
                    "The race in deep navy, the route in gold — the marathon print.",
                    style: .harbor)
            edition("gallery", "Gallery",
                    "A muted map on gallery paper, the route in Etch Blue.", style: .streets)
            edition("noir", "Noir",
                    "Faint streets on near-black, the route in white.", style: .streetsNoir)
        case .summit:
            edition("trail", "Trail Journal",
                    "Terrain contours on aged paper, the route inked over.", style: .contour)
            edition("midnight", "Midnight Atlas",
                    "Gold contours across deep ink, the route aglow.", style: .midnight)
            edition("gallery", "Gallery",
                    "A muted map on gallery paper, the route in Etch Blue.", style: .streets)
        case .everyday:
            edition("gallery", "Gallery",
                    "A muted map on gallery paper, the route in Etch Blue.", style: .streets)
            edition("noir", "Noir",
                    "Faint streets on near-black, the route in white.", style: .streetsNoir)
            edition("harbor", "Harbor",
                    "The city in deep navy, the route in gold.", style: .harbor)
        }

        if !run.photoReferences.isEmpty {
            add("memory", "Memory",
                "Your photographs from the day, composed with the route.") { c in
                c.family = .gallery
                c.galleryDesign = run.photoReferences.count >= 2 ? .triptych : .portfolio
                c.galleryFrames = [.photo, .map, .route, .elevation]
            }
        }

        edition("line", "Line",
                "Just the route and the type. Nothing else.", style: .none, layout: .minimal)

        return picks
    }

    // MARK: What the activity is

    private enum LeadKind { case race, summit, everyday }

    /// A summit is a hike, or anything that climbed like one. The threshold is generous on
    /// purpose: the contour journals only *lead* here — they remain one card among five for
    /// everything else.
    private static func leadKind(for run: Run) -> LeadKind {
        if run.isRace { return .race }
        if run.activityType == .hike { return .summit }
        if run.elevationGain > 450 { return .summit }   // ~1,500 ft — a real climb, any discipline
        return .everyday
    }

    /// Data rows chosen for the discipline: a race is a result, a summit is a climb, a ride is
    /// speed. Three at most — a record of a day, not a dashboard.
    private static func dataSlots(for run: Run) -> [StatMetric] {
        if run.isRace {
            var slots: [StatMetric] = [.time, .pace]
            // `.finish` is the finishing position; `.place` is the location, which the
            // composition already names above the row.
            if !run.finishPlace.isEmpty { slots.append(.finish) }
            return slots
        }
        switch run.activityType {
        case .hike:  return [.elevationGain, .time]
        case .ride:  return [.time, .speed]
        default:     return [.time, .elevationGain]
        }
    }

    // MARK: Composition from geometry

    /// Portrait unless the route itself argues otherwise. The bounding box is compared in
    /// Mercator-corrected spans, and only a decisively wide route (an east–west point-to-point,
    /// a coastline ride) flips the sheet — a loop stays portrait, which is what a wall wants.
    static func bestOrientation(for run: Run) -> StudioOrientation {
        let spanLat = run.maxLatitude - run.minLatitude
        let spanLon = run.maxLongitude - run.minLongitude
        guard spanLat > 0, spanLon > 0 else { return .portrait }
        let midLat = (run.maxLatitude + run.minLatitude) / 2
        let width = spanLon * cos(midLat * .pi / 180)
        guard width / spanLat > 1.8 else { return .portrait }
        return .landscape
    }
}
