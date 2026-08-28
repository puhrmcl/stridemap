import SwiftUI

/// One choice in an `EtchSelectionSheet` — an icon, a label, whether it's currently selected, a full
/// VoiceOver label, and what to do when picked.
struct SelectionOption: Identifiable {
    let id: String
    let icon: String
    let label: String
    let isSelected: Bool
    /// Full VoiceOver label, e.g. "Activity Type, Runs".
    let accessibilityLabel: String
    let action: () -> Void
}

/// The shared header for a selection sheet: a centred title with a trailing circular close button —
/// matching the Map Type sheet exactly.
struct SelectionSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
    }
}

/// A single rounded selection tile: an icon over a tinted card with a label beneath, taking the Map
/// Type sheet's selected-blue-accent treatment.
struct SelectionTile: View {
    let option: SelectionOption
    let width: CGFloat

    var body: some View {
        Button(action: option.action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(option.isSelected ? Theme.accent.opacity(0.16) : Color.secondary.opacity(0.12))
                    .frame(width: width, height: max(56, width * 0.78))
                    .overlay(
                        Image(systemName: option.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(option.isSelected ? Theme.accent : .primary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(option.isSelected ? Theme.accent : Color.clear, lineWidth: 2.5)
                    )
                Text(option.label)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(option.isSelected ? Theme.accent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityLabel)
        .accessibilityAddTraits(option.isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A bottom sheet of selection tiles matching the Map Type sheet — a dimmed backdrop with a
/// rounded-top glass card, a titled header, and the tiles laid out in centred rows of `columns`.
/// Incomplete rows (e.g. two tiles across three columns) centre. Tap the backdrop or the close
/// button to dismiss.
struct EtchSelectionSheet: View {
    let title: String
    let options: [SelectionOption]
    var columns: Int = 3
    let onClose: () -> Void

    /// Measured content width, so tiles size to the screen (compact on an SE, capped on large phones)
    /// and incomplete rows centre with consistent tile widths.
    @State private var contentWidth: CGFloat = 320
    private let spacing: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            card.transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var rows: [[SelectionOption]] {
        stride(from: 0, to: options.count, by: columns).map {
            Array(options[$0 ..< min($0 + columns, options.count)])
        }
    }

    private var tileWidth: CGFloat {
        min(116, (contentWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// The tallest a sheet's tiles may grow before they scroll instead.
    ///
    /// Activity View carries nine options — All, Recent, PRs, Races, Favorites, then a tile per
    /// place map — which is three rows, and it is the sheet that found this. Clearing the tab bar
    /// moves a too-tall card up rather than making it fit, so without a ceiling the fix for the
    /// bottom row would eventually push the header off the top instead. A cap turns "too many
    /// options" into a scroll, which is a thing a person can deal with, rather than a clipped row,
    /// which is a thing they cannot.
    private var maxTileAreaHeight: CGFloat {
        let screen = UIScreen.main.bounds.height
        return max(220, screen * 0.46)
    }

    private var card: some View {
        VStack(spacing: 18) {
            SelectionSheetHeader(title: title, onClose: onClose)
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: spacing) {
                            ForEach(row) { SelectionTile(option: $0, width: tileWidth) }
                        }
                        .frame(maxWidth: .infinity)   // centre incomplete rows
                    }
                }
                .background(
                    GeometryReader { g in
                        Color.clear
                            .onAppear { contentWidth = g.size.width }
                            .onChange(of: g.size.width) { _, w in contentWidth = w }
                    }
                )
            }
            // Only scrolls when it has to: a three-tile sheet keeps its natural height and does
            // not bounce, so the common case is unchanged.
            .frame(maxHeight: maxTileAreaHeight)
            .scrollBounceBehavior(.basedOnSize)
        }
        .bottomDockedCard()
    }
}
