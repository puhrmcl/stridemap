import SwiftUI

/// Three screens: what Under is, the spend rule, then who is using it.
/// The keyboard appears here and nowhere near a check-in.
struct OnboardingView: View {
    @EnvironmentObject private var store: UnderStore

    @State private var page = 0
    @State private var isCouple = false
    @State private var firstName = ""
    @State private var partnerName = ""
    @FocusState private var focused: Field?

    private enum Field { case first, partner }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark()
                Spacer()
                dots
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)

            ScrollView {
                Group {
                    switch page {
                    case 0: intro
                    case 1: rule
                    default: people
                    }
                }
                .padding(Theme.gutter)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Pages

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 40)
            Text("The daily check-in for staying under.")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.ink)
            Text("Five seconds in the evening. Was today a quiet day?")
                .font(.callout)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rule: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("What counts")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.ink)
            SpendRuleContent()
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Who is using Under?")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.ink)

            Picker("People", selection: $isCouple) {
                Text("Just me").tag(false)
                Text("Two people").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isCouple {
                VStack(spacing: 12) {
                    nameField("Your first name", text: $firstName, field: .first)
                    nameField("Their first name", text: $partnerName, field: .partner)
                }
                Text("Each person keeps their own log. Nobody answers for anybody else.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                Text("One name, one log, the same check-in.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private func nameField(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focused, equals: field)
            .font(.system(size: 17))
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
            )
    }

    // MARK: - Chrome

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.accent : Theme.hairline)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            AnswerButton(title: page == 2 ? "Start" : "Continue", emphasis: .leading) {
                advance()
            }
            .disabled(page == 2 && !canStart)
            .opacity(page == 2 && !canStart ? 0.5 : 1)

            if page > 0 {
                QuietLink(title: "Back") {
                    withAnimation(.easeInOut(duration: 0.18)) { page -= 1 }
                }
            }
        }
    }

    private var canStart: Bool {
        guard isCouple else { return true }
        return !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !partnerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func advance() {
        focused = nil
        if page < 2 {
            withAnimation(.easeInOut(duration: 0.18)) { page += 1 }
            return
        }
        guard canStart else { return }
        store.completeOnboarding(names: isCouple ? [firstName, partnerName] : ["You"])
        Reminder.requestAuthorization { granted in
            store.setReminder(on: granted)
        }
    }
}

#if DEBUG
#Preview {
    OnboardingView().environmentObject(UnderStore(storage: MemoryStorage()))
}
#endif
