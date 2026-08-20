import Foundation
import SwiftData
import SwiftUI

/// A poster the user composed in Etch Studio and chose to keep. It stores only the *recipe* —
/// which run, which edition, and every customization — never the pixels, so the artwork always
/// re-renders at full quality (and follows the run if its photos or route later change).
///
/// Reopening a saved poster restores the exact composition the user left, so Studio becomes a
/// place your finished pieces live, not just a one-shot export flow.
@Model
final class SavedPoster {

    @Attribute(.unique) var id: UUID

    /// The run this poster was composed from (matched to a `Run.id`).
    var runID: UUID
    /// The run's name at save time — a stable label if the run is ever unavailable.
    var runName: String

    var createdAt: Date
    var updatedAt: Date

    // MARK: Composition recipe (mirrors StudioView's state)

    var editionRaw: String
    var layoutRaw: String
    var orientationRaw: String
    var dataPlacementRaw: String
    var photoLayoutRaw: String
    var customTitle: String
    var customDate: String
    var heroMetricRaw: String
    var statSlotsRaw: [String]
    var showEditorialPhoto: Bool
    var showMemoryRoute: Bool
    var showElevationProfile: Bool
    var includeWeather: Bool
    /// Hex (#RRGGBB) of the user's colour picks; nil means "Auto" — the edition's own colour.
    var routeColorHex: String?
    var textColorHex: String?
    var groundColorHex: String?

    // MARK: Remodel recipe (Map / Gallery products)
    //
    // Added in the Studio remodel. Existing posters saved before the remodel have `familyRaw`
    // empty; `PosterConfig(poster:)` detects that and migrates them to the closest new setup, so
    // these defaults are only ever read for genuinely new posters.

    /// "map" or "gallery". Empty on pre-remodel posters (triggers migration).
    var familyRaw: String = ""
    var mapStyleRaw: String = "standard"
    var galleryDesignRaw: String = "portfolio"
    var galleryFramesRaw: [String] = []
    var monochrome: Bool = false
    var fontRaw: String = "editorial"
    var showTitle: Bool = true
    var showLocation: Bool = true
    /// Location override; empty falls back to the run's city/state.
    var locationText: String = ""

    /// A bare poster for a run; `PosterConfig.write(into:run:)` fills in the recipe.
    convenience init(runID: UUID, runName: String) {
        self.init(
            runID: runID, runName: runName,
            editionRaw: StudioEdition.ID.gallery.rawValue, layoutRaw: StudioLayout.classic.rawValue,
            orientationRaw: StudioOrientation.portrait.rawValue,
            dataPlacementRaw: StudioDataPlacement.side.rawValue,
            photoLayoutRaw: StudioPhotoLayout.single.rawValue,
            customTitle: "", customDate: "",
            heroMetricRaw: StatMetric.distance.rawValue, statSlotsRaw: [],
            showEditorialPhoto: false, showMemoryRoute: false,
            showElevationProfile: false, includeWeather: false,
            routeColorHex: nil, textColorHex: nil, groundColorHex: nil
        )
        self.familyRaw = PosterFamily.map.rawValue
    }

    init(
        id: UUID = UUID(),
        runID: UUID,
        runName: String,
        editionRaw: String,
        layoutRaw: String,
        orientationRaw: String,
        dataPlacementRaw: String,
        photoLayoutRaw: String,
        customTitle: String,
        customDate: String,
        heroMetricRaw: String,
        statSlotsRaw: [String],
        showEditorialPhoto: Bool,
        showMemoryRoute: Bool,
        showElevationProfile: Bool,
        includeWeather: Bool,
        routeColorHex: String?,
        textColorHex: String?,
        groundColorHex: String?
    ) {
        self.id = id
        self.runID = runID
        self.runName = runName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.editionRaw = editionRaw
        self.layoutRaw = layoutRaw
        self.orientationRaw = orientationRaw
        self.dataPlacementRaw = dataPlacementRaw
        self.photoLayoutRaw = photoLayoutRaw
        self.customTitle = customTitle
        self.customDate = customDate
        self.heroMetricRaw = heroMetricRaw
        self.statSlotsRaw = statSlotsRaw
        self.showEditorialPhoto = showEditorialPhoto
        self.showMemoryRoute = showMemoryRoute
        self.showElevationProfile = showElevationProfile
        self.includeWeather = includeWeather
        self.routeColorHex = routeColorHex
        self.textColorHex = textColorHex
        self.groundColorHex = groundColorHex
    }

    var editionID: StudioEdition.ID { StudioEdition.ID(rawValue: editionRaw) ?? .gallery }
}

extension Color {
    /// `#RRGGBB` for persistence. Resolved through UIColor so any Color (brand token or a custom
    /// ColorPicker pick) round-trips. Opacity is dropped — poster colours are always opaque.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// Rebuilds a Color from `hexString`. Nil in, nil out (the "Auto" case).
    init?(hex: String?) {
        guard let hex else { return nil }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
