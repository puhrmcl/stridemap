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
    /// - Parameter requireOwnCartography: refuses the Apple fallback, returning nil instead. The
    ///   print path sets it: a preview may honestly show an Apple panel and simply not be
    ///   sellable, but a print file built from one would be Apple's map data on merchandise.
    /// - Parameter ground: the poster's actual paper colour. The panel is finished onto it, so the
    ///   map's own ground and the sheet around it are the same tone and no seam runs across the
    ///   print. Nil falls back to the edition's authored ground.
    @MainActor
    static func studioPanel(for run: Run, size: CGSize, edition: StudioEdition,
                            route routeOverride: Color? = nil,
                            ground groundOverride: Color? = nil,
                            requireOwnCartography: Bool = false) async -> UIImage? {
        guard let kind = edition.mapKind else { return nil }
        let coordinates = run.coordinates
        guard coordinates.count > 1 else { return nil }

        // The Studio editor re-renders the whole composition on every option change — including
        // every keystroke in a text field — and each render used to start a fresh MKMapSnapshotter.
        // The panel only depends on the run, the edition, the size and the route tint, so cache it:
        // typing a title now costs one snapshot, not one per character.
        // A strict render neither reads nor writes the cache. The key covers the run, size,
        // edition and route tint — not *where the map came from* — so a preview that fell back to
        // Apple would otherwise be handed straight back to a print asking for our cartography,
        // and the guard would pass while shipping the thing it exists to prevent. Print panels are
        // rendered once per order, so there is nothing to save here anyway.
        let paper = groundOverride ?? edition.ground
        let key = panelKey("studio", run: run, size: size, edition: edition,
                           route: routeOverride, ground: paper)
        if !requireOwnCartography, let cached = panelCache.object(forKey: key) { return cached }

        // Etch's own cartography first, when the basemap is live and this edition has an
        // OpenStreetMap equivalent — that is the panel the poster may actually be sold as. Apple
        // remains the fallback, so a tile outage costs a poster its *printability*, never its
        // existence.
        //
        // The paper travels into the style, so the basemap's land layer *is* the sheet rather than
        // a tone that happens to be close to it.
        if EtchMapSnapshotter.canRender(edition),
           let own = await EtchMapSnapshotter.snapshot(for: coordinates, size: size,
                                                       scale: 2, edition: edition, ground: paper) {
            let base = edition.panelSaturation.map { desaturated(own.image, saturation: $0) }
                ?? own.image
            let finished = overlay(
                groundMatched(washed(base, edition: edition), to: paper),
                coordinates: coordinates, size: size, scale: 2,
                edition: edition, route: routeOverride, isRace: run.isRace,
                project: { own.frame.point(for: $0, in: size) }
            )
            if !requireOwnCartography { panelCache.setObject(finished, forKey: key) }
            return finished
        }

        // Our cartography could not supply it. For a preview that is fine — Apple draws the panel
        // and the shop marks the piece display-only. For a print it is not: the caller asked for
        // a sheet it can sell, and there isn't one.
        if requireOwnCartography { return nil }

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
        // holiday snap — keeping the route the hero, per the brand's "mute geography". Editions
        // with `panelSaturation` (the Streets city prints) drive their own level — 0 turns the
        // map fully monochrome so only the street pattern remains.
        let baseImage: UIImage
        if kind == .satellite {
            baseImage = desaturated(snapshot.image, saturation: 0.42)
        } else if let saturation = edition.panelSaturation {
            baseImage = desaturated(snapshot.image, saturation: saturation)
        } else {
            baseImage = snapshot.image
        }

        let image = overlay(
            groundMatched(washed(baseImage, edition: edition), to: paper),
            coordinates: coordinates, size: size, scale: options.scale,
            edition: edition, route: routeOverride, isRace: run.isRace,
            project: { snapshot.point(for: $0) }
        )
        panelCache.setObject(image, forKey: key)
        return image
    }

    // MARK: Finishing the panel onto the paper

    /// Washes the map toward the edition's material.
    ///
    /// This used to happen inside `overlay`, after the route had a rectangle to sit on. It has to
    /// happen here instead, because `groundMatched` runs next and needs to see the map's *final*
    /// ground — correcting a tone and then tinting it afterwards would put the seam straight back.
    private static func washed(_ image: UIImage, edition: StudioEdition) -> UIImage {
        guard edition.mapWashAlpha > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            UIColor(edition.mapWash).withAlphaComponent(edition.mapWashAlpha).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: image.size))
        }
    }

    /// Prints the map onto the poster's own paper.
    ///
    /// The seam this removes was the loudest thing separating our sheets from the references: a
    /// map panel carries its own land colour — Apple's, or an edition's authored ground — and the
    /// poster around it carries the user's chosen paper. Two tones a few percent apart meet at a
    /// hard rectangle, and the eye finds that edge instantly. The references have no such edge
    /// because their maps are drawn *on* the sheet.
    ///
    /// The correction is a white balance rather than a fill. The panel's own land colour is
    /// measured, and a per-channel gain is applied that takes exactly that colour to the paper.
    /// Land lands on the paper by construction; everything else — roads, water, buildings — moves
    /// with it and keeps its relationship to the ground, so the map still reads as the map. A flat
    /// tint could only have averaged the difference away and muddied every feature doing it.
    ///
    /// Skipped when the measurement is untrustworthy: a near-black ground makes the gain explode,
    /// and a panel whose land is already the paper needs nothing.
    private static func groundMatched(_ image: UIImage, to paper: Color) -> UIImage {
        guard let land = dominantColor(of: image) else { return image }
        var pr: CGFloat = 0, pg: CGFloat = 0, pb: CGFloat = 0, pa: CGFloat = 0
        UIColor(paper).getRed(&pr, green: &pg, blue: &pb, alpha: &pa)

        // A channel this dark carries no reliable ratio — dividing by it turns noise into colour.
        guard land.0 > 0.02, land.1 > 0.02, land.2 > 0.02 else { return image }

        let gain = (
            min(max(pr / land.0, 0.25), 4),
            min(max(pg / land.1, 0.25), 4),
            min(max(pb / land.2, 0.25), 4)
        )
        // Already on the paper — within a value the print process itself cannot hold apart.
        if abs(gain.0 - 1) < 0.004, abs(gain.1 - 1) < 0.004, abs(gain.2 - 1) < 0.004 { return image }

        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIColorMatrix", parameters: [
                kCIInputImageKey: input,
                "inputRVector": CIVector(x: gain.0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain.1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain.2, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
              ]),
              let output = filter.outputImage,
              let cgImage = ciContext.createCGImage(output, from: input.extent)
        else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// The panel's land colour: the most common tone in it.
    ///
    /// Mode rather than mean. A map's average is dragged toward whatever happens to be in frame —
    /// a river, a park, a dense downtown — and correcting to an average would tint the sheet by
    /// how much water the route ran past. The ground is by definition the colour most of the panel
    /// is, so the modal bucket finds it whatever else is on the page.
    private static func dominantColor(of image: UIImage) -> (CGFloat, CGFloat, CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        // 5 bits per channel: fine enough to tell a paper from a park, coarse enough that the
        // land does not scatter across a hundred near-identical buckets and lose to a solid one.
        var counts: [UInt16: Int] = [:]
        var sums: [UInt16: (Int, Int, Int)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            let bucket = UInt16((r >> 3) << 10 | (g >> 3) << 5 | (b >> 3))
            counts[bucket, default: 0] += 1
            let running = sums[bucket] ?? (0, 0, 0)
            sums[bucket] = (running.0 + r, running.1 + g, running.2 + b)
        }
        guard let (bucket, count) = counts.max(by: { $0.value < $1.value }),
              let total = sums[bucket], count > 0 else { return nil }
        // The bucket's own mean, not the bucket's centre — a quantised centre would introduce an
        // error of its own into the very number the correction is built on.
        return (CGFloat(total.0) / CGFloat(count) / 255,
                CGFloat(total.1) / CGFloat(count) / 255,
                CGFloat(total.2) / CGFloat(count) / 255)
    }

    /// Draws the route over a finished map panel.
    ///
    /// `project` is the only thing that differs between the two sources: Apple hands back a
    /// `point(for:)` from its own snapshot, Etch's basemap projects through the frame it framed
    /// with. Everything after that — the glow, the casing, the route, the start and finish dots —
    /// is the edition's style and must be identical, or the same edition would look like two
    /// different products depending on which cartography drew it.
    @MainActor
    private static func overlay(
        _ base: UIImage, coordinates: [CLLocationCoordinate2D], size: CGSize, scale: CGFloat,
        edition: StudioEdition, route routeOverride: Color?, isRace: Bool = false,
        project: (CLLocationCoordinate2D) -> CGPoint
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let route = UIColor(routeOverride ?? edition.route)

        return renderer.image { context in
            let cg = context.cgContext

            // The wash and the ground correction have already been applied — `base` arrives as the
            // finished sheet. Anything tinted here would tint the route with it.
            base.draw(in: CGRect(origin: .zero, size: size))

            let path = UIBezierPath()
            var started = false
            for coordinate in coordinates {
                let point = project(coordinate)
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

            if let first = coordinates.first {
                dot(cg, at: project(first), fill: UIColor(edition.accent), radius: edition.routeWidth)
            }
            if let last = coordinates.last {
                if isRace {
                    chequer(cg, at: project(last), fill: route, radius: edition.routeWidth * 1.35)
                } else {
                    dot(cg, at: project(last), fill: route, radius: edition.routeWidth)
                }
            }
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

        // Contour panels are the most expensive art in Studio — a network elevation fetch plus a
        // marching-squares trace — so caching them matters even more than the map panels.
        let key = panelKey("contour", run: run, size: size, edition: edition,
                           route: routeOverride, ground: ground)
        if let cached = panelCache.object(forKey: key) { return cached }

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

        let image = renderer.image { context in
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
            if let last = coordinates.last {
                // The contour prints mark their ends the same way the map panels do — a race
                // finishes under a chequer wherever it is drawn.
                if run.isRace {
                    chequer(cg, at: pixel(last), fill: route, radius: edition.routeWidth * 1.35)
                } else {
                    dot(cg, at: pixel(last), fill: route, radius: edition.routeWidth)
                }
            }

            // Waypoint labels — START / FINISH, and the high point over the terrain (its
            // elevation), the way trail prints call out the key points along a route.
            func drawLabel(_ text: String, at point: CGPoint, dy: CGFloat) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: lineColor,
                    .kern: 2
                ]
                let s = NSAttributedString(string: text, attributes: attrs)
                let sz = s.size()
                var o = CGPoint(x: point.x - sz.width / 2, y: point.y + dy)
                o.x = min(max(8, o.x), size.width - sz.width - 8)
                o.y = min(max(8, o.y), size.height - sz.height - 8)
                s.draw(at: o)
            }
            if let first = coordinates.first { drawLabel("START", at: pixel(first), dy: -36) }
            if coordinates.count > 2, let last = coordinates.last { drawLabel("FINISH", at: pixel(last), dy: 18) }

            // Highest point over the terrain, marked with an upward triangle + its elevation.
            var maxElev = -Double.greatestFiniteMagnitude
            var highCoord: CLLocationCoordinate2D?
            for c in coordinates {
                let u = (c.longitude - lonMin) / (lonMax - lonMin)
                let v = (latMax - c.latitude) / (latMax - latMin)
                let col = min(field.cols - 1, max(0, Int(u * Double(field.cols - 1))))
                let row = min(field.rows - 1, max(0, Int(v * Double(field.rows - 1))))
                let e = field.value(row: row, col: col)
                if e > maxElev { maxElev = e; highCoord = c }
            }
            if let hc = highCoord, maxElev > 0 {
                let p = pixel(hc)
                let r = edition.routeWidth * 0.9
                let tri = UIBezierPath()
                tri.move(to: CGPoint(x: p.x, y: p.y - r))
                tri.addLine(to: CGPoint(x: p.x - r, y: p.y + r))
                tri.addLine(to: CGPoint(x: p.x + r, y: p.y + r))
                tri.close()
                UIColor(edition.accent).setFill(); tri.fill()
                UIColor.white.withAlphaComponent(0.9).setStroke(); tri.lineWidth = 2; tri.stroke()
                drawLabel(Format.elevation(maxElev), at: p, dy: -36)
            }
        }
        panelCache.setObject(image, forKey: key)
        return image
    }

    // MARK: Panel cache

    /// Rendered Studio art panels (map snapshots and contour fields), keyed by everything that can
    /// change them. Studio re-renders its whole composition on every option change, so without this
    /// a single editing session starts hundreds of snapshotters and elevation fetches.
    private static let panelCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 40          // panels are large; bound the set rather than the bytes
        return cache
    }()

    private static func panelKey(_ kind: String, run: Run, size: CGSize, edition: StudioEdition,
                                 route: Color?, ground: Color? = nil) -> NSString {
        // `updatedAt` is in the key so an edited route re-renders instead of returning a stale panel.
        let parts = [
            kind,
            run.id.uuidString,
            "\(run.updatedAt.timeIntervalSinceReferenceDate)",
            edition.id.rawValue,
            "\(Int(size.width))x\(Int(size.height))",
            route?.hexString ?? "-",
            ground?.hexString ?? "-"
        ]
        return parts.joined(separator: "|") as NSString
    }

    /// The map image attached when an activity is shared. Uses the route-over-map panel when the
    /// activity has a route; otherwise — a hand-entered race, or any activity placed on the map
    /// without a recorded track — falls back to a map of *where* it happened with the start point
    /// marked, so a shared activity always carries a picture of its place.
    @MainActor
    static func sharePanel(for run: Run, size: CGSize) async -> UIImage? {
        if run.coordinates.count > 1 {
            return await routePanel(for: run, size: size)
        }
        guard let coordinate = run.startCoordinate else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 1600, longitudinalMeters: 1600
        )
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

        return renderer.image { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            bone.withAlphaComponent(0.18).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            dot(context.cgContext, at: snapshot.point(for: coordinate), fill: blue, radius: 13)
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

    /// In-memory cache + tile-sized renderer for row/tile thumbnails. Bounded: every activity
    /// row now carries a map tile, so an unbounded cache over a large library (1,000+ activities
    /// across search, timeline and achievements) grows without limit until the app is killed.
    private static let tileCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    @MainActor
    static func tileImage(for run: Run, size: CGSize) async -> UIImage? {
        guard size.width > 1, size.height > 1, run.coordinates.count > 1 else { return nil }
        // Key on the run's edit stamp too, so an edited route (same id, same tile size) renders a
        // fresh snapshot instead of returning a stale one.
        let key = "\(run.id.uuidString)-\(Int(size.width))x\(Int(size.height))-\(run.updatedAt.timeIntervalSinceReferenceDate)" as NSString
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

    /// The chequered finish, for a race. Drawn as geometry rather than as a flag glyph: a symbol
    /// font's flag turns to mush at 300 DPI, and this stays crisp at any size the sheet is
    /// printed at.
    private static func chequer(_ ctx: CGContext, at point: CGPoint, fill: UIColor, radius: CGFloat) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: rect)

        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        let cells = 4
        let cell = radius * 2 / CGFloat(cells)
        ctx.setFillColor(UIColor.white.cgColor)
        for row in 0..<cells {
            for column in 0..<cells where (row + column).isMultiple(of: 2) {
                ctx.fill(CGRect(x: rect.minX + CGFloat(column) * cell,
                                y: rect.minY + CGFloat(row) * cell,
                                width: cell, height: cell))
            }
        }
        ctx.restoreGState()

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
