import SwiftUI
import UIKit

/// Exercises production history and composition rules on the PR's simulator build.
@MainActor
struct StudioQualityCheckView: View {
    static let expectedChecks = 52
    @State private var report = "Checking Studio…"

    var body: some View {
        ScrollView { Text(report).font(.system(.caption, design: .monospaced)).padding() }
            .task { await check() }
    }

    private func activity(city: String?, state: String?) -> Run {
        let run = Run(provider: .healthKit, name: "Studio fixture", startDate: Date(),
                      distance: 5000, movingTime: 1500, elapsedTime: 1800,
                      elevationGain: 0, summaryPolyline: "", sportType: "Run")
        run.city = city; run.state = state; run.country = "United States"
        return run
    }

    private func check() async {
        var lines: [String] = []
        func expect(_ name: String, _ condition: Bool) {
            lines.append("\(condition ? "PASS" : "FAIL")  \(name)")
        }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var history = StudioEditHistory<Int>()
        expect("New editor has no history", !history.canUndo && !history.canRedo)
        history.record(from: 0, to: 1, at: start)
        expect("Edit can be undone", history.canUndo && !history.canRedo)
        history.record(from: 1, to: 2, at: start.addingTimeInterval(0.1))
        expect("Rapid edits coalesce", history.past == [0])
        let undo = history.undo(2)
        expect("Undo returns the original value", undo == 0)
        history.record(from: 2, to: 0, at: start.addingTimeInterval(1))
        expect("Observing Undo does not record a new edit", !history.canUndo && history.canRedo)
        expect("Redo restores the finished edit", history.redo(0) == 2)
        history.record(from: 0, to: 2, at: start.addingTimeInterval(2))
        expect("Observing Redo preserves history", history.past == [0] && !history.canRedo)
        history.record(from: 2, to: 3, at: start.addingTimeInterval(3))
        expect("Separate edits remain separate", history.past == [0, 2])
        _ = history.undo(3)
        history.record(from: 2, to: 4, at: start.addingTimeInterval(4))
        expect("Editing after Undo clears Redo", !history.canRedo)
        expect("Branched edit undoes to correct value", history.undo(4) == 2)
        var bounded = StudioEditHistory<Int>()
        for index in 0..<100 {
            bounded.record(from: index, to: index + 1, at: start.addingTimeInterval(Double(index)))
        }
        expect("History is bounded to 60 entries", bounded.past.count == 60 && bounded.past.first == 40)
        var clock = StudioEditHistory<Int>()
        clock.record(from: 0, to: 1, at: start)
        clock.record(from: 1, to: 2, at: start.addingTimeInterval(-1))
        expect("Clock changes do not merge edits", clock.past == [0, 1])
        let config = PosterConfig.makeDefault(for: activity(city: "Portland", state: "Maine"))
        var changed = config; changed.mapInset.toggle()
        expect("Border change invalidates preview", changed != config)
        changed = config; changed.athleteName = "Jordan Avery"
        expect("Athlete text invalidates preview", changed != config)
        changed = config; changed.showBib.toggle()
        expect("Bib visibility invalidates preview", changed != config)
        changed = config; changed.galleryPhotoPicks = [2, 0, 1]
        expect("Photo assignments invalidate preview", changed != config)
        changed = config; changed.titleScale = 1.1
        expect("Typography scale invalidates preview", changed != config)
        let portrait = StudioPrintLayout.gallerySecondaryHeight(total: 620, gutter: 16, fraction: 0.38)
        let landscape = StudioPrintLayout.gallerySecondaryHeight(total: 300, gutter: 16, fraction: 0.38)
        expect("Gallery rows adapt to available height", portrait > landscape && abs(landscape - 107.92) < 0.01)
        expect("Gallery gutters cannot produce negative frames", StudioPrintLayout.gallerySecondaryHeight(total: 8, gutter: 16, fraction: 0.38) == 0)
        expect("Gallery fractions cannot exceed available space", StudioPrintLayout.gallerySecondaryHeight(total: 100, gutter: 16, fraction: 2) == 84)
        let title = String(repeating: "A year of extraordinary places ", count: 6)
        let attributes = StudioPrintLayout.fittedAttributes(title,
            font: EtchType.uiFont(.editorial, size: 48), color: .black, tracking: 2, width: 320)
        expect("Long titles fit the print margin", (title as NSString).size(withAttributes: attributes).width <= 321)
        let short = StudioPrintLayout.fittedAttributes("Etch", font: .systemFont(ofSize: 20), color: .black, tracking: 0, width: 800)
        expect("Short titles retain authored size", (short[.font] as? UIFont)?.pointSize == 20)
        let maine = activity(city: "Portland", state: "Maine")
        let oregon = activity(city: "Portland", state: "Oregon")
        let repeatMaine = activity(city: " Portland ", state: "maine")
        let unnamed = activity(city: nil, state: nil)
        let cities = StudioPrintLayout.cityEntries(in: [maine, oregon, repeatMaine, unnamed])
        expect("Same-name cities retain their region", cities.count == 2 && cities.allSatisfy { $0.name.contains(",") })
        expect("Repeated visits aggregate accurately", cities.first?.count == 2 && cities.first?.metres == 10_000)
        expect("Map and city list use the same place identity", StudioPrintLayout.cityKey(for: maine) == StudioPrintLayout.cityKey(for: repeatMaine) && StudioPrintLayout.cityKey(for: maine) != StudioPrintLayout.cityKey(for: oregon))
        expect("Unlocated activities do not invent a city", StudioPrintLayout.cityEntries(in: [unnamed]).isEmpty)
        let emptyArt = await MapPrintRenderer.image(for: .make(kind: .artMap, runs: []), scale: 0.1)
        expect("Empty Anthology is not a blank printable image", emptyArt == nil)
        var emptyIndex = MapPrintRequest.make(kind: .cities, runs: [])
        emptyIndex.cityIndex = true
        let emptyLithograph = await MapPrintRenderer.image(for: emptyIndex, scale: 0.1)
        expect("Empty Lithograph is not a blank printable image", emptyLithograph == nil)
        var index = MapPrintRequest.make(kind: .cities, runs: [maine, oregon])
        index.cityIndex = true
        let lithograph = await MapPrintRenderer.image(for: index, scale: 0.1)
        expect("Lithograph renders at its paper proportions", lithograph != nil && lithograph?.size == index.posterIndexSize)
        // Contour panels. Both of these rendered as bare paper on device: one throttled batch out
        // of sixteen failed the whole elevation field, and a valley-floor course fell under a 1 m
        // relief floor. Neither said anything — the sheet just arrived empty.
        var gapped = [Double](repeating: 0, count: 9)
        var knownSamples = [Bool](repeating: true, count: 9)
        gapped[0] = 100; gapped[1] = 110; gapped[2] = 120     // north row, fetched
        knownSamples[3] = false; knownSamples[4] = false; knownSamples[5] = false  // middle row lost
        gapped[6] = 140; gapped[7] = 150; gapped[8] = 160     // south row, fetched
        ElevationService.fillGaps(&gapped, known: knownSamples, rows: 3, cols: 3)
        expect("A lost batch is filled from the terrain around it",
               gapped[3] == 100 && gapped[4] == 110 && gapped[5] == 120)
        expect("Filling a gap leaves the fetched samples alone",
               gapped[0] == 100 && gapped[8] == 160)
        expect("No sample is left at sea level after filling",
               !gapped.contains(0))

        func field(_ relief: Double) -> ElevationField {
            let values = (0..<16).map { Double($0 % 4) / 3 * relief }
            return ElevationField(rows: 4, cols: 4, values: values,
                                  minElevation: values.min() ?? 0, maxElevation: values.max() ?? 0)
        }
        expect("A gentle course still traces contours",
               !ContourExtractor.segments(for: field(0.6)).isEmpty)
        expect("Genuinely flat ground traces nothing",
               ContourExtractor.segments(for: field(0.05)).isEmpty)

        var source = StudioRenderer.Request(run: maine, edition: .atlas, layout: .gallery)
        source.galleryCellsRaw = ["photo", "route"]
        expect("Photo and route Gallery needs no map provider", !source.needsMapPanel && source.printReady)
        source.galleryCellsRaw = ["photo", "map"]
        expect("A map tile requires print cartography", source.needsMapPanel)
        source.galleryCellsRaw = []
        expect("Legacy Gallery plans conservatively require a map", source.needsMapPanel)
        source.galleryCellsRaw = ["unknown"]
        expect("Invalid Gallery plans do not bypass the map guard", source.needsMapPanel)
        source.layout = .classic; source.galleryCellsRaw = ["photo"]
        expect("Map product always requires its map panel", source.needsMapPanel)
        source.edition = .minimal
        expect("No Map composition remains available", !source.needsMapPanel && source.printReady)

        var retry = MapSnapshotRetryState()
        expect("Fresh map style can render", retry.allowsAttempt(at: start))
        retry.failed(at: start); retry.failed(at: start); retry.failed(at: start)
        expect("Repeated failures pause automatic retries", !retry.allowsAttempt(at: start.addingTimeInterval(44)))
        var independent = MapSnapshotRetryState()
        expect("Another map style remains available", independent.allowsAttempt(at: start))
        expect("Cooldown permits a recovery probe", retry.allowsAttempt(at: start.addingTimeInterval(45)))
        retry.failed(at: start.addingTimeInterval(45))
        expect("Failed recovery probe pauses again", !retry.allowsAttempt(at: start.addingTimeInterval(46)))
        let failedGeneration = retry.generation
        retry.reset()
        expect("Explicit retry immediately clears the pause", retry.allowsAttempt(at: start.addingTimeInterval(46)))
        expect("Explicit retry invalidates older failures", retry.generation != failedGeneration && retry.failures == 0)

        let tile = CommerceConfig.workerBase.absoluteString + "/tiles/{z}/{x}/{y}.mvt"
        let resolved = PrintTileSource.source(from: ["tiles": [tile], "minzoom": 0, "maxzoom": 15, "scheme": "xyz"])
        expect("Print tiles preserve placeholders and gain a new cache identity",
               (resolved?["tiles"] as? [String])?.first == tile + "?etchRevision=" + PrintTileSource.revision)
        expect("Print tiles preserve served zoom limits", resolved?["maxzoom"] as? Int == 15)
        expect("Malformed metadata cannot become a print source",
               PrintTileSource.source(from: ["tiles": [tile], "minzoom": 16, "maxzoom": 15]) == nil)
        expect("External tile redirects are not silently adopted",
               PrintTileSource.source(from: ["tiles": ["https://example.org/{z}/{x}/{y}"], "minzoom": 0, "maxzoom": 15]) == nil)
        expect("Existing tile queries remain intact", PrintTileSource.versioned(tile + "?a=1").contains("?a=1&etchRevision="))

        let passed = lines.count == Self.expectedChecks && !lines.contains { $0.hasPrefix("FAIL") }
        let complete = (["studio-quality \(AppInfo.changeTag)"] + lines + [
            "EXPECTED_CHECKS: \(Self.expectedChecks)", "RAN_CHECKS: \(lines.count)",
            passed ? "RESULT: ALL PASS" : "RESULT: FAIL"
        ]).joined(separator: "\n")
        report = complete
        if let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? complete.write(to: directory.appendingPathComponent("studio-quality-report.txt"), atomically: true, encoding: .utf8)
        }
    }
}

/// Full artwork proofs use the production renderers, not editor thumbnails or mockups.
@MainActor
struct StudioPrintProofView: View {
    let name: String
    let runs: [Run]
    let subject: Run
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.88).ignoresSafeArea()
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(18) }
            else { ProgressView("Rendering proof…") }
        }
        .task {
            let landscape = name.contains("landscape")
            if name.contains("anthology") || name.contains("lithograph") {
                var request = MapPrintRequest.make(kind: name.contains("anthology") ? .artMap : .cities, runs: runs)
                request.orientation = landscape ? .landscape : .portrait
                request.artStyle = .ridgeline
                request.artPlateEdge = .bottom
                request.artPlateTitle = "A Year in Motion"
                request.artPlateName = "Jordan Avery"
                request.cityIndex = name.contains("lithograph")
                request.cityIndexHero = .map
                request.cityIndexMapScope = .country
                request.cityIndexSubtitle = "The miles between familiar places"
                image = await MapPrintRenderer.image(for: request, scale: 1)
            } else {
                var config = PosterConfig.makeDefault(for: subject)
                config.family = name.contains("gallery") ? .gallery : .map
                config.galleryDesign = .feature
                config.orientation = landscape ? .landscape : .portrait
                image = await StudioRenderer.image(for: config.request(for: subject), scale: 1)
            }
        }
    }
}
