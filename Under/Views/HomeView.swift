import SwiftUI

/// If you have not logged today, home *is* your check-in. If you have, home is
/// your streak and the calendar. Never "Waiting on [Name]", never two numbers
/// side by side.
struct HomeView: View {
    @EnvironmentObject private var store: UnderStore

    @State private var sheet: HomeSheet?

    /// One sheet slot, so two presentations can never fight.
    private enum HomeSheet: Identifiable {
        case settings
        case recap
        case day(String)

        var id: String {
            switch self {
            case .settings: return "settings"
            case .recap: return "recap"
            case .day(let key): return "day-" + key
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header

                if store.isCouple {
                    peopleRow
                }

                if let me = store.activePerson {
                    if let bucket = store.todayBucket(for: me.id) {
                        logged(me, bucket: bucket)
                    } else {
                        CheckInView(person: me)
                            .padding(.top, 24)
                    }
                }
            }
            .padding(Theme.gutter)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $sheet) { item in
            switch item {
            case .settings: SettingsView()
            case .recap: RecapView()
            case .day(let key): DayDetailView(dayKey: key)
            }
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            Wordmark()
            Spacer()
            Button {
                sheet = .settings
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    /// One tap switches who is checking in. Two names, no numbers.
    private var peopleRow: some View {
        HStack(spacing: 8) {
            ForEach(store.people) { person in
                PersonPill(name: store.displayName(person),
                           isActive: person.id == store.activePerson?.id) {
                    store.setActivePerson(person.id)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Logged state

    @ViewBuilder
    private func logged(_ me: Person, bucket: Bucket) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            // Quiet days get a word. Mid and high get a colour on the calendar,
            // then silence.
            if bucket.isQuiet {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Quiet day.")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Theme.ink)

                    streakBlock(for: me)
                }
                .padding(.top, 8)
            }

            MonthCalendarView { key in
                sheet = .day(key)
            }
            .padding(.top, bucket.isQuiet ? 0 : 12)

            HStack(spacing: 20) {
                QuietLink(title: "Change today") { sheet = .day(store.today) }
                QuietLink(title: "This week") { sheet = .recap }
                Spacer(minLength: 0)
            }
        }
    }

    /// Your streak only. Never yours next to theirs.
    @ViewBuilder
    private func streakBlock(for me: Person) -> some View {
        let streak = store.streak(for: me.id)
        if streak > 0 {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)")
                    .font(.system(size: 68, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(streak == 1 ? "quiet day in a row" : "quiet days in a row")
                    .font(.callout)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

#if DEBUG
#Preview("Couple") {
    HomeView().environmentObject(UnderStore.previewCouple)
}

#Preview("Solo") {
    HomeView().environmentObject(UnderStore.previewSolo)
}
#endif
