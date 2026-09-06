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
                .font(.etch(.title3, weight: .bold))
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
                    .font(.etch(.subheadline, weight: .semibold))
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
///
/// `Show on Map` is the one deliberate specialization: the Home header was simplified to a single
/// summary disclosure, so that disclosure must still provide both halves of the old control —
/// *what activity* and *what view*. The activity choice lives here as a compact strip above the
/// view tiles instead of returning a second permanent control to the map chrome.
struct EtchSelectionSheet: View {
    let title: String
    let options: [SelectionOption]
    var columns: Int = 3
    let onClose: () -> Void

    @Environment(AppModel.self) private var appModel

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

    /// The Home summary opens `Show on Map`; when more than one concrete activity type is enabled,
    /// that sheet carries a compact activity strip so Runs / Hikes / Rides / Walks never become an
    /// orphaned capability after the header simplification.
    private var showsActivityStrip: Bool {
        title == "Show on Map" && ActivitySettings.visibleScopes.filter { $0 != .all }.count > 1
    }

    private var activityStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity")
                .font(.etch(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ActivitySettings.visibleScopes) { scope in
                        let selected = appModel.activityScope == scope
                        Button {
                            withAnimation(Theme.gentle) { appModel.activityScope = scope }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: scope.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(scope == .all ? "All" : scope.label)
                                    .font(.etch(.footnote, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? Theme.accent : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                selected ? Theme.accent.opacity(0.14) : Color.secondary.opacity(0.10),
                                in: .capsule
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Activity Type, \(scope == .all ? "All Activities" : scope.label)")
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
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
        // The activity strip consumes a little of the available card height; trim the tile area
        // rather than letting the whole card climb under the header on compact phones.
        let fraction = showsActivityStrip ? 0.38 : 0.46
        return max(200, screen * fraction)
    }

    private var card: some View {
        VStack(spacing: 18) {
            SelectionSheetHeader(title: title, onClose: onClose)

            if showsActivityStrip {
                activityStrip
                Divider()
                Text("View")
                    .font(.etch(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
