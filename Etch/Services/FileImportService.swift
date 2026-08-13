import Foundation
import SwiftData

/// Imports activity files (GPX / TCX today) into Etch. Parsing is separated from committing so
/// the UI can parse first, show a preview ("312 runs · 287 with maps · 18 already imported"),
/// and only write to the store when the user confirms.
///
/// All commits go through the shared `ActivityIngestor`, so file imports de-duplicate against
/// live-synced runs — and, when a file matches a metadata-only HealthKit workout, attach the
/// route to it rather than creating a second run.
@MainActor
final class FileImportService {

    /// The result of parsing files, before any database write.
    struct ParseOutcome {
        var activities: [ImportedActivity] = []
        /// Names of files that couldn't be read/parsed (unsupported, corrupt, or empty).
        var failedFiles: [String] = []
    }

    /// What a completed import did — powers the results screen.
    struct Summary {
        var found = 0
        var newRuns = 0
        var duplicates = 0
        var withoutGPS = 0
        var failedFiles: [String] = []
        var earliest: Date?
        var latest: Date?
    }

    private let context: ModelContext
    private let ingestor: ActivityIngestor

    init(context: ModelContext) {
        self.context = context
        self.ingestor = ActivityIngestor(context: context)
    }

    // MARK: Parse (no writes)

    /// Reads and parses the picked files into normalized activities. Makes no database changes,
    /// so its result is safe to render as an import preview.
    ///
    /// Each URL is accessed through its security scope and read into memory; nothing is copied
    /// to disk, so there's no temp file to clean up. Yields between files so a multi-file
    /// selection doesn't lock the UI. (Phase 2 moves large-archive parsing fully off the main
    /// actor.)
    func parse(urls: [URL]) async -> ParseOutcome {
        var outcome = ParseOutcome()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let parsed = try ActivityFileParsing.parse(data: data, fileName: url.lastPathComponent)
                outcome.activities.append(contentsOf: parsed)
            } catch {
                outcome.failedFiles.append(url.lastPathComponent)
            }
            await Task.yield()
        }
        return outcome
    }

    // MARK: Preview (read-only)

    /// Classifies parsed activities without writing anything, for the import preview: how many
    /// are new, how many are already in Etch (by file id or a confident match), how many new
    /// runs lack GPS, and the date range. Within-batch duplicates are counted too.
    func preview(_ activities: [ImportedActivity]) -> Summary {
        var summary = Summary()
        summary.found = activities.count
        var seen = Set<String>()
        for activity in activities {
            let duplicate = isDuplicate(activity, seenInBatch: seen)
            if duplicate {
                summary.duplicates += 1
            } else {
                summary.newRuns += 1
                if activity.coordinates.isEmpty { summary.withoutGPS += 1 }
            }
            if !activity.externalID.isEmpty { seen.insert(activity.externalID) }
            summary.earliest = Swift.min(summary.earliest ?? activity.startDate, activity.startDate)
            summary.latest = Swift.max(summary.latest ?? activity.startDate, activity.startDate)
        }
        return summary
    }

    /// A read-only version of the ingestor's dedup decision: already imported (same file id),
    /// already seen earlier in this batch, or a confident match against an existing run.
    private func isDuplicate(_ activity: ImportedActivity, seenInBatch seen: Set<String>) -> Bool {
        let extID = activity.externalID
        if !extID.isEmpty {
            if seen.contains(extID) { return true }
            var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.sourceExternalID == extID })
            descriptor.fetchLimit = 1
            if let found = try? context.fetch(descriptor), !found.isEmpty { return true }
        }
        let match = (try? ingestor.bestMatch(for: activity)) ?? nil
        return match != nil
    }

    // MARK: Commit

    /// Ingests parsed activities, de-duplicating against the store and within the batch, and
    /// saving in batches so a large import streams progress. `progress` reports `(done, total)`.
    @discardableResult
    func commit(_ activities: [ImportedActivity], progress: ((Int, Int) -> Void)? = nil) async -> Summary {
        var summary = Summary()
        summary.found = activities.count

        var processed = 0
        for activity in activities {
            if let outcome = try? ingestor.ingestImported(activity) {
                switch outcome {
                case .inserted: summary.newRuns += 1
                case .merged: summary.duplicates += 1
                }
            }
            if activity.coordinates.isEmpty { summary.withoutGPS += 1 }
            summary.earliest = Swift.min(summary.earliest ?? activity.startDate, activity.startDate)
            summary.latest = Swift.max(summary.latest ?? activity.startDate, activity.startDate)

            processed += 1
            if processed % 50 == 0 {
                try? context.save()
                await Task.yield()
            }
            progress?(processed, activities.count)
        }
        try? context.save()
        return summary
    }
}
