import SwiftUI

/// The shared calendar. Solo shows one mark a day; two people show two
/// independent marks, in a fixed order, never averaged into one household
/// colour. A high day is a colour, then silence — no names, no words.
struct MonthCalendarView: View {
    @EnvironmentObject private var store: UnderStore

    let onSelectDay: (String) -> Void

    @State private var anchor = Date()

    private var calendar: Calendar { Calendar.current }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 6), count: 7) }

    init(onSelectDay: @escaping (String) -> Void = { _ in }) {
        self.onSelectDay = onSelectDay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if store.isCouple {
                Text(rowLegend)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                // Indexed, because weekday initials repeat (S, T).
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSoft)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(cells.enumerated()), id: \.offset) { item in
                    dayCell(for: item.element)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.inkSoft)
            .accessibilityLabel("Previous month")

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoForward ? Theme.inkSoft : Theme.hairline)
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(isCurrentYear ? "LLLL" : "LLLL yyyy")
        return formatter.string(from: anchor)
    }

    private var isCurrentYear: Bool {
        calendar.component(.year, from: anchor) == calendar.component(.year, from: Date())
    }

    private var rowLegend: String {
        let names = store.people.map { store.displayName($0) }
        guard names.count >= 2 else { return "" }
        return "Top \(names[0]) \u{00B7} Bottom \(names[1])"
    }

    // MARK: - Grid

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Leading blanks, then every day of the month.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor),
              let dayCount = calendar.range(of: .day, in: .month, for: anchor)?.count else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days = [Date?](repeating: nil, count: leading)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: first))
        }
        return days
    }

    @ViewBuilder
    private func dayCell(for date: Date?) -> some View {
        if let date {
            let key = DayKey.key(from: date, calendar: calendar)
            DayCellView(dayKey: key,
                        dayNumber: calendar.component(.day, from: date),
                        isToday: key == store.today,
                        isFuture: key > store.today)
                .contentShape(Rectangle())
                .onTapGesture {
                    if key <= store.today { onSelectDay(key) }
                }
        } else {
            Color.clear.frame(height: 44)
        }
    }

    // MARK: - Month navigation

    private var canGoForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: anchor) else { return false }
        return next <= Date()
    }

    private func shiftMonth(by value: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: value, to: anchor) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { anchor = shifted }
    }
}

/// One day: the number, then one mark per person. Future days carry no marks.
struct DayCellView: View {
    @EnvironmentObject private var store: UnderStore

    let dayKey: String
    let dayNumber: Int
    let isToday: Bool
    let isFuture: Bool

    init(dayKey: String, dayNumber: Int, isToday: Bool, isFuture: Bool) {
        self.dayKey = dayKey
        self.dayNumber = dayNumber
        self.isToday = isToday
        self.isFuture = isFuture
    }

    var body: some View {
        VStack(spacing: 5) {
            Text("\(dayNumber)")
                .font(.system(size: 11, weight: isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Theme.ink : Theme.inkSoft)

            VStack(spacing: 3) {
                ForEach(store.people) { person in
                    DayMark(bucket: store.bucket(for: person.id, on: dayKey),
                            height: store.isCouple ? 8 : 16,
                            isPlaceholder: isFuture)
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 2)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isToday ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                .padding(.horizontal, -1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Spoken labels stay as neutral as the colours: your own day is named,
    /// the other person's is only "logged".
    private var accessibilityText: String {
        guard !isFuture else { return "Day \(dayNumber)" }
        var parts = ["Day \(dayNumber)"]
        if let me = store.activePerson {
            if let bucket = store.bucket(for: me.id, on: dayKey) {
                parts.append("you, \(bucket.label.lowercased())")
            } else {
                parts.append("you, not logged")
            }
        }
        if let other = store.partner {
            parts.append(store.bucket(for: other.id, on: dayKey) == nil ? "partner, not logged" : "partner, logged")
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview {
    MonthCalendarView()
        .environmentObject(UnderStore.previewCouple)
        .padding(24)
}
#endif
