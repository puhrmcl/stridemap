import SwiftUI

/// How much of the screen the control tray is claiming.
///
/// Three stops rather than a free drag: a poster editor has exactly three useful states — looking
/// at the artwork, working on it, and going deep — and a continuously resizable panel makes the
/// user responsible for finding them.
enum StudioTrayDetent: CaseIterable {
    /// The artwork owns the screen; only the section picker shows.
    case collapsed
    /// Normal editing. The poster stays clearly visible above.
    case medium
    /// Advanced controls, for when a sub-editor genuinely needs the room.
    case expanded

    /// Tray height for a given available height. Collapsed is a fixed chrome height because it
    /// holds fixed chrome; the other two are proportional so a Pro Max gets more working room and
    /// a small phone still keeps the poster on screen.
    func height(in total: CGFloat) -> CGFloat {
        switch self {
        case .collapsed: return 96
        case .medium:    return max(240, total * 0.44)
        case .expanded:  return max(320, total * 0.72)
        }
    }

    var next: StudioTrayDetent {
        switch self {
        case .collapsed: return .medium
        case .medium:    return .expanded
        case .expanded:  return .expanded
        }
    }

    var previous: StudioTrayDetent {
        switch self {
        case .collapsed: return .collapsed
        case .medium:    return .collapsed
        case .expanded:  return .medium
        }
    }
}

/// The editor's control surface: a grabber, a section picker, and whatever the active section
/// wants to show — sized to one of three detents, with the artwork persistent above it.
///
/// **Why this is not a `.sheet` with `presentationDetents`.** Studio is itself presented as a
/// sheet from the storefront, and a sheet presented over a sheet pushes the parent back and dims
/// it — which would take the poster, the one thing that must never leave, and grey it out behind
/// the controls. Detents also cannot be driven below their own presentation, so the collapsed
/// state could not keep the section picker live. An inline panel gives the same three stops with
/// the poster genuinely on screen and no stacking.
///
/// **Gesture safety.** The drag lives on the grabber and the section picker only, never on the
/// scrolling content. A drag that had to arbitrate with an inner `ScrollView` is where these
/// panels usually go wrong: the list rubber-bands when you meant to resize, or the panel resizes
/// when you meant to scroll. Confining it to the chrome means the two gestures can never contend,
/// and the panel cannot be dismissed by accident because it has no dismissed state — collapsed
/// still shows the picker.
struct StudioEditorTray<Content: View>: View {
    @Binding var detent: StudioTrayDetent
    let availableHeight: CGFloat
    @ViewBuilder var content: () -> Content

    @GestureState private var dragOffset: CGFloat = 0

    private var resolvedHeight: CGFloat {
        let base = detent.height(in: availableHeight)
        let dragged = base - dragOffset
        return min(max(dragged, StudioTrayDetent.collapsed.height(in: availableHeight)),
                   StudioTrayDetent.expanded.height(in: availableHeight))
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: resolvedHeight, alignment: .top)
        // Solid, not a material. A control tray is read, not looked through: over
        // `.regularMaterial` SwiftUI renders hierarchical styles with vibrancy, and in light mode
        // that took every secondary label, trailing value, chevron and divider in this panel down
        // to invisible — the b457 renders showed rows carrying an icon and a title and nothing
        // else. The concrete colours below are the other half of that fix.
        .background(Color(.systemBackground))
        .clipShape(.rect(topLeadingRadius: 20, topTrailingRadius: 20))
        .overlay(alignment: .top) {
            // A hairline rather than a shadow: the tray sits against the artwork, and a drop
            // shadow there reads as a second frame around the poster.
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
        }
        .animation(.interpolatingSpring(stiffness: 320, damping: 30), value: detent)
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragOffset) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        // Settle on the nearest stop, but let a decisive flick carry to the next
                        // one even when the finger did not travel far.
                        let target = resolvedHeight - value.predictedEndTranslation.height
                            + value.translation.height
                        detent = nearestDetent(to: target)
                    }
            )
            .onTapGesture { detent = detent == .collapsed ? .medium : .collapsed }
            .accessibilityLabel("Resize controls")
            .accessibilityAddTraits(.isButton)
    }

    private func nearestDetent(to height: CGFloat) -> StudioTrayDetent {
        StudioTrayDetent.allCases.min {
            abs($0.height(in: availableHeight) - height) < abs($1.height(in: availableHeight) - height)
        } ?? .medium
    }
}

// MARK: - Section picker

/// The editor's three sections. Ordered as the work is actually done: choose a starting point,
/// decide what the poster says, then refine how it says it.
enum StudioSection: String, CaseIterable, Identifiable {
    case design, content, customize
    var id: String { rawValue }

    var name: String {
        switch self {
        case .design:    return "Design"
        case .content:   return "Content"
        case .customize: return "Customize"
        }
    }
}

/// The section switch. An underlined row rather than a segmented control: this is navigation
/// between three workspaces, and a segmented control reads as picking one *value* out of three.
struct StudioSectionPicker: View {
    @Binding var section: StudioSection
    /// Raising the tray when a section is tapped from collapsed — tapping a section is a request
    /// to work in it.
    var onSelect: () -> Void

    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StudioSection.allCases) { s in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { section = s }
                    onSelect()
                } label: {
                    VStack(spacing: 6) {
                        Text(s.name)
                            .font(.system(.subheadline, design: .rounded)
                                .weight(section == s ? .semibold : .regular))
                            .foregroundStyle(section == s ? Theme.accent : Color.secondary)
                        ZStack {
                            Capsule().fill(.clear).frame(height: 2)
                            if section == s {
                                Capsule().fill(Theme.accent).frame(height: 2)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Shared control components

/// A drill-down row — the spine of Customize. Carries what it currently is, so the section can be
/// read without opening anything.
struct StudioDrillRow: View {
    let title: String
    var value: String?
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                }
                Text(title)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.55))
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A sub-editor's header: back to the list, and the name of where you are.
struct StudioDetailHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                    Text("Back").font(.system(.subheadline, design: .rounded))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            // Balances the title against the back button so it sits optically centred.
            Color.clear.frame(width: 52, height: 1)
        }
        .padding(.bottom, 6)
    }
}

/// A small caps section label, used across all three editors.
struct StudioGroupLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A selectable thumbnail card — the visual currency of the Design section. Takes any content as
/// its picture, so one component serves rendered posters, map swatches and palette chips.
struct StudioThumbCard<Picture: View>: View {
    let title: String
    let isSelected: Bool
    var width: CGFloat = 82
    var aspect: CGFloat = 2.0 / 3.0
    let action: () -> Void
    @ViewBuilder var picture: () -> Picture

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                picture()
                    .frame(width: width, height: width / aspect)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Theme.accent : Color.primary.opacity(0.10),
                                          lineWidth: isSelected ? 2 : 0.5)
                    }
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                    .lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
