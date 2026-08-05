import MapKit

/// An `MKPolyline` that carries the metadata needed to style and hit-test a run route.
final class RunPolyline: MKPolyline {
    /// The unified run identity this overlay represents.
    var runID: UUID = UUID()
    /// 0 (today) → 1 (oldest run in the set). Drives colour + opacity.
    var ageFraction: Double = 0
    /// Highlighted when the run is selected or emphasised by the active mode.
    var emphasised: Bool = false
    var isSelected: Bool = false
}

/// Camera instruction handed to the map. Carries an id so SwiftUI re-applies it even
/// when the same conceptual target is requested twice.
struct MapCameraCommand: Equatable {
    enum Target: Equatable {
        case fit(runIDs: [UUID])
        case focus(runID: UUID)
        case region(latitude: Double, longitude: Double, spanDegrees: Double)
    }
    var id = UUID()
    var target: Target
}
