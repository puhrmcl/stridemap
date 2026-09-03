import SwiftUI

/// The whole product: one to three taps, no keyboard, ever.
///
/// "Spend today?" No  -> none
/// "Under $25?"  Yes  -> low
/// "Under $100?" Yes  -> mid, No -> high
///
/// Exactly $25 is low. Exactly $100 is mid. In steps two and three the leading
/// answer is Yes.
struct CheckInView: View {
    @EnvironmentObject private var store: UnderStore

    let person: Person
    let onComplete: () -> Void

    @State private var step: Step = .spend
    @State private var showingRule = false

    private enum Step { case spend, underTwentyFive, underHundred }

    init(person: Person, onComplete: @escaping () -> Void = {}) {
        self.person = person
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(question)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                AnswerButton(title: leadingTitle, emphasis: .leading) { answerLeading() }
                AnswerButton(title: trailingTitle) { answerTrailing() }
            }

            HStack(spacing: 20) {
                if step != .spend {
                    QuietLink(title: "Back") { back() }
                }
                QuietLink(title: "What counts?") { showingRule = true }
                Spacer(minLength: 0)
            }
        }
        .sheet(isPresented: $showingRule) {
            SpendRuleView(showsDoneButton: true)
        }
    }

    // MARK: - Copy

    private var question: String {
        switch step {
        case .spend: return "Spend today?"
        case .underTwentyFive: return "Under $25?"
        case .underHundred: return "Under $100?"
        }
    }

    private var leadingTitle: String {
        switch step {
        case .spend: return "No"
        case .underTwentyFive, .underHundred: return "Yes"
        }
    }

    private var trailingTitle: String {
        switch step {
        case .spend: return "Yes"
        case .underTwentyFive, .underHundred: return "No"
        }
    }

    // MARK: - Answers

    private func answerLeading() {
        switch step {
        case .spend: log(Bucket.none)
        case .underTwentyFive: log(Bucket.low)
        case .underHundred: log(Bucket.mid)
        }
    }

    private func answerTrailing() {
        switch step {
        case .spend: advance(to: .underTwentyFive)
        case .underTwentyFive: advance(to: .underHundred)
        case .underHundred: log(Bucket.high)
        }
    }

    private func back() {
        switch step {
        case .spend: break
        case .underTwentyFive: advance(to: .spend)
        case .underHundred: advance(to: .underTwentyFive)
        }
    }

    private func advance(to next: Step) {
        withAnimation(.easeInOut(duration: 0.18)) { step = next }
    }

    private func log(_ bucket: Bucket) {
        store.log(bucket, for: person.id)
        step = .spend
        onComplete()
    }
}

#if DEBUG
#Preview {
    CheckInView(person: UnderStore.previewCouple.people[0])
        .environmentObject(UnderStore.previewCouple)
        .padding(24)
}
#endif
