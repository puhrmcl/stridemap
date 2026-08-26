import SwiftUI
import SwiftData

/// The Year Book — a whole year of activity composed into Prodigi's layflat A4-landscape book.
/// This surface previews every page (cover → months → races → back cover) and exports a
/// print-ready proof PDF; in-app ordering joins once the book order pipeline is wired.
struct YearBookView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Run.startDate) private var allRuns: [Run]

    @State private var year: Int = Calendar.current.component(.year, from: .now)
    @State private var didSeedYear = false
    /// Rendered page previews, by page index, for the current plan.
    @State private var previews: [Int: UIImage] = [:]
    @State private var currentPage = 0

    @State private var isExporting = false
    @State private var exportProgress: (Int, Int) = (0, 0)
    @State private var proofURL: URL?

    private var years: [Int] {
        Array(Set(allRuns.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private var plan: BookPlan { BookPlan.make(year: year, runs: allRuns) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if years.isEmpty {
                    ContentUnavailableView("No activities yet",
                                           systemImage: "book.closed",
                                           description: Text("The Year Book composes itself from a year of activities."))
                } else {
                    yearPicker
                    pager
                    footer
                }
            }
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Year Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .task(id: year) { await renderPreviews() }
            .onAppear {
                // Open on the most recent year that has activity.
                if !didSeedYear, let latest = years.first {
                    didSeedYear = true
                    year = latest
                }
            }
        }
    }

    private var yearPicker: some View {
        Picker("Year", selection: $year) {
            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .disabled(isExporting)
    }

    /// The book as a swipeable pager — each card is one page at the true A4-landscape aspect.
    private var pager: some View {
        TabView(selection: $currentPage) {
            ForEach(plan.pages.indices, id: \.self) { index in
                Group {
                    if let image = previews[index] {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.Palette.bone)
                            .aspectRatio(BookCatalog.pageSize.width / BookCatalog.pageSize.height,
                                         contentMode: .fit)
                            .overlay(ProgressView())
                    }
                }
                .padding(.horizontal, 22)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("Page \(currentPage + 1) of \(plan.pageCount)  ·  \(BookCatalog.name)  ·  \(BookCatalog.price)")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)

            if let proofURL {
                ShareLink(item: proofURL) {
                    Label("Share Proof PDF", systemImage: "square.and.arrow.up")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.accent, in: .capsule)
                }
            } else {
                Button { export() } label: {
                    Group {
                        if isExporting {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Rendering page \(exportProgress.0) of \(exportProgress.1)…")
                            }
                        } else {
                            Label("Export Proof PDF", systemImage: "doc.richtext")
                        }
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isExporting || plan.runs.isEmpty)
            }

            Text("\(BookCatalog.material) Ordering opens closer to launch — the proof PDF is print-exact.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    /// Preview pages render sequentially at a light scale; the pager fills in as they land.
    private func renderPreviews() async {
        previews = [:]
        currentPage = 0
        proofURL = nil
        let plan = plan
        for index in plan.pages.indices {
            if Task.isCancelled { return }
            if let image = await BookRenderer.pageImage(plan: plan, page: index, scale: 0.45) {
                previews[index] = image
            }
        }
    }

    private func export() {
        guard !isExporting else { return }
        isExporting = true
        let plan = plan
        Task {
            let url = await BookRenderer.exportPDF(plan: plan) { done, total in
                exportProgress = (done, total)
            }
            isExporting = false
            proofURL = url
        }
    }
}
