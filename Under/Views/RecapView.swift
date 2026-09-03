import SwiftUI

/// Opened by choice, never pushed. A count of your quiet days — never dollars,
/// never a comparison, never a badge.
struct RecapView: View {
    @EnvironmentObject private var store: UnderStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("This week")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)

                Text(mine)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.ink)

                if let together = together {
                    Text(together)
                        .font(.callout)
                        .foregroundStyle(Theme.inkSoft)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.gutter)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private var mine: String {
        guard let me = store.activePerson else { return "" }
        let count = store.quietDays(for: me.id)
        return count == 1 ? "1 quiet day." : "\(count) quiet days."
    }

    /// A single together-line, and only because you opened this screen.
    private var together: String? {
        guard store.isCouple else { return nil }
        let total = store.people.reduce(into: 0) { sum, person in
            sum += store.quietDays(for: person.id)
        }
        return total == 1 ? "Together, 1 quiet day." : "Together, \(total) quiet days."
    }
}

#if DEBUG
#Preview {
    RecapView()
        .environmentObject(UnderStore.previewCouple)
}
#endif
