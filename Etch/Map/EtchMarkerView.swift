import MapKit
import UIKit

/// The Etch place marker: a circular Ink chip with the run count, and the place name hung
/// quietly beneath it. Replaces the default Apple teardrop so the map reads as Etch, not as
/// navigation. Ink for the resting state; Etch Blue is reserved for selection so the blue
/// stays a signal, not decoration.
final class EtchMarkerView: MKAnnotationView {
    static let reuseID = "etchMarker"

    private let disc = UIView()
    private let countLabel = UILabel()
    private let nameLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear

        disc.layer.borderColor = UIColor(Theme.Palette.bone).withAlphaComponent(0.9).cgColor
        disc.layer.borderWidth = 1.5
        disc.layer.shadowColor = UIColor.black.cgColor
        disc.layer.shadowOpacity = 0.22
        disc.layer.shadowRadius = 3
        disc.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(disc)

        countLabel.textColor = UIColor(Theme.Palette.bone)
        countLabel.textAlignment = .center
        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        countLabel.adjustsFontSizeToFitWidth = true
        countLabel.minimumScaleFactor = 0.6
        disc.addSubview(countLabel)

        nameLabel.textAlignment = .center
        nameLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.textColor = UIColor(Theme.Palette.bone)
        // A soft dark halo keeps the name legible over any map ground.
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowOpacity = 0.6
        nameLabel.layer.shadowRadius = 2
        nameLabel.layer.shadowOffset = .zero

        addSubview(nameLabel)

        canShowCallout = false
        clusteringIdentifier = nil
        displayPriority = .required
        collisionMode = .circle
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Sizes and colours the chip. `name` nil/empty hides the label (clusters). `selected`
    /// switches the disc to Etch Blue.
    func configure(count: Int, name: String?, selected: Bool = false) {
        let diameter: CGFloat = 34
        disc.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        disc.layer.cornerRadius = diameter / 2
        disc.backgroundColor = UIColor(selected ? Theme.Palette.blue : Theme.Palette.ink)
            .withAlphaComponent(0.95)
        countLabel.frame = disc.bounds
        countLabel.text = "\(count)"

        let hasName = (name?.isEmpty == false)
        nameLabel.text = name
        nameLabel.isHidden = !hasName
        let nameHeight: CGFloat = hasName ? 15 : 0
        let gap: CGFloat = hasName ? 3 : 0
        let width: CGFloat = 132
        let totalHeight = diameter + gap + nameHeight

        bounds = CGRect(x: 0, y: 0, width: width, height: totalHeight)
        disc.center = CGPoint(x: width / 2, y: diameter / 2)
        if hasName {
            nameLabel.frame = CGRect(x: 0, y: diameter + gap, width: width, height: nameHeight)
        }
        // Anchor the disc's centre on the coordinate; the name hangs below the point.
        centerOffset = CGPoint(x: 0, y: (totalHeight - diameter) / 2)
    }
}

/// A world-spanning tonal wash drawn above the base map (below annotations) so geography
/// recedes to an archival tone and the Etch markers/routes are the only high-contrast thing.
enum MapWash {
    /// A world-covering polygon to add as an overlay, above labels, so it tones tiles + labels
    /// while the annotation markers (always drawn above overlays) stay crisp.
    static func makeOverlay() -> MKPolygon {
        let rect = MKMapRect.world
        let corners = [
            MKMapPoint(x: rect.minX, y: rect.minY),
            MKMapPoint(x: rect.maxX, y: rect.minY),
            MKMapPoint(x: rect.maxX, y: rect.maxY),
            MKMapPoint(x: rect.minX, y: rect.maxY)
        ].map(\.coordinate)
        return MKPolygon(coordinates: corners, count: corners.count)
    }

    /// A translucent Bone (light) / Ink (dark) fill, resolved to the map's current appearance.
    static func renderer(for polygon: MKPolygon) -> MKPolygonRenderer {
        let renderer = MKPolygonRenderer(polygon: polygon)
        renderer.fillColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Theme.Palette.ink).withAlphaComponent(0.34)
                : UIColor(Theme.Palette.bone).withAlphaComponent(0.30)
        }
        renderer.strokeColor = .clear
        return renderer
    }
}
