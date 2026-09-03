import SwiftUI

/// One household, one rulebook. Shown once at first launch, then available from
/// the check-in and from Settings. Read-only, everywhere.
struct SpendRuleContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text(SpendRule.headline)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.ink)
                Text(SpendRule.subhead)
                    .font(.callout)
                    .foregroundStyle(Theme.inkSoft)
            }

            list(title: SpendRule.doesNotCountTitle, items: SpendRule.doesNotCount, aside: SpendRule.doesNotCountAside)
            list(title: SpendRule.countsTitle, items: SpendRule.counts, aside: nil)

            VStack(alignment: .leading, spacing: 8) {
                Text(SpendRule.choiceTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(SpendRule.choiceBody)
                    .font(.callout)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(title: String, items: [String], aside: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.inkSoft)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(Theme.accent.opacity(0.5))
                            .frame(width: 4, height: 4)
                        Text(item)
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                    }
                }
            }

            if let aside {
                Text(aside)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 2)
            }
        }
    }
}

/// The rule as its own screen: a sheet from the check-in, a page from Settings.
struct SpendRuleView: View {
    let showsDoneButton: Bool

    @Environment(\.dismiss) private var dismiss

    init(showsDoneButton: Bool = false) {
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        if showsDoneButton {
            NavigationStack {
                scroller
                    .navigationTitle("What counts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
            }
        } else {
            scroller
                .navigationTitle("What counts")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var scroller: some View {
        ScrollView {
            SpendRuleContent()
                .padding(Theme.gutter)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    SpendRuleView(showsDoneButton: true)
}
#endif
