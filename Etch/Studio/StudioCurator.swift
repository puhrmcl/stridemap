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
            // A Nameplate always composes masthead → art → foot, whatever the data placement says.
            // In landscape the default `.right` placement would therefore size the sheet for a
            // square-art-plus-column print it never draws. Landscape Nameplates take the wide
            // canvas, with the data beneath the art — which is also exactly what a landscape Race
            // Edition has to be.
            if c.orientation == .landscape, c.family == .map, c.mapLayout == .nameplate {
                c.dataPlacement = .bottom
            }
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
            // Race Edition is an authored product, not a generic map with race data poured into it.
            // It used to force portrait so the collection kept one silhouette on the wall — but a
            // wide point-to-point course drawn on a 2:3 sheet spends two thirds of the art panel on
            // empty ground either side of a thin line, which is a worse object than a matched pair.
            // The course chooses the sheet now, like every other piece; the finish time is still
            // the headline, and the data still sits beneath the art in both orientations.
            func raceEdition(_ id: String, _ name: String, _ line: String, style: MapStyle) {
                add(id, name, line) { c in
                    c.family = .map
                    c.mapStyle = style
                    c.mapLayout = .nameplate
                    c.heroMetric = .time
                    c.dataSlots = [.distance, .pace] + (run.finishPlace.isEmpty ? [] : [.finish])
                    c.showStatLabels = true
                    c.font = .editorial
                    c.dataFont = .modern
                    c.mapInset = true
                    let e = style.edition
                    c.groundColor = e.ground
                    c.textColor = e.ink
                    c.routeColor = e.route
                    c.monochrome = false
                }
            }

            raceEdition("race-gallery", "Race Edition",
                        "Gallery paper, Etch Blue course — the definitive record of race day.",
                        style: .streets)
            raceEdition("race-harbor", "Race Edition · Harbor",
                        "Deep navy and brass — a darker commemorative edition.",
                        style: .harbor)
            raceEdition("race-minimal", "Race Edition · Minimal",
                        "Only the course, result and type. Nothing else.",
                        style: .none)
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

    /// How many times wider than tall this route actually is on the ground.
    ///
    /// Read from the activity's stored bounding box — four `Double`s already on the model — so this
    /// is arithmetic, not analysis: no route walk, no snapshot, nothing that would make asking the
    /// question expensive enough to cache.
    ///
    /// The longitude span is corrected for latitude because a degree of longitude narrows as you
    /// leave the equator. Without it the same loop reads half again as wide in Reykjavík as in
    /// Quito, and the sheet would be chosen by where the run happened rather than by its shape.
    ///
    /// - Returns: the corrected width : height ratio, or `nil` when the bounds are missing or
    ///   degenerate — an activity with no route, or one that never moved east or west.
    static func routeAspect(for run: Run) -> Double? {
        let spanLat = run.maxLatitude - run.minLatitude
        let spanLon = run.maxLongitude - run.minLongitude
        guard spanLat >= 0, spanLon > 0 else { return nil }
        let midLat = (run.maxLatitude + run.minLatitude) / 2
        let width = spanLon * cos(midLat * .pi / 180)
        guard width > 0 else { return nil }
        // A route with no north–south extent at all is as wide as a route gets. Real GPS never
        // produces it, but a hand-authored or single-latitude course can, and dividing by zero to
        // find that out would hand the sheet an orientation of `nan`.
        guard spanLat > 0 else { return .infinity }
        return width / spanLat
    }

    /// Where a route stops being a shape that suits a portrait sheet and starts being one that
    /// needs a landscape one.
    ///
    /// The previous value was 1.8, which in practice meant almost nothing flipped: a genuinely
    /// wide point-to-point marathon measures around 1.6–1.9 corrected, so half of them stayed on a
    /// portrait sheet with the course squeezed into the middle third of the art panel. Rendered
    /// against the seeded courses, 1.5 is the point where the map visibly starts wasting the sheet
    /// in portrait — comfortably above a loop (which lands near 1.0–1.2) and below an out-and-back
    /// that still reads well upright.
    static let landscapeAspectThreshold: Double = 1.5

    /// Portrait unless the route itself argues otherwise.
    ///
    /// Portrait is the default answer, and it is the answer for every case the geometry cannot
    /// speak to: a loop, a tall north–south route, an activity with no usable bounds at all. Only a
    /// decisively wide route — an east–west point-to-point, a coastline ride — turns the sheet.
    static func bestOrientation(for run: Run) -> StudioOrientation {
        guard let aspect = routeAspect(for: run) else { return .portrait }
        return aspect >= landscapeAspectThreshold ? .landscape : .portrait
    }
}
