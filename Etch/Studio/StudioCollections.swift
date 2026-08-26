import SwiftUI
import CoreLocation

/// The Etch Studio collections — curated, editorial groupings of the pieces a user's own history
/// can already make, modelled on how a design house structures a line (and how Fifty-Nine Parks
/// sells: finished editions, not configurators).
///
/// Three collections ship here:
/// - **The Course Collection** — the user's races, presented as finisher pieces.
/// - **The Summit Collection** — climbs and bucket-list trails, in the contour editions.
/// - **The Archive Collection** — the body of work as one object (Grid / Constellation / Bloom),
///   each style offered only when the user's data will render it well.
///
/// ## Licensing (why artwork titles are "BOSTON 26.2", not "Boston Marathon")
/// Selling commemorative merchandise bearing a race's name is exactly what *BAA v. Sullivan*
/// (1st Cir. 1989) found infringing, and IRONMAN®/70.3® are enforced at least as hard. So:
/// - **App-authored artwork never defaults to a third-party event mark.** The default poster title
///   is the city + the distance figure ("BOSTON 26.2", "MESA 13.1") — facts, in the house style.
/// - Official event names stay in the *in-app UI* (matching, lists, detail) as factual reference,
///   which is ordinary nominative use — the line we do not cross is printing the mark on goods.
/// - If the user types an event name into the title field themselves, that is their own text on
///   their own object; the app just doesn't put it there for them.
/// - Trail, summit and park names are geographic facts and safe to print; the NPS arrowhead and
///   event logos are not, and nothing here renders any logo.
enum StudioCollection: String, CaseIterable, Identifiable {
    case course, summit, archive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .course:  return "The Course Collection"
        case .summit:  return "The Summit Collection"
        case .archive: return "The Archive Collection"
        }
    }

    /// The editorial line — what the collection *is*, in the brand's voice.
    var descriptor: String {
        switch self {
        case .course:  return "The races you finished, as finisher pieces — the course, the city, your time."
        case .summit:  return "The climbs that earned a wall — contour lines, elevation, brass."
        case .archive: return "Everything you've ever run, as one object."
        }
    }

    /// The eyebrow accent: blue signals activity, brass is reserved for achievement, stone for the
    /// archive's quiet record-keeping.
    var accent: Color {
        switch self {
        case .course:  return Theme.Palette.blueBright
        case .summit:  return Theme.Palette.brass
        case .archive: return Theme.Palette.stone
        }
    }

    var symbol: String {
        switch self {
        case .course:  return "flag.checkered"
        case .summit:  return "mountain.2"
        case .archive: return "square.grid.3x3"
        }
    }
}

/// One curated piece: an activity plus the preset that opens Studio already looking finished.
struct CollectionPiece: Identifiable {
    let run: Run
    let preset: PosterConfig
    /// A short curatorial subtitle ("Angels Landing · Zion", "Finisher · 2022").
    let subtitle: String
    var id: UUID { run.id }
}

enum StudioCollections {

    // MARK: The Course Collection

    /// The user's races, newest first, each preset as a finisher piece: classic Atlas map, the
    /// finish time as the hero metric, the licensing-safe title.
    static func courses(in runs: [Run]) -> [CollectionPiece] {
        runs.filter(\.isRace)
            .sorted { $0.startDate > $1.startDate }
            .map { run in
                let year = Calendar.current.component(.year, from: run.startDate)
                return CollectionPiece(run: run, preset: coursePreset(for: run),
                                       subtitle: "Finisher · \(year)")
            }
    }

    /// The finisher-piece recipe: classic Atlas map, the finish time as the hero, the
    /// licensing-safe title. Shared by the collection browser and the run-detail moment card.
    static func coursePreset(for run: Run) -> PosterConfig {
        var preset = PosterConfig.makeDefault(for: run)
        preset.mapStyle = .standard
        preset.font = .editorial
        preset.heroMetric = .time
        preset.dataSlots = [.distance, .pace]
        preset.title = artworkTitle(for: run)
        return preset
    }

    /// The licensing-safe default artwork title: CITY + the distance figure. "BOSTON 26.2" says
    /// everything the finisher needs said, in facts.
    static func artworkTitle(for run: Run) -> String {
        let place = (run.city?.isEmpty == false ? run.city! : run.name)
        return "\(place.uppercased()) \(distanceFigure(run.distance))"
    }

    /// The figure runners actually say: 26.2, 13.1, 10K, 5K — else the formatted distance.
    static func distanceFigure(_ meters: Double) -> String {
        switch meters {
        case 41_600...43_000:   return "26.2"
        case 20_800...21_500:   return "13.1"
        case 9_600...10_400:    return "10K"
        case 4_800...5_300:     return "5K"
        case 159_000...163_000: return "100"
        default:                return Format.distance(meters)
        }
    }

    // MARK: The Summit Collection

    /// A bucket-list trail the collection recognises by geography. Names are geographic facts —
    /// the safe half of the licensing line. Coordinates are trailheads/summits, matched loosely.
    struct IconicSummit {
        let name: String
        let park: String
        let coordinate: CLLocationCoordinate2D
    }

    /// Curated from what people actually chase (permit lotteries are the tell): the hikes that top
    /// every list and already have finisher culture with no premium personal-route product.
    static let iconicSummits: [IconicSummit] = [
        IconicSummit(name: "Half Dome", park: "Yosemite",
                     coordinate: CLLocationCoordinate2D(latitude: 37.7459, longitude: -119.5332)),
        IconicSummit(name: "Angels Landing", park: "Zion",
                     coordinate: CLLocationCoordinate2D(latitude: 37.2690, longitude: -112.9469)),
        IconicSummit(name: "Rim to Rim", park: "Grand Canyon",
                     coordinate: CLLocationCoordinate2D(latitude: 36.0544, longitude: -112.1401)),
        IconicSummit(name: "Delicate Arch", park: "Arches",
                     coordinate: CLLocationCoordinate2D(latitude: 38.7436, longitude: -109.4993)),
        IconicSummit(name: "Old Rag", park: "Shenandoah",
                     coordinate: CLLocationCoordinate2D(latitude: 38.5514, longitude: -78.3161)),
        IconicSummit(name: "Emerald Lake", park: "Rocky Mountain",
                     coordinate: CLLocationCoordinate2D(latitude: 40.3095, longitude: -105.6455)),
        IconicSummit(name: "Camelback Mountain", park: "Phoenix",
                     coordinate: CLLocationCoordinate2D(latitude: 33.5151, longitude: -111.9619)),
        IconicSummit(name: "Highline Trail", park: "Glacier",
                     coordinate: CLLocationCoordinate2D(latitude: 48.6967, longitude: -113.7183))
    ]

    /// Genuine climbing, in metres of gain — below this a hike is a walk, not a summit piece.
    static let summitGainFloor: Double = 120

    /// The user's summit-worthy activities: hikes with real elevation gain, or anything matched to
    /// an iconic trail. Iconic matches lead; the rest rank by climb. Preset: Midnight Atlas — gold
    /// contours on ink, the elevation profile on, the gain as the hero.
    static func summits(in runs: [Run]) -> [CollectionPiece] {
        let candidates = runs.filter { run in
            let isHikeLike = run.activityType == .hike || run.isTrail
            return (isHikeLike && run.elevationGain >= summitGainFloor) || iconicSummit(for: run) != nil
        }
        return candidates
            .map { run -> (Run, IconicSummit?) in (run, iconicSummit(for: run)) }
            .sorted { a, b in
                if (a.1 != nil) != (b.1 != nil) { return a.1 != nil }
                return a.0.elevationGain > b.0.elevationGain
            }
            .map { run, iconic in
                let subtitle = iconic.map { "\($0.name) · \($0.park)" }
                    ?? "\(Format.elevationGain(run.elevationGain)) of climb"
                return CollectionPiece(run: run, preset: summitPreset(for: run, iconic: iconic),
                                       subtitle: subtitle)
            }
    }

    /// The summit-piece recipe: Midnight Atlas — gold contours on ink — the elevation profile on,
    /// the climb as the hero. Shared by the collection browser and the run-detail moment card.
    static func summitPreset(for run: Run, iconic: IconicSummit?) -> PosterConfig {
        var preset = PosterConfig.makeDefault(for: run)
        preset.mapStyle = .midnight
        preset.font = .editorial
        preset.heroMetric = .elevationGain
        preset.dataSlots = [.distance, .time]
        preset.showElevation = true
        if let iconic { preset.title = iconic.name.uppercased() }
        return preset
    }

    /// The iconic trail this activity belongs to, if its start sits within ~20 km of one.
    static func iconicSummit(for run: Run) -> IconicSummit? {
        guard let lat = run.startLatitude, let lon = run.startLongitude else { return nil }
        let start = CLLocation(latitude: lat, longitude: lon)
        return iconicSummits.first {
            start.distance(from: CLLocation(latitude: $0.coordinate.latitude,
                                            longitude: $0.coordinate.longitude)) < 20_000
        }
    }

    // MARK: The Archive Collection

    /// The wall-art styles this user's data will render *well* — the gate is the curation. A grid
    /// of twelve glyphs looks unfinished; a constellation of one city is a blob; a bloom needs
    /// volume to read as a form. Home Turf is deliberately not offered here: the heat-tangle is
    /// the most commodity look in the market, the opposite of what the Archive is for.
    /// Thresholds come from the served configuration (compiled defaults when there's none), so
    /// they can be tuned against real histories without an App Store release — they're guesses
    /// until users prove otherwise.
    static func archiveStyles(for runs: [Run]) -> [MapArtStyle] {
        let gates = EtchConfig.current.archive
        let routed = runs.filter(\.hasRoute)
        var styles: [MapArtStyle] = []
        if routed.count >= gates.gridMinRoutedRuns { styles.append(.grid) }
        // Ridgeline needs recorded elevation profiles; Rings and Pulse need only dates and
        // distances, so they open the Archive to treadmill-heavy histories too.
        if runs.filter({ $0.elevationSeries.count > 4 }).count >= gates.ridgelineMinProfiles {
            styles.append(.ridgeline)
        }
        if runs.count >= gates.ringsMinRuns { styles.append(.rings) }
        if runs.count >= gates.pulseMinRuns { styles.append(.pulse) }
        if geographicCells(of: runs) >= gates.constellationMinCells { styles.append(.constellation) }
        if routed.count >= gates.bloomMinRoutedRuns { styles.append(.bloom) }
        return styles
    }

    /// Distinct ~1° map cells the user's activities start in — a cheap measure of geographic
    /// spread (≈100 km cells; 4+ means the constellation has a shape, not a dot).
    static func geographicCells(of runs: [Run]) -> Int {
        var cells = Set<String>()
        for run in runs {
            guard let lat = run.startLatitude, let lon = run.startLongitude else { continue }
            cells.insert("\(Int(lat.rounded()))|\(Int(lon.rounded()))")
        }
        return cells.count
    }
}

// MARK: - Browser

/// The inside of one collection: the user's qualifying pieces, each opening Studio (or Wall Art)
/// on its authored preset. Curation over configuration — every row is already a finished look.
struct CollectionBrowserView: View {
    let collection: StudioCollection
    let runs: [Run]

    @Environment(\.dismiss) private var dismiss
    @State private var pick: CollectionPiece?
    @State private var archivePick: MapArtStyle?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if collection == .archive {
                        archiveList
                    } else {
                        pieceList
                    }
                }
                .padding(20)
            }
            .navigationTitle(collection.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $pick) { piece in
                StudioView(run: piece.run, preset: piece.preset)
            }
            .sheet(item: $archivePick) { style in
                MapPrintView(runs: runs, kind: .artMap, artStyle: style)
            }
        }
    }

    private var header: some View {
        Text(collection.descriptor)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pieces: [CollectionPiece] {
        collection == .course ? StudioCollections.courses(in: runs)
                              : StudioCollections.summits(in: runs)
    }

    private var pieceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                if index > 0 { Divider().padding(.leading, 76) }
                Button { pick = piece } label: { pieceRow(piece) }
                    .buttonStyle(.plain)
            }
        }
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 18))
    }

    private func pieceRow(_ piece: CollectionPiece) -> some View {
        HStack(spacing: 14) {
            RouteThumbnail(run: piece.run)
                .frame(width: 54, height: 54)
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(piece.run.displayName)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(piece.subtitle)
                    .font(.caption)
                    .foregroundStyle(collection.accent)
                Text(Format.dateTime(piece.run.startDate))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .contentShape(.rect)
    }

    /// The Archive's rows are styles, not runs — each is the whole history rendered one way,
    /// led by a live thumbnail of *this* user's data in that style (a text row asked the buyer
    /// to imagine the product; the thumbnail is the product).
    @State private var archiveThumbs: [MapArtStyle: UIImage] = [:]
    @State private var showYearBook = false

    private var archiveList: some View {
        VStack(spacing: 0) {
            let styles = StudioCollections.archiveStyles(for: runs)
            ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
                if index > 0 { Divider().padding(.leading, 20) }
                Button { archivePick = style } label: {
                    HStack(spacing: 14) {
                        archiveThumbnail(style)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(style.name)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Text(style.descriptor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            // The Archive's other object: the whole year as a layflat hardcover.
            Divider().padding(.leading, 20)
            Button { showYearBook = true } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.Palette.bone)
                        .frame(width: 56, height: 84)
                        .overlay {
                            Image(systemName: "book.pages")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("The Year Book")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("A year of it, bound — layflat hardcover, composed from your months and races.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showYearBook) { YearBookView() }
        }
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 18))
        .task(id: runs.count) { await renderArchiveThumbnails() }
    }

    @ViewBuilder private func archiveThumbnail(_ style: MapArtStyle) -> some View {
        Group {
            if let image = archiveThumbs[style] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.Palette.bone
            }
        }
        .frame(width: 56, height: 84)
        .clipShape(.rect(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    /// Renders each offered style's poster at thumbnail scale — the user's own history, not a
    /// stock sample. Sequential, cached for the sheet's lifetime.
    private func renderArchiveThumbnails() async {
        guard collection == .archive else { return }
        for style in StudioCollections.archiveStyles(for: runs) where archiveThumbs[style] == nil {
            if Task.isCancelled { return }
            var request = MapPrintRequest.make(kind: .artMap, runs: runs)
            request.artStyle = style
            if style == .homeTurf, let region = MapPrintRequest.homeTurfRegion(runs: runs) {
                request.region = region
            }
            if let image = await MapPrintRenderer.image(for: request, scale: 0.14) {
                archiveThumbs[style] = image
            }
        }
    }
}
