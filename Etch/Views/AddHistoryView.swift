import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// "Add Your History": bring runs into Etch from files exported by other apps. Provider rows
/// expand to show where to get an export; every path lands in the same document picker →
/// preview → import. Everything is processed on-device.
struct AddHistoryView: View {
    @Environment(\.modelContext) private var context

    @State private var pickerPresented = false
    @State private var isParsing = false
    @State private var session: PreviewSession?

    var body: some View {
        List {
            Section {
                ForEach(ImportGuide.providers) { guide in
                    ProviderRow(guide: guide) { pickerPresented = true }
                }
            } header: {
                Text("Import from another app")
            } footer: {
                Text("Choose your app to see where to download your history.")
            }

            Section {
                Button {
                    pickerPresented = true
                } label: {
                    Label("Choose Activity Files", systemImage: "doc.badge.plus")
                        .foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Import files")
            } footer: {
                Text("Select .fit, .gpx, or .tcx files, or a .zip export from another app.")
            }

            Section {
                Label {
                    Text("Your files are read on this device only — nothing is uploaded.")
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(.green)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add Your History")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $pickerPresented,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true,
            onCompletion: handlePick
        )
        .sheet(item: $session) { session in
            ImportPreviewView(outcome: session.outcome)
        }
        .overlay {
            if isParsing {
                ProgressView("Reading files…")
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
    }

    /// GPX/TCX are XML under the hood; include their extension-derived types plus `.xml` so
    /// the picker surfaces them even though iOS declares no system UTI for either.
    private static let allowedTypes: [UTType] = {
        var types: [UTType] = ["gpx", "tcx", "fit"].compactMap { UTType(filenameExtension: $0) }
        types.append(.xml)
        types.append(.zip)
        return types
    }()

    private func handlePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        isParsing = true
        Task {
            let service = FileImportService(context: context)
            let outcome = await service.parse(urls: urls)
            isParsing = false
            session = PreviewSession(outcome: outcome)
        }
    }
}

/// Carries a parse result into the preview sheet.
struct PreviewSession: Identifiable {
    let id = UUID()
    let outcome: FileImportService.ParseOutcome
}

// MARK: - Provider guidance

/// Where to find a given app's export. Purely instructional — every provider ends at the
/// same file picker, since the files themselves are what Etch parses.
struct ImportGuide: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let steps: [String]
    let note: String?

    static let providers: [ImportGuide] = [
        ImportGuide(
            id: "nike", name: "Nike Run Club", symbol: "figure.run.circle",
            steps: [
                "Sign in at nike.com and open your Privacy settings.",
                "Request a copy of your data, then download the .zip Nike emails you.",
                "Choose that .zip here — Etch reads your runs from inside it."
            ],
            note: "No need to unzip — pick the file exactly as Nike sends it."
        ),
        ImportGuide(
            id: "garmin", name: "Garmin", symbol: "dot.radiowaves.left.and.right",
            steps: [
                "Sign in at connect.garmin.com.",
                "Open an activity and export the original .fit (or .tcx / .gpx), or request a full data export.",
                "Choose the downloaded files or .zip here."
            ],
            note: nil
        ),
        ImportGuide(
            id: "coros", name: "COROS", symbol: "dot.radiowaves.left.and.right",
            steps: [
                "Open your COROS web dashboard and sign in.",
                "Open an activity and export it as .fit or .gpx.",
                "Choose the downloaded files here."
            ],
            note: nil
        ),
        ImportGuide(
            id: "other", name: "Other fitness app", symbol: "square.and.arrow.down",
            steps: [
                "Most apps can export a run as .gpx or .tcx.",
                "Save the files to your phone (Files, iCloud Drive, or AirDrop).",
                "Choose them here."
            ],
            note: nil
        )
    ]
}

/// One expandable provider row: tap to reveal the steps, then Choose Files.
private struct ProviderRow: View {
    let guide: ImportGuide
    let onChooseFiles: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 18, alignment: .center)
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let note = guide.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                Button(action: onChooseFiles) {
                    Label("Choose Files", systemImage: "doc.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
        } label: {
            Label(guide.name, systemImage: guide.symbol)
        }
    }
}
