import SwiftUI
import SwiftData

/// The confirmation step between parsing files and writing runs: shows what was found, lets
/// the user commit or cancel, streams progress during the import, then reports the result.
struct ImportPreviewView: View {
    let outcome: FileImportService.ParseOutcome

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncService.self) private var sync

    /// A mutable copy of the parsed activities so the user can correct each one's type before
    /// importing — auto-detection is the default, and edits here flow straight into the commit.
    @State private var activities: [ImportedActivity]

    /// Above this many activities we don't show the per-activity type editor (a full Nike/Garmin
    /// export can be hundreds) — those import on auto-detection and can be re-typed in run detail.
    private let typeEditorLimit = 25

    init(outcome: FileImportService.ParseOutcome) {
        self.outcome = outcome
        _activities = State(initialValue: outcome.activities)
    }

    private enum Stage {
        case loading
        case preview(FileImportService.Summary)
        case importing(done: Int, total: Int)
        case done(FileImportService.Summary)
    }
    @State private var stage: Stage = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .loading:
                    ProgressView("Reading your history…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .preview(let summary):
                    previewContent(summary)
                case .importing(let done, let total):
                    importingContent(done: done, total: total)
                case .done(let summary):
                    resultsContent(summary)
                }
            }
            .navigationTitle("Add Your History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isImporting {
                        Button(isFinished ? "Done" : "Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(isImporting)
        }
        .task { await computePreview() }
    }

    private var isImporting: Bool { if case .importing = stage { return true }; return false }
    private var isFinished: Bool { if case .done = stage { return true }; return false }

    // MARK: Preview

    private func previewContent(_ summary: FileImportService.Summary) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("\(summary.newRuns)")
                        .font(.etch(size: 60, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Text("new \(newActivityNoun(summary, capitalized: false)) ready to import")
                        .font(.etch(.headline))
                        .foregroundStyle(.secondary)
                    if let range = dateRange(summary) {
                        Text(range).font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 20)

                VStack(spacing: 0) {
                    detailRow("Activities found", "\(summary.found)", "doc.text")
                    if summary.newRuns - summary.withoutGPS > 0 {
                        divider
                        detailRow("With route maps", "\(summary.newRuns - summary.withoutGPS)", "map")
                    }
                    if summary.withoutGPS > 0 {
                        divider
                        detailRow("Without GPS", "\(summary.withoutGPS)", "location.slash")
                    }
                    if summary.duplicates > 0 {
                        divider
                        detailRow("Already in Etch", "\(summary.duplicates)", "checkmark.circle")
                    }
                    if !outcome.failedFiles.isEmpty {
                        divider
                        detailRow("Couldn't be read", "\(outcome.failedFiles.count)", "exclamationmark.triangle")
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 16))

                if !outcome.failedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(outcome.failedFiles, id: \.self) { name in
                            Text(name).font(.caption).foregroundStyle(.tertiary).lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if summary.newRuns > 0 { typeEditor }

                importButton(summary)
            }
            .padding(20)
        }
    }

    /// Per-activity type control shown before importing: each activity is pre-set to Etch's
    /// auto-detected type and can be overridden. Hidden for very large imports (a full export),
    /// which come in on auto-detection and can be re-typed later in run detail.
    @ViewBuilder
    private var typeEditor: some View {
        if !activities.isEmpty && activities.count <= typeEditorLimit {
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity type")
                    .font(.etch(.headline))
                Text("Etch auto-detects each activity. Tap to override.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(activities.indices, id: \.self) { i in
                        if i > 0 { divider }
                        typeRow(i)
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func typeRow(_ i: Int) -> some View {
        Menu {
            Picker("Activity", selection: $activities[i].activityType) {
                ForEach(typeChoices(including: activities[i].activityType), id: \.self) { t in
                    Label(t.detailLabel, systemImage: t.detailIcon).tag(t)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: activities[i].activityType.detailIcon)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(activities[i]))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(activities[i].startDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(activities[i].activityType.detailLabel)
                    .font(.etch(.subheadline))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
    }

    /// Run/Hike/Ride/Walk, plus the current type if it's something else, so the menu always shows
    /// a valid selection.
    private func typeChoices(including current: ActivityType) -> [ActivityType] {
        var base: [ActivityType] = [.run, .hike, .ride, .walk]
        if !base.contains(current) { base.append(current) }
        return base
    }

    private func displayName(_ a: ImportedActivity) -> String {
        if let n = a.name, !n.isEmpty { return n }
        return "Imported \(a.activityType.detailLabel)"
    }

    /// The noun for the import counts. When there's a single activity it uses that activity's type
    /// (Hike/Ride/…) so importing a hike doesn't read "Run"; batches use the generic "activity".
    private func newActivityNoun(_ summary: FileImportService.Summary, capitalized: Bool) -> String {
        let word: String
        if activities.count == 1 {
            word = activities[0].activityType.detailLabel
        } else {
            word = summary.newRuns == 1 ? "activity" : "activities"
        }
        return capitalized ? word.prefix(1).uppercased() + word.dropFirst() : word.lowercased()
    }

    @ViewBuilder
    private func importButton(_ summary: FileImportService.Summary) -> some View {
        if summary.newRuns > 0 {
            Button {
                Task { await runImport(summary) }
            } label: {
                Text("Import \(summary.newRuns) \(newActivityNoun(summary, capitalized: true))")
                    .font(.etch(.headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            Text(summary.found > 0 ? "Everything here is already in Etch." : "No activities found in these files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }

    // MARK: Importing

    private func importingContent(done: Int, total: Int) -> some View {
        VStack(spacing: 18) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .padding(.horizontal, 40)
            Text("Importing your history")
                .font(.etch(.headline))
            Text("\(done) / \(total)")
                .font(.etch(.title3, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: Results

    private func resultsContent(_ summary: FileImportService.Summary) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 30)
                Text(summary.newRuns > 0 ? "History added" : "Nothing new to add")
                    .font(.etch(.title2, weight: .bold))

                VStack(spacing: 0) {
                    detailRow("Activities added", "\(summary.newRuns)", "figure.run")
                    if summary.duplicates > 0 {
                        divider
                        detailRow("Already in Etch", "\(summary.duplicates)", "checkmark.circle")
                    }
                    if !summary.failedFiles.isEmpty {
                        divider
                        detailRow("Couldn't be read", "\(summary.failedFiles.count)", "exclamationmark.triangle")
                    }
                }
                .background(.regularMaterial, in: .rect(cornerRadius: 16))

                if !summary.failedFiles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.failedFiles, id: \.self) { name in
                            Text(name).font(.caption).foregroundStyle(.tertiary).lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.etch(.headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Theme.accent, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
    }

    // MARK: Pieces

    private func detailRow(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.etch(.subheadline, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var divider: some View {
        Divider().padding(.leading, 16)
    }

    private func dateRange(_ summary: FileImportService.Summary) -> String? {
        guard let earliest = summary.earliest, let latest = summary.latest else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        let a = f.string(from: earliest), b = f.string(from: latest)
        return a == b ? a : "\(a) – \(b)"
    }

    // MARK: Actions

    private func computePreview() async {
        guard case .loading = stage else { return }
        let service = FileImportService(context: context)
        var summary = service.preview(activities)
        summary.failedFiles = outcome.failedFiles
        stage = .preview(summary)
    }

    private func runImport(_ summary: FileImportService.Summary) async {
        stage = .importing(done: 0, total: summary.newRuns + summary.duplicates)
        let service = FileImportService(context: context)
        var result = await service.commit(activities) { done, total in
            stage = .importing(done: done, total: total)
        }
        result.failedFiles = outcome.failedFiles
        stage = .done(result)
        // Fill place names now, since a file import doesn't run a full sync: state/country fill
        // instantly (offline), cities begin filling in via the geocoder.
        await sync.enrichLocations()
    }
}
