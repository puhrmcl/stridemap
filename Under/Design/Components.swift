import SwiftUI

/// The wordmark. The app is called Under; nothing else in the product is.
struct Wordmark: View {
    var body: some View {
        Text("Under")
            .font(.system(size: 19, weight: .semibold))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A large, unmissable answer. Two of these are the whole check-in.
struct AnswerButton: View {
    enum Emphasis { case leading, plain }

    let title: String
    var emphasis: Emphasis = .plain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .fill(emphasis == .leading ? Theme.accent.opacity(0.14) : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .stroke(emphasis == .leading ? Theme.accent.opacity(0.35) : Theme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// A quiet text link. Used for "Back", "What counts?", "This week".
struct QuietLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One person's mark for one day. No number, no name, no words.
struct DayMark: View {
    let bucket: Bucket?
    var height: CGFloat = 18
    var isPlaceholder: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: max(3, height / 2.8), style: .continuous)
            .fill(fill)
            .frame(height: height)
            .opacity(isPlaceholder ? 0 : 1)
    }

    private var fill: Color {
        guard let bucket else { return Theme.emptyMark }
        return bucket.color
    }
}

/// A person's name as a tap target. Tapping the other name switches to them.
struct PersonPill: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Theme.ink : Theme.inkSoft)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? Theme.surface : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isActive ? Theme.hairline : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(name), checking in" : "Switch to \(name)")
    }
}
