import SwiftUI

/// The book's activities as a control surface — every activity the subject holds, grouped by the
/// chapter it falls in, each with a switch.
///
/// This closes the gap in the curation layer: the reader could already take a *photograph* out and
/// a *page* out, but never an activity. The test run logged by accident, the duplicate import, the
/// walk to the shop that a year of running does not need — all of it printed, in the chapter, in
/// the index and in the totals, with no way to say "not this one, not in this book".
///
/// Book-scoped and non-destructive. Hiding an activity in Settings removes it from the whole app;
/// this only says it is not part of *this* book, and the activity is untouched everywhere else.
struct BookActivitiesSheet: View {
    /// The plan built with NO activity exclusions applied — the complete list, so an excluded
    /// activity stays listed and can come back.
    let fullPlan: BookPlan
    @Binding var curation: BookCuration
    let onRepublish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var opening: BookCuration?

    private var hasChanges: Bool { opening.map { $0 != curation } ?? false }

    /// The activities grouped the way the book chapters them, oldest first.
    private var chapters: [(start: Date, runs: [Run])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: fullPlan.runs) {
            fullPlan.chapterSpan.start(of: $0.startDate, calendar)
        }
        return grouped.keys.sorted().map { ($0, (grouped[$0] ?? []).sorted { $0.startDate < $1.startDate }) }
    }

    private var includedCount: Int {
        fullPlan.runs.filter { curation.includesActivity($0) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // A real row rather than a header on an empty section: a section with no rows
                // renders as a stray gap on iOS.
                Section {
                    HStack {
                        Label("In the book", systemImage: "book.closed")
                        Spacer()
                        Text("\(includedCount) of \(fullPlan.runs.count)")
                            .font(.etch(.subheadline, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(includedCount == fullPlan.runs.count
                                             ? .secondary : Theme.accent)
                    }
                } footer: {
                    Text("Switching an activity off takes it out of this book only — its chapter, the index and the totals. It stays in Etch, and it still counts toward lifetime marks.")
                }

                ForEach(chapters, id: \.start) { chapter in
                    Section {
                        ForEach(chapter.runs, id: \.id) { run in
                            activityRow(run)
                        }
                    } header: {
                        chapterHeader(chapter)
                    }
                }
            }
            .navigationTitle("The Book's Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Include all") { curation.excludedRunIDs.removeAll() }
                        .disabled(curation.excludedRunIDs.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { republishBar }
            .onAppear { if opening == nil { opening = curation } }
        }
    }

    private func activityRow(_ run: Run) -> some View {
        Toggle(isOn: Binding(
            get: { curation.includesActivity(run) },
            set: { include in
                if include { curation.excludedRunIDs.remove(run.id) }
                else { curation.excludedRunIDs.insert(run.id) }
            }
        )) {
            HStack(spacing: 10) {
                Image(systemName: run.isRace ? "flag.checkered" : run.activityType.detailIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(run.isRace ? Theme.accent : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.name)
                        .lineLimit(1)
                        .foregroundStyle(curation.includesActivity(run) ? .primary : .secondary)
                    Text(activityDetail(run))
                        .font(.etch(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(Theme.accent)
    }

    private func activityDetail(_ run: Run) -> String {
        [shortDate(run.startDate), StatMetric.distance.value(for: run),
         run.photoReferences.isEmpty ? nil
            : "\(run.photoReferences.count) photo\(run.photoReferences.count == 1 ? "" : "s")"]
            .compactMap { $0 }
            .joined(separator: "  ·  ")
    }

    /// The chapter's name, its count, and one control that takes the whole chapter out. A month
    /// of twenty activities should not cost twenty taps to drop.
    private func chapterHeader(_ chapter: (start: Date, runs: [Run])) -> some View {
        let ids = Set(chapter.runs.map(\.id))
        let allOut = ids.isSubset(of: curation.excludedRunIDs)
        return HStack {
            Text(chapterName(chapter.start))
            Spacer()
            Button(allOut ? "Include month" : "Exclude month") {
                if allOut { curation.excludedRunIDs.subtract(ids) }
                else { curation.excludedRunIDs.formUnion(ids) }
            }
            .font(.etch(.caption, weight: .semibold))
            .textCase(nil)
            .foregroundStyle(Theme.accent)
        }
    }

    private func chapterName(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch fullPlan.chapterSpan {
        case .year:  formatter.dateFormat = "yyyy"
        case .month: formatter.dateFormat = fullPlan.chapterNamesYear ? "MMMM yyyy" : "MMMM"
        }
        return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private var republishBar: some View {
        Button {
            curation.save(slug: fullPlan.slug)
            onRepublish()
            dismiss()
        } label: {
            Label(hasChanges ? "Republish the book" : "No changes yet",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.etch(.subheadline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.accent.opacity(hasChanges ? 1 : 0.35),
                            in: .rect(cornerRadius: 14))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
