import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

/// Attaches a route from a GPX/TCX/FIT file to an existing activity — the escape hatch for
/// workouts whose source never delivered a map (Nike, treadmill GPS gaps, a HealthKit race)
/// when the runner has the file from elsewhere, e.g. a Strava export.
///
/// One modifier so every surface (the Edit sheet's Route row, the detail page's "No map data"
/// card) runs the identical flow: file picker → off-main parse → pick the track closest in
/// time when a file holds several → honest confirmation (distance, points, date, replace
/// warning) → write through `ActivityIngestor.applyRoute`, the same central path every import
/// uses, with `RouteSource.imported` provenance. Recorded stats stay untouched.
struct RouteFileAttacher: ViewModifier {
    @Bindable var run: Run
    @Binding var isPresented: Bool
    /// Called after a route is written, for callers that show their own confirmation state.
    var onAttached: (() -> Void)? = nil

    @Environment(\.modelContext) private var context

    @State private var candidate: Candidate?
    @State private var errorMessage: String?
    @State private var isReading = false

    /// A parsed route awaiting the user's confirmation before it's written to the activity.
    private struct Candidate: Identifiable {
        let id = UUID()
        var coordinates: [CLLocationCoordinate2D]
        var encoded: String?
        var elevations: [Double]
        var paces: [Double]
        var distance: Double
        var startDate: Date
    }

    /// GPX/TCX/FIT carry no registered UTI on iOS — `.data`/`.xml` keep them selectable; the
    /// parser validates the actual contents.
    private static let fileTypes: [UTType] = {
        var types = [
            UTType(filenameExtension: "gpx", conformingTo: .xml),
            UTType(filenameExtension: "tcx", conformingTo: .xml),
            UTType(filenameExtension: "fit", conformingTo: .data)
        ].compactMap { $0 }
        types.append(.data)
        types.append(.xml)
        return types
    }()

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: Self.fileTypes,
                allowsMultipleSelection: false,
                onCompletion: handlePick
            )
            .overlay {
                if isReading {
                    ProgressView("Reading file…")
                        .padding(20)
                        .background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .alert("Attach this route?", isPresented: .init(
                get: { candidate != nil }, set: { if !$0 { candidate = nil } }
            ), presenting: candidate) { candidate in
                Button("Attach") { attach(candidate) }
                Button("Cancel", role: .cancel) {}
            } message: { candidate in
                Text(summary(candidate))
            }
            .alert("Couldn't read that file", isPresented: .init(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isReading = true
        let target = run.startDate
        Task {
            defer { isReading = false }
            let parsed: [ImportedActivity]
            do {
                parsed = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    return try ActivityFileParsing.parse(data: data, fileName: url.lastPathComponent)
                }.value
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            // A file can hold several activities; the one closest in time to this activity is
            // the intended route. Only tracks with actual GPS points qualify.
            let withRoute = parsed.filter { !$0.coordinates.isEmpty }
            guard let best = withRoute.min(by: {
                abs($0.startDate.timeIntervalSince(target)) < abs($1.startDate.timeIntervalSince(target))
            }) else {
                errorMessage = "That file has no GPS points in it."
                return
            }
            candidate = Candidate(
                coordinates: best.coordinates,
                encoded: best.encodedPolyline,
                elevations: best.elevationSeries,
                paces: best.paceSeries,
                distance: best.distance,
                startDate: best.startDate
            )
        }
    }

    private func summary(_ candidate: Candidate) -> String {
        let miles = candidate.distance / 1609.344
        var lines = [
            String(format: "%.1f mi · %d GPS points", miles, candidate.coordinates.count),
            candidate.startDate.formatted(date: .abbreviated, time: .shortened),
        ]
        if abs(candidate.startDate.timeIntervalSince(run.startDate)) > 6 * 3600 {
            lines.append("Note: the file's date differs from this activity's.")
        }
        if run.hasRoute {
            lines.append("This replaces the current route.")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the route through the central import path, then overrides the elevation series
    /// explicitly — on a replace, the attached file's data wins. Elevation gain backfills only
    /// when the activity recorded none.
    private func attach(_ candidate: Candidate) {
        let ingestor = ActivityIngestor(context: context)
        ingestor.applyRoute(
            candidate.coordinates, source: .imported, to: run,
            encoded: candidate.encoded, elevations: candidate.elevations,
            paces: candidate.paces
        )
        if !candidate.elevations.isEmpty {
            run.elevationSeries = candidate.elevations
        }
        if !candidate.paces.isEmpty {
            run.paceSeries = candidate.paces
        }
        if run.elevationGain == 0 {
            run.elevationGain = RouteMetrics.elevationGain(of: candidate.elevations)
        }
        try? context.save()
        self.candidate = nil
        onAttached?()
    }
}

extension View {
    /// See `RouteFileAttacher`. Present by setting `isPresented` to true.
    func routeFileAttacher(
        run: Run, isPresented: Binding<Bool>, onAttached: (() -> Void)? = nil
    ) -> some View {
        modifier(RouteFileAttacher(run: run, isPresented: isPresented, onAttached: onAttached))
    }
}
