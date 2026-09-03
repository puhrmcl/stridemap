import SwiftUI

/// Tapping a day opens this. Only today is editable, and only your own bucket.
/// A closed day shows its marks and nothing else — no names, no words, no
/// comments, no "want to talk about it?".
struct DayDetailView: View {
    @EnvironmentObject private var store: UnderStore
    @Environment(\.dismiss) private var dismiss

    let dayKey: String

    init(dayKey: String) {
        self.dayKey = dayKey
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(title)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(Theme.ink)

                    marks

                    if isToday, let me = store.activePerson {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(store.todayBucket(for: me.id) == nil ? "Your day" : "Change your day")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSoft)
                            CheckInView(person: me) { dismiss() }
                        }
                    } else {
                        Text("This day is closed.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(Theme.gutter)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents(isToday ? [.large] : [.medium])
    }

    private var marks: some View {
        VStack(spacing: 8) {
            ForEach(store.people) { person in
                DayMark(bucket: store.bucket(for: person.id, on: dayKey),
                        height: store.isCouple ? 14 : 22)
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var isToday: Bool { dayKey == store.today }

    private var title: String {
        guard let date = DayKey.date(from: dayKey) else { return "" }
        if isToday { return "Today" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }
}

#if DEBUG
#Preview {
    DayDetailView(dayKey: DayKey.today())
        .environmentObject(UnderStore.previewCouple)
}
#endif
