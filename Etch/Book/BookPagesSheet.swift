import SwiftUI

/// The book's table of contents as a control surface — every page listed by name, each
/// non-structural one with a visibility toggle. The pager's touch-and-hold hides a page in
/// passing; this sheet is where the whole book is surveyed, including the pages already
/// hidden (which the pager, by definition, can no longer show).
struct BookPagesSheet: View {
    /// The plan with NO hidden pages applied — the complete table of contents, so a hidden
    /// page stays listed and can come back individually.
    let fullPlan: BookPlan
    @Binding var curation: BookCuration
    let onRepublish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var opening: BookCuration?

    private var hasChanges: Bool { opening.map { $0 != curation } ?? false }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(fullPlan.pages.enumerated()), id: \.offset) { index, spec in
                        if !isBlank(spec) { row(index: index, spec: spec) }
                    }
                } footer: {
                    Text("The cover, title, record and closing always print — a book keeps its spine. Hidden pages are replanned away; blank leaves fill to the binder's minimum.")
                }
            }
            .navigationTitle("The Book's Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { republishBar }
            .onAppear { if opening == nil { opening = curation } }
        }
    }

    @ViewBuilder
    private func row(index: Int, spec: BookPageSpec) -> some View {
        if let key = fullPlan.hideKey(at: index) {
            Toggle(isOn: Binding(
                get: { !curation.hiddenPages.contains(key) },
                set: { include in
                    if include { curation.hiddenPages.remove(key) }
                    else { curation.hiddenPages.insert(key) }
                }
            )) {
                Text(pageTitle(spec))
                    .foregroundStyle(curation.hiddenPages.contains(key) ? .secondary : .primary)
            }
            .tint(Theme.accent)
        } else {
            HStack {
                Text(pageTitle(spec))
                Spacer()
                Image(systemName: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func isBlank(_ spec: BookPageSpec) -> Bool {
        if case .blank = spec { return true }
        return false
    }

    private func pageTitle(_ spec: BookPageSpec) -> String {
        switch spec {
        case .cover:                    return "Cover"
        case .title:                    return "Title page"
        case .stats:                    return "Statistics"
        case .marks:                    return "The Marks"
        case .map:                      return "The Map"
        case .chapter(let start):       return chapterName(start)
        case .chapterPhotos(let start): return "\(chapterName(start)) — in pictures"
        case .race(let index):
            return "Race — \(fullPlan.run(at: index)?.name ?? "")"
        case .gallery:                  return "In Pictures"
        case .numbers:                  return "The Numbers"
        case .review:                   return "The Review"
        case .years:                    return "The Years"
        case .raceHistory:              return "Race History"
        case .atlas:                    return "The Atlas"
        case .cities:                   return "The Cities"
        case .index:                    return "The Record (index)"
        case .closing:                  return "Closing"
        case .blank:                    return "Blank leaf"
        case .backCover:                return "Back cover"
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
