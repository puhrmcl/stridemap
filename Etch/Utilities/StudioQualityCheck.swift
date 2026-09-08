import SwiftUI
import UIKit

/// Exercises production history and composition rules on the PR's simulator build.
@MainActor
struct StudioQualityCheckView: View {
    static let expectedChecks = 29
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
