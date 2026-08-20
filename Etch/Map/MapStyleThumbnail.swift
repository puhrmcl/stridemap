import SwiftUI
import MapKit

/// A small, cached MapKit snapshot preview of a base-map style — used by the Map Type picker so
/// each tile shows what the map actually looks like rather than a vague icon.
struct MapStyleThumbnail: View {
    let style: MapStyleOption
    var size: CGFloat = 92

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear   // the tile's gradient placeholder shows through until this loads
            }
        }
        .task(id: style) {
            image = await MapStylePreviewCache.shared.image(for: style, size: size)
        }
    }
}

/// Renders and caches one snapshot per style (at a sample region with city, water, and hills so
/// the differences read clearly). Cheap after the first render — the sheet reopens instantly.
actor MapStylePreviewCache {
    static let shared = MapStylePreviewCache()

    private var cache: [MapStyleOption: UIImage] = [:]

    func image(for style: MapStyleOption, size: CGFloat) async -> UIImage? {
        if let cached = cache[style] { return cached }
        let rendered = await render(style, size: size)
        if let rendered { cache[style] = rendered }
        return rendered
    }

    private func render(_ style: MapStyleOption, size: CGFloat) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        // San Francisco: city grid, bay water, and hills — shows each style's character.
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.803, longitude: -122.42),
            span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09)
        )
        options.size = CGSize(width: size, height: size)
        options.preferredConfiguration = style.configuration()
        if style.forcedInterfaceStyle == .dark {
            options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        }
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        return snapshot.image
    }
}
