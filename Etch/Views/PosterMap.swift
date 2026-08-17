import MapKit
import UIKit
import SwiftUI
import CoreImage

/// Renders the map panel for a route poster: a muted MapKit snapshot of the run's area,
/// tinted toward the brand Bone, with the route drawn aligned on top (white casing under
/// Etch Blue) and start/finish dots. Used behind the poster's title block.
enum PosterMap {

    @MainActor
    static func routePanel(
        for run: Run,
        size: CGSize,
        routeWidth: CGFloat = 11,
        casingWidth: CGFloat = 18,
        dotRadius: CGFloat = 11,
        boneWash: CGFloat = 0.22
    ) async -> UIImage? {
        let coordinates = run.coordinates
        guard coordinates.count > 1 else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region(for: run)
        options.size = size
        options.scale = 2
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = config

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
            snapshotter.start(with: .main) { snap, _ in continuation.resume(returning: snap) }
        }
        guard let snapshot else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = options.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let bone = UIColor(Theme.Palette.bone)
        let blue = UIColor(Theme.Palette.blue)
        let sage = UIColor(Theme.Palette.sage)

        return renderer.image { context in
            let cg = context.cgContext

            // Base map, unified toward the brand with a translucent Bone wash.
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            bone.withAlphaComponent(boneWash).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Route path, projected through the snapshot so it aligns with the map.
            let path = UIBezierPath()
            var started = false
            for coordinate in coordinates {
                let point = snapshot.point(for: coordinate)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round

            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = casingWidth
            path.stroke()
            blue.setStroke()
            path.lineWidth = routeWidth
            path.stroke()

            if let first = coordinates.first { dot(cg, at: snapshot.point(for: first), fill: sage, radius: dotRadius) }
            if let last = coordinates.last { dot(cg, at: snapshot.point(for: last), fill: blue, radius: dotRadius) }
        }
    }

    /// Renders the art panel for an Etch Studio *edition*: a muted map snapshot (light or dark
    /// per the edition), washed toward the edition's material, with the route drawn on top in
    /// the edition's style (optional casing, optional glow, start/finish dots). Returns nil for
    /// paper editions, which draw a vector route in the composition instead.
    @MainActor
    static func studioPanel(for run: Run, size: CGSize, edition: StudioEdition,
                            route routeOverride: Color? = nil) async -> UIImage? {
        guard let kind = edition.mapKind else { return nil }
        let coordinates = run.coordinates
        guard coordinates.count > 1 else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region(for: run)
        options.size = size
        options.scale = 2
        options.pointOfInterestFilter = .excludingAll
        let dark = kind == .streetsDark || kind == .standardDark
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        switch kind {
        case .streetsLight, .streetsDark:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
        case .standardLight, .standardDark:
            // Default emphasis keeps Apple's full map colours (roads, parks, water) rather than
            // the muted, archival treatment the other editions use.
            let config = MKStandardMapConfiguration(elevationStyle: .flat)
            config.pointOfInterestFilter = .excludingAll
            options.preferredConfiguration = config
        case .satellite:
            // Real terrain. Elevation adds relief shading where the land actually rises.
            options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        }

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
            snapshotter.start(with: .main) { snap, _ in continuation.resume(returning: snap) }
        }
        guard let snapshot else { return nil }

        // Satellite is a photograph; desaturate it so the terrain reads as muted relief, not a
        // holiday snap — keeping the route the hero, per the brand's "mute geography".
        let baseImage = kind == .satellite
            ? desaturated(snapshot.image, saturation: 0.42) : snapshot.image

        let format = UIGraphicsImageRendererFormat()
        format.scale = options.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let route = UIColor(routeOverride ?? edition.route)

        return renderer.image { context in
            let cg = context.cgContext

            baseImage.draw(in: CGRect(origin: .zero, size: size))
            UIColor(edition.mapWash).withAlphaComponent(edition.mapWashAlpha).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let path = UIBezierPath()
            var started = false
            for coordinate in coordinates {
                let point = snapshot.point(for: coordinate)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round

            if edition.glow {
                cg.saveGState()
                cg.setShadow(offset: .zero, blur: edition.routeWidth * 2.2, color: route.cgColor)
                route.setStroke()
                path.lineWidth = edition.routeWidth
                path.stroke()
                path.stroke()   // second pass deepens the glow
                cg.restoreGState()
            }
            if let casing = edition.casing {
                UIColor(casing).withAlphaComponent(0.9).setStroke()
                path.lineWidth = edition.routeWidth * 1.7
                path.stroke()
            }
            route.setStroke()
            path.lineWidth = edition.routeWidth
            path.stroke()

            let startFill = UIColor(edition.accent)
            let endFill = route
            if let first = coordinates.first { dot(cg, at: snapshot.point(for: first), fill: startFill, radius: edition.routeWidth) }
            if let last = coordinates.last { dot(cg, at: snapshot.point(for: last), fill: endFill, radius: edition.routeWidth) }
        }
    }

    /// Renders the art panel for the Topographic edition: real terrain contour lines (traced
    /// from an Open-Meteo elevation grid via marching squares) over a chosen ground, with the
    /// run's route drawn on top. Pen-plotted contour aesthetic. Returns nil if elevation can't be
    /// fetched, so the caller can fall back.
    @MainActor
    static func topographicPanel(for run: Run, size: CGSize, edition: StudioEdition,
                                 ground: Color, route routeOverride: Color? = nil) async -> UIImage? {
        let coordinates = run.coordinates
        guard coordinates.count > 1 else { return nil }

        let region = region(for: run)
        let latMax = region.center.latitude + region.span.latitudeDelta / 2
        let latMin = region.center.latitude - region.span.latitudeDelta / 2
        let lonMin = region.center.longitude - region.span.longitudeDelta / 2
        let lonMax = region.center.longitude + region.span.longitudeDelta / 2

        guard let field = await ElevationService.field(
            latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax, rows: 40, cols: 40
        ) else { return nil }
        let segments = ContourExtractor.segments(for: field)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let groundColor = UIColor(ground)
        let lineColor = UIColor(edition.contourTint ?? (ground.isDarkGround ? Theme.Palette.bone : Theme.Palette.ink))
        let route = UIColor(routeOverride ?? edition.route)

        func pixel(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(
                x: (coordinate.longitude - lonMin) / (lonMax - lonMin) * size.width,
                y: (latMax - coordinate.latitude) / (latMax - latMin) * size.height
            )
        }

        return renderer.image { context in
            let cg = context.cgContext

            groundColor.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // Contour lines — one thin, round-capped path.
            let contour = UIBezierPath()
            for segment in segments {
                contour.move(to: CGPoint(x: segment.a.x * size.width, y: segment.a.y * size.height))
                contour.addLine(to: CGPoint(x: segment.b.x * size.width, y: segment.b.y * size.height))
            }
            contour.lineWidth = 1.5
            contour.lineCapStyle = .round
            lineColor.withAlphaComponent(0.62).setStroke()
            contour.stroke()

            // Route over the terrain, white-cased so it reads on any ground.
            let path = UIBezierPath()
            var started = false
            for coordinate in coordinates {
                let point = pixel(coordinate)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round

            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = edition.routeWidth * 1.7
            path.stroke()
            route.setStroke()
            path.lineWidth = edition.routeWidth
            path.stroke()

            if let first = coordinates.first { dot(cg, at: pixel(first), fill: UIColor(edition.accent), radius: edition.routeWidth) }
            if let last = coordinates.last { dot(cg, at: pixel(last), fill: route, radius: edition.routeWidth) }
        }
    }

    /// Shared CoreImage context for the satellite desaturation pass.
    private static let ciContext = CIContext(options: nil)

    /// Desaturates (and gently lifts) a snapshot so satellite terrain reads as muted relief.
    private static func desaturated(_ image: UIImage, saturation: CGFloat) -> UIImage {
        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: input,
                kCIInputSaturationKey: saturation,
                kCIInputBrightnessKey: 0.03,
                kCIInputContrastKey: 1.03
              ]),
              let output = filter.outputImage,
              let cgImage = ciContext.createCGImage(output, from: input.extent)
        else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// In-memory cache + tile-sized renderer for the Timeline's month tiles.
    private static let tileCache = NSCache<NSString, UIImage>()

    @MainActor
    static func tileImage(for run: Run, size: CGSize) async -> UIImage? {
        guard size.width > 1, size.height > 1, run.coordinates.count > 1 else { return nil }
        let key = "\(run.id.uuidString)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = tileCache.object(forKey: key) { return cached }
        let image = await routePanel(
            for: run, size: size,
            routeWidth: 4, casingWidth: 7, dotRadius: 4, boneWash: 0.18
        )
        if let image { tileCache.setObject(image, forKey: key) }
        return image
    }

    private static func dot(_ ctx: CGContext, at point: CGPoint, fill: UIColor, radius: CGFloat = 11) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: rect)
    }

    /// A region framing the run with padding, from its cached bounding box.
    private static func region(for run: Run) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(
            latitude: (run.minLatitude + run.maxLatitude) / 2,
            longitude: (run.minLongitude + run.maxLongitude) / 2
        )
        let latDelta = max((run.maxLatitude - run.minLatitude) * 1.35, 0.004)
        let lonDelta = max((run.maxLongitude - run.minLongitude) * 1.35, 0.004)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
