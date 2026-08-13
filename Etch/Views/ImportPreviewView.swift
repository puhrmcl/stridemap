import SwiftUI
import SwiftData

/// The confirmation step between parsing files and writing runs: shows what was found, lets
/// the user commit or cancel, streams progress during the import, then reports the result.
struct ImportPreviewView: View {
    let outcome: FileImportService.ParseOutcome

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Text(summary.newRuns == 1 ? "new run ready to import" : "new runs ready to import")
                        .font(.system(.headline, design: .rounded))
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

                importButton(summary)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func importButton(_ summary: FileImportService.Summary) -> some View {
        if summary.newRuns > 0 {
            Button {
                Task { await runImport(summary) }
            } label: {
                Text("Import \(summary.newRuns) \(summary.newRuns == 1 ? "Run" : "Runs")")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.accent, in: .rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else {
            Text(summary.found > 0 ? "Everything here is already in Etch." : "No runs found in these files.")
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
                .font(.system(.headline, design: .rounded))
            Text("\(done) / \(total)")
                .font(.system(.title3, design: .rounded).weight(.semibold))
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
                    .font(.system(.title2, design: .rounded).weight(.bold))

                VStack(spacing: 0) {
                    detailRow("Runs added", "\(summary.newRuns)", "figure.run")
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
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary.failedFiles, id: \.self) { name in
                            Text(name).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { dismiss() } label: {
                    Text("Done")
                        .font(.system(.headline, design: .rounded))
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
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
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
        var summary = service.preview(outcome.activities)
        summary.failedFiles = outcome.failedFiles
        stage = .preview(summary)
    }

    private func runImport(_ summary: FileImportService.Summary) async {
        stage = .importing(done: 0, total: summary.newRuns + summary.duplicates)
        let service = FileImportService(context: context)
        var result = await service.commit(outcome.activities) { done, total in
            stage = .importing(done: done, total: total)
        }
        result.failedFiles = outcome.failedFiles
        stage = .done(result)
    }
}
