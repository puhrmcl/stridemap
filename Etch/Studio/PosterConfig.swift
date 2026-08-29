import SwiftUI

/// The two Etch Studio products. A *Map* poster leads with the route over a real map (or a bare
/// line); a *Gallery* poster arranges photos, the map, the route, and the elevation into a curated
/// art layout. Everything else — colours, type, data — is customised the same way in both.
enum PosterFamily: String, CaseIterable, Identifiable {
    case map, gallery
    var id: String { rawValue }
    var name: String { self == .map ? "Map" : "Gallery" }
    var icon: String { self == .map ? "map" : "square.grid.2x2" }
}

/// The base map behind a Map poster's route. `none` drops the map entirely — just the route line on
/// the poster's ground, the most restrained look. Each maps onto a curated `StudioEdition` so the
/// existing render pipeline draws it.
enum MapStyle: String, CaseIterable, Identifiable {
    case standard, streets, terrain, satellite, dark, streetsNoir, harbor, contour, midnight, none
    var id: String { rawValue }
    var name: String {
        switch self {
        case .standard:  return "Standard"
        case .streets:   return "Streets"
        case .terrain:   return "Terrain"
        case .satellite: return "Satellite"
        case .dark:      return "Dark"
        case .streetsNoir: return "Streets Noir"
        case .harbor:    return "Harbor"
        case .contour:   return "Trail Journal"
        case .midnight:  return "Midnight Atlas"
        case .none:      return "No Map"
        }
    }
    var icon: String {
        switch self {
        case .standard:  return "map"
        case .streets:   return "road.lanes"
        case .terrain:   return "mountain.2"
        case .satellite: return "globe.americas.fill"
        case .dark:      return "moon.stars"
        case .streetsNoir: return "road.lanes.curved.right"
        case .harbor:    return "water.waves"
        case .contour:   return "square.stack.3d.down.right"
        case .midnight:  return "sparkles"
        case .none:      return "scribble.variable"
        }
    }
    /// True for the two contour styles, which trace real terrain rather than snapshotting a map —
    /// the most distinctive art Studio can make, and the slowest, since it needs elevation data.
    var isContour: Bool { self == .contour || self == .midnight }
    /// The edition that renders this base map (defaults, before user colour overrides).
    var edition: StudioEdition {
        switch self {
        case .standard:  return .atlas
        case .streets:   return .streets
        case .terrain:   return .terrain
        case .satellite: return .satellite
        case .dark:      return .atlasDark
        case .streetsNoir: return .streetsNoir
        case .harbor:    return .harbor
        case .contour:   return .trailJournal
        case .midnight:  return .midnightAtlas
        case .none:      return .minimal
        }
    }
}

/// A Map poster's layout — how the area beneath the map is composed. `statement` is the full
/// editorial footer (title, big headline, place, data, date); `minimal` reduces it to just the
/// title and date under the map; `photo` fills the data area with 1–3 photos; `fullBleed` runs
/// the map edge to edge with the type set over it and the data anchored in the corners.
enum MapLayout: String, CaseIterable, Identifiable {
    /// Nameplate leads the list because it is the one most people want and the one the category
    /// has settled on: the place named large at the top, the map beneath it, the numbers in a row
    /// along the foot. Statement is the older Etch arrangement, which makes the distance the hero
    /// and sets the name above it as a caption — a piece about a number rather than about a place.
    case nameplate, statement, minimal, photo, fullBleed
    var id: String { rawValue }
    var name: String {
        switch self {
        case .nameplate: return "Nameplate"
        case .statement: return "Statement"
        case .minimal:   return "Minimal"
        case .photo:     return "Photo"
        case .fullBleed: return "Full Bleed"
        }
    }
    var icon: String {
        switch self {
        case .nameplate: return "textformat.size.larger"
        case .statement: return "doc.richtext"
        case .minimal:   return "textformat"
        case .photo:     return "photo.on.rectangle"
        case .fullBleed: return "rectangle.inset.filled"
        }
    }
}

/// A curated Title typeface — three faces, no font zoo: an editorial serif, the app's modern
/// rounded face, and a wide poster sans. Applied to the title (and echoed on the location line).
enum PosterFont: String, CaseIterable, Identifiable {
    case editorial, modern, poster
    var id: String { rawValue }
    var name: String {
        switch self {
        case .editorial: return "Editorial"
        case .modern:    return "Modern"
        case .poster:    return "Poster"
        }
    }
    var design: Font.Design {
        switch self {
        case .editorial: return .serif
        case .modern:    return .rounded
        case .poster:    return .default
        }
    }
    var titleWeight: Font.Weight {
        switch self {
        case .editorial: return .regular
        case .modern:    return .semibold
        case .poster:    return .heavy
        }
    }
    /// Extra letter-spacing layered on the base title tracking, so each face sits at its natural
    /// rhythm (a serif wants air; a heavy sans wants less).
    var extraTracking: CGFloat {
        switch self {
        case .editorial: return 3
        case .modern:    return 0
        case .poster:    return 2
        }
    }
    /// A preview string in the picker rendered in the face itself.
    var sample: String { "Aa" }
}

/// The five curated Gallery art layouts. Each arranges a set of *frames* (photo / map / route /
/// elevation) beneath a masthead. The frame count is fixed per design; the user picks what media
/// each frame shows.
enum GalleryDesign: String, CaseIterable, Identifiable {
    case portfolio, duo, triptych, grid, feature
    var id: String { rawValue }
    var name: String {
        switch self {
        case .portfolio: return "Portfolio"
        case .duo:       return "Duo"
        case .triptych:  return "Triptych"
        case .grid:      return "Grid"
        case .feature:   return "Feature"
        }
    }
    /// A small glyph that evokes the arrangement in the picker.
    var icon: String {
        switch self {
        case .portfolio: return "rectangle.portrait"
        case .duo:       return "rectangle.split.2x1"
        case .triptych:  return "rectangle.split.3x1"
        case .grid:      return "square.grid.2x2"
        case .feature:   return "rectangle.grid.1x2"
        }
    }
    /// How many media frames this design lays out.
    var frameCount: Int {
        switch self {
        case .portfolio: return 1
        case .duo:       return 2
        case .triptych:  return 3
        case .grid:      return 4
        case .feature:   return 4
        }
    }
}

/// The full editable recipe for a poster — the single source of truth the editor binds to, the
/// renderer reads from, and a `SavedPoster` persists. Value type so the editor can diff it for
/// re-renders and copy it in and out of storage cleanly.
struct PosterConfig {
    var family: PosterFamily = .map
    var mapStyle: MapStyle = .standard
    /// Map product: how the sheet is composed. Nameplate is the default — a new poster should open
    /// on the arrangement most people are going to want, and a piece named for its place is that.
    /// A poster saved before this keeps whatever it was saved with; only new ones change.
    var mapLayout: MapLayout = .nameplate
    /// Map Photo layout: how many photos to show (1–3).
    var mapPhotoCount: Int = 1
    /// Poster text size multiplier (0.85 = Small … 1.3 = XL). 1 = the designed size. Applies to
    /// every text element, multiplied by the per-element scales below.
    var textScale: CGFloat = 1
    /// Per-element size multipliers, so each piece of type can be dialled independently of the
    /// global size: the three text lines, the big headline block, and the data rows.
    var titleScale: CGFloat = 1
    var locationScale: CGFloat = 1
    var dateScale: CGFloat = 1
    var heroScale: CGFloat = 1
    var statScale: CGFloat = 1
    var galleryDesign: GalleryDesign = .portfolio
    /// Media shown in each Gallery frame, in order. Trimmed/padded to the design's frame count.
    var galleryFrames: [GalleryTileKind] = [.photo, .map, .route, .elevation]
    /// Which of the run's photos fills each Gallery frame (parallel to `galleryFrames`; -1 or
    /// missing = automatic order — the k-th photo frame shows the k-th photo).
    var galleryPhotoPicks: [Int] = []
    var monochrome: Bool = false
    var orientation: StudioOrientation = .portrait
    var dataPlacement: StudioDataPlacement = .right
    var font: PosterFont = .editorial
    var showTitle: Bool = true
    /// Title override; empty falls back to the run's name.
    var title: String = ""
    var showLocation: Bool = true
    /// Location override; empty falls back to the run's city/state.
    var location: String = ""
    var showDate: Bool = true
    /// Date override; empty falls back to the run's date.
    var date: String = ""
    /// The big headline metric (distance by default) — chosen from the same set as the slots.
    var heroMetric: StatMetric = .distance
    /// 0–4 "complication" slots shown beneath the headline.
    var dataSlots: [StatMetric] = [.time, .pace, .elevationGain]
    /// Whether the small caption labels under data values (TIME, PACE — and the headline's unit)
    /// are drawn. Off gives the bare-numbers minimal look.
    var showStatLabels: Bool = true
    var showElevation: Bool = false
    var showPace: Bool = false
    var includeWeather: Bool = false
    var photoLayout: StudioPhotoLayout = .single
    var routeColor: Color?
    var textColor: Color?
    var groundColor: Color?
    var outputSize: StudioOutputSize = .poster

    // MARK: Derived

    /// The edition that supplies presentation defaults for the current product.
    var edition: StudioEdition {
        family == .gallery ? .gallery : mapStyle.edition
    }

    var layout: StudioLayout {
        family == .gallery ? .gallery : .classic
    }

    /// Frames trimmed/padded to the current design's frame count.
    var resolvedFrames: [GalleryTileKind] {
        let n = galleryDesign.frameCount
        var frames = galleryFrames
        // Seed missing frames with sensible defaults (photo, then map, route, elevation).
        let seeds: [GalleryTileKind] = [.photo, .map, .route, .elevation]
        while frames.count < n { frames.append(seeds[min(frames.count, seeds.count - 1)]) }
        return Array(frames.prefix(n))
    }

    /// Photo picks trimmed/padded to the current design's frame count (-1 = automatic).
    var resolvedPhotoPicks: [Int] {
        let n = galleryDesign.frameCount
        var picks = galleryPhotoPicks
        while picks.count < n { picks.append(-1) }
        return Array(picks.prefix(n))
    }

    /// The render request for a run, threading every option (including the ones the renderer
    /// gained for the remodel) through to the composition.
    func request(for run: Run) -> StudioRenderer.Request {
        var r = StudioRenderer.Request(
            run: run, edition: edition, layout: layout,
            orientation: orientation, dataPlacement: dataPlacement, photoLayout: photoLayout,
            titleOverride: title.isEmpty ? nil : title,
            dateOverride: date.isEmpty ? nil : date,
            heroMetric: heroMetric, statSlots: dataSlots,
            showStatLabels: showStatLabels,
            showElevationProfile: showElevation,
            galleryCellsRaw: resolvedFrames.map(\.rawValue),
            includeWeather: includeWeather,
            routeColor: routeColor, textColor: textColor, groundColor: groundColor,
            outputSize: outputSize
        )
        r.monochrome = monochrome
        r.titleFont = font
        r.showTitle = showTitle
        r.showLocation = showLocation
        r.showDate = showDate
        r.locationOverride = location.isEmpty ? nil : location
        r.galleryDesignRaw = galleryDesign.rawValue
        r.galleryPhotoPicks = resolvedPhotoPicks
        r.mapLayoutRaw = mapLayout.rawValue
        r.mapPhotoCount = mapPhotoCount
        r.showPaceProfile = showPace
        r.textScale = textScale
        r.titleScale = titleScale
        r.locationScale = locationScale
        r.dateScale = dateScale
        r.heroScale = heroScale
        r.statScale = statScale
        return r
    }

    // MARK: Persistence

    /// Copy this recipe into a stored poster.
    func write(into p: SavedPoster, run: Run) {
        p.runName = run.name
        p.familyRaw = family.rawValue
        p.mapStyleRaw = mapStyle.rawValue
        p.mapLayoutRaw = mapLayout.rawValue
        p.mapPhotoCount = mapPhotoCount
        p.textScale = Double(textScale)
        p.titleScale = Double(titleScale)
        p.locationScale = Double(locationScale)
        p.dateScale = Double(dateScale)
        p.heroScale = Double(heroScale)
        p.statScale = Double(statScale)
        p.galleryDesignRaw = galleryDesign.rawValue
        p.galleryFramesRaw = galleryFrames.map(\.rawValue)
        p.galleryPhotoPicks = galleryPhotoPicks
        p.monochrome = monochrome
        p.orientationRaw = orientation.rawValue
        p.dataPlacementRaw = dataPlacement.rawValue
        p.photoLayoutRaw = photoLayout.rawValue
        p.fontRaw = font.rawValue
        p.showTitle = showTitle
        p.customTitle = title
        p.showLocation = showLocation
        p.locationText = location
        p.showDate = showDate
        p.customDate = date
        p.statSlotsRaw = dataSlots.map(\.rawValue)
        p.heroMetricRaw = heroMetric.rawValue
        p.showStatLabels = showStatLabels
        p.showElevationProfile = showElevation
        p.showPaceProfile = showPace
        p.includeWeather = includeWeather
        p.routeColorHex = routeColor?.hexString
        p.textColorHex = textColor?.hexString
        p.groundColorHex = groundColor?.hexString
        // Legacy mirror so anything still reading the old fields stays coherent.
        p.editionRaw = edition.id.rawValue
        p.layoutRaw = layout.rawValue
        p.showEditorialPhoto = false
        p.showMemoryRoute = false
        p.updatedAt = Date()
    }

    /// A fresh recipe for a run. Four elements by default — title, place, date, one hero metric —
    /// and nothing else: the route and the memory are the hero, and a first-open poster should
    /// read as designed wall art, not an activity-stat dashboard. Time/pace/elevation are one
    /// stepper away in the Data tab for the athlete who wants them.
    static func makeDefault(for run: Run) -> PosterConfig {
        var c = PosterConfig()
        // Three figures, as peers, along the foot.
        //
        // The old default was one metric and nothing else, because the old default layout blew
        // that one metric up into a headline and three of those would have been a dashboard.
        // Nameplate sets them small and quiet under a rule, where three reads as a record of a day
        // and one reads as an unfinished row.
        c.dataSlots = [.elevationGain, .time]
        // Gallery frames lead with a photograph, which is right until the run has none — then
        // Portfolio (a single frame) opened on an empty sheet and the product looked broken
        // rather than unfilled. With no photos the frames lead with the map, and the photograph
        // moves to the back of the queue where it fills in the moment one is added.
        if run.photoReferences.isEmpty {
            c.galleryFrames = [.map, .route, .elevation, .photo]
        }
        return c
    }

    /// Reads a stored poster into a recipe. New posters carry the remodel fields directly; posters
    /// saved under the old 10-edition system (no `familyRaw`) are migrated to the closest new setup.
    init(poster p: SavedPoster) {
        if p.familyRaw.isEmpty {
            self = PosterConfig.migrated(from: p)
            return
        }
        family = PosterFamily(rawValue: p.familyRaw) ?? .map
        mapStyle = MapStyle(rawValue: p.mapStyleRaw) ?? .standard
        mapLayout = MapLayout(rawValue: p.mapLayoutRaw) ?? .statement
        mapPhotoCount = max(1, min(3, p.mapPhotoCount))
        textScale = p.textScale > 0 ? CGFloat(p.textScale) : 1
        titleScale = p.titleScale > 0 ? CGFloat(p.titleScale) : 1
        locationScale = p.locationScale > 0 ? CGFloat(p.locationScale) : 1
        dateScale = p.dateScale > 0 ? CGFloat(p.dateScale) : 1
        heroScale = p.heroScale > 0 ? CGFloat(p.heroScale) : 1
        statScale = p.statScale > 0 ? CGFloat(p.statScale) : 1
        galleryDesign = GalleryDesign(rawValue: p.galleryDesignRaw) ?? .portfolio
        galleryFrames = p.galleryFramesRaw.compactMap { GalleryTileKind(rawValue: $0) }
        if galleryFrames.isEmpty { galleryFrames = [.photo, .map, .route, .elevation] }
        galleryPhotoPicks = p.galleryPhotoPicks
        monochrome = p.monochrome
        orientation = StudioOrientation(rawValue: p.orientationRaw) ?? .portrait
        dataPlacement = StudioDataPlacement.from(raw: p.dataPlacementRaw)
        photoLayout = StudioPhotoLayout(rawValue: p.photoLayoutRaw) ?? .single
        font = PosterFont(rawValue: p.fontRaw) ?? .editorial
        showTitle = p.showTitle
        title = p.customTitle
        showLocation = p.showLocation
        location = p.locationText
        showDate = p.showDate
        date = p.customDate
        heroMetric = StatMetric(rawValue: p.heroMetricRaw) ?? .distance
        let slots = p.statSlotsRaw.compactMap { StatMetric(rawValue: $0) }
        dataSlots = slots
        showStatLabels = p.showStatLabels
        showElevation = p.showElevationProfile
        showPace = p.showPaceProfile
        includeWeather = p.includeWeather
        routeColor = Color(hex: p.routeColorHex)
        textColor = Color(hex: p.textColorHex)
        groundColor = Color(hex: p.groundColorHex)
    }

    private init() {}

    /// Maps a legacy edition + layout onto the nearest new product setup, so an old saved poster
    /// keeps rendering (just through the new model).
    private static func migrated(from p: SavedPoster) -> PosterConfig {
        var c = PosterConfig()
        c.orientation = StudioOrientation(rawValue: p.orientationRaw) ?? .portrait
        c.dataPlacement = StudioDataPlacement.from(raw: p.dataPlacementRaw)
        c.heroMetric = StatMetric(rawValue: p.heroMetricRaw) ?? .distance
        c.photoLayout = StudioPhotoLayout(rawValue: p.photoLayoutRaw) ?? .single
        c.title = p.customTitle
        c.date = p.customDate
        c.showElevation = p.showElevationProfile
        c.includeWeather = p.includeWeather
        c.routeColor = Color(hex: p.routeColorHex)
        c.textColor = Color(hex: p.textColorHex)
        c.groundColor = Color(hex: p.groundColorHex)
        let slots = p.statSlotsRaw.compactMap { StatMetric(rawValue: $0) }
        if !slots.isEmpty { c.dataSlots = slots }

        let edition = StudioEdition.ID(rawValue: p.editionRaw) ?? .gallery
        let wasGallery = p.layoutRaw == "gallery"
        let wasPhoto = edition == .memory

        if wasGallery || wasPhoto {
            c.family = .gallery
            c.galleryFrames = wasPhoto ? [.photo, .route, .elevation, .map] : [.photo, .map, .route, .elevation]
            c.galleryDesign = wasPhoto ? .portfolio : .triptych
        } else {
            c.family = .map
            switch edition {
            case .satellite:            c.mapStyle = .satellite
            case .terrain:              c.mapStyle = .terrain
            case .trailJournal:         c.mapStyle = .contour
            case .midnightAtlas:        c.mapStyle = .midnight
            case .atlasDark, .night:    c.mapStyle = .dark
            case .minimal:              c.mapStyle = .none
            default:                    c.mapStyle = .standard
            }
        }
        return c
    }
}
