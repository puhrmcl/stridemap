import SwiftUI

/// The UI elements from the Etch Brand System sheet, built as real components.
///
/// The sheet specifies six things by drawing them: a primary pill, a circular icon button, a
/// segmented control, an activity card, a stat strip, and the tracked metadata line that runs
/// under a poster. This file is those six, so a screen can be *composed* of them rather than
/// approximating them one padding value at a time.
///
/// Everything here reads `Theme` and the type tokens. There are no literal colours, sizes chosen
/// by eye, or fonts named directly — if the brand moves, these move with it.

// MARK: - Primary action

/// The brand's primary control: a capsule in Etch Blue with a Gallery White label, set in
/// sentence case at medium weight.
///
/// The fill is `accentFill` rather than the brand blue itself. `#4A8EAE` under a white label is
/// 3.53:1 — the one place in the system where the signature colour cannot be used raw, because
/// here it is carrying text. The deepened tone is visually indistinguishable and clears AA.
struct EtchPrimaryButtonStyle: ButtonStyle {
    /// Fills the available width. Off by default: the sheet draws the pill at its content's
    /// width, and a button that always spans the screen reads as a form, not an invitation.
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.etch(.callout, weight: .etchMedium))
            .foregroundStyle(Theme.Ink.onAccent)
            .padding(.vertical, 14)
            .padding(.horizontal, 26)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Theme.accentFill, in: .capsule)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(Theme.gentle, value: configuration.isPressed)
    }
}

/// The quiet counterpart: the same capsule as an outline, for a secondary action beside a
/// primary one.
struct EtchSecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.etch(.callout, weight: .etchMedium))
            .foregroundStyle(Theme.accentText)
            .padding(.vertical, 14)
            .padding(.horizontal, 26)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                Capsule().strokeBorder(Theme.accent, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Theme.gentle, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == EtchPrimaryButtonStyle {
    static var etchPrimary: EtchPrimaryButtonStyle { EtchPrimaryButtonStyle() }
    static func etchPrimary(fullWidth: Bool) -> EtchPrimaryButtonStyle {
        EtchPrimaryButtonStyle(fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == EtchSecondaryButtonStyle {
    static var etchSecondary: EtchSecondaryButtonStyle { EtchSecondaryButtonStyle() }
}

/// A ringed circular icon button — the arrow that sits beside the primary pill on the sheet.
///
/// Ring rather than fill on purpose: two solid blue shapes side by side would spend the accent
/// twice on one row, and the brand allows it about five percent of a screen.
struct EtchCircleButton: View {
    let systemName: String
    var diameter: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.36, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().strokeBorder(Theme.accent, lineWidth: 1)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Segmented control

/// The filter row from the sheet: a sunken track, and the selected segment as a solid Etch Ink
/// pill with the label reversed out of it.
///
/// Written rather than styling `Picker(.segmented)`, which paints from the system's own palette
/// and cannot be given an Ink thumb — the one visual detail that makes this control Etch's
/// rather than iOS's.
struct EtchSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(Theme.spring) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.etch(.subheadline, weight: isSelected ? .etchMedium : .etchRoman))
                        .foregroundStyle(isSelected ? Theme.Ink.onInverse : Theme.Ink.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Theme.Surface.inverse)
                                    .matchedGeometryEffect(id: "segment", in: thumb)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Surface.sunken, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Cards

/// The card treatment used throughout the sheet: a Gallery White ground, a Mist hairline, and a
/// radius small enough to read as a sheet of paper rather than a bubble.
struct EtchCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Surface.raised, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.Line.hairline, lineWidth: 1)
            }
    }
}

/// The activity card from the sheet: a map thumbnail bled to the card's own edge, the activity's
/// name, and two lines of metadata separated by middots.
///
/// The thumbnail sits flush rather than inset — that is the detail that makes the card read as a
/// print rather than as a list row with a picture in it.
struct EtchActivityCard<Thumbnail: View>: View {
    let title: String
    let symbol: String
    /// The figures line: distance, pace, time.
    let metrics: [String]
    /// The context line: date, place.
    let context: [String]
    var showsChevron: Bool = true
    @ViewBuilder var thumbnail: Thumbnail

    var body: some View {
        HStack(spacing: 0) {
            thumbnail
                .frame(width: 104)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Ink.primary)
                    Text(title)
                        .font(.etch(.headline, weight: .etchMedium))
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)
                }
                EtchDotLine(parts: metrics, tabular: true)
                EtchDotLine(parts: context)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.trailing, 14)
                .opacity(showsChevron ? 1 : 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.Surface.raised, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Line.hairline, lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
    }
}

/// Values joined by a middot, the way every metadata line on the sheet is set.
struct EtchDotLine: View {
    let parts: [String]
    var tabular: Bool = false

    var body: some View {
        Text(parts.filter { !$0.isEmpty }.joined(separator: "  ·  "))
            .font(.etch(.subheadline))
            .monospacedDigit(tabular)
            .foregroundStyle(Theme.Ink.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private extension View {
    /// `monospacedDigit()` only when asked — a context line of words gains nothing from tabular
    /// figures and loses a little rhythm to them.
    @ViewBuilder func monospacedDigit(_ enabled: Bool) -> some View {
        if enabled { self.monospacedDigit() } else { self }
    }
}

// MARK: - Statistics

/// One figure and its label, as the sheet sets them: a small tracked uppercase label above a
/// large tabular number.
struct EtchStat: View {
    let label: String
    let value: String
    var size: CGFloat = 30

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .etchLabelStyle(10)
                .foregroundStyle(Theme.Ink.secondary)
            Text(value)
                .font(.etchMetric(size, weight: .etchRoman))
                .foregroundStyle(Theme.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

/// Several figures in one bordered strip, divided by hairlines rather than by gaps.
///
/// One container with rules inside it, not three cards in a row: the sheet's totals read as a
/// single statement about the whole library, and three separate cards would read as three
/// unrelated facts.
struct EtchStatStrip: View {
    let stats: [(label: String, value: String)]
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Line.hairline)
                        .frame(width: 1)
                        .padding(.vertical, 12)
                }
                EtchStat(label: stat.label, value: stat.value, size: size)
            }
        }
        .padding(.vertical, 16)
        .background(Theme.Surface.raised, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Line.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Metadata

/// The rule-divided metadata row the sheet runs under its type specimens — a tracked uppercase
/// label over a tabular value, with a hairline standing between each pair.
///
/// The same pattern the posters use in print, which is the point: a piece looks like the app it
/// came out of because the app sets its figures the way the print does.
struct EtchMetaColumns: View {
    let columns: [(label: String, value: String)]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Line.hairline)
                        .frame(width: 1, height: 34)
                        .padding(.horizontal, 18)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(column.label)
                        .etchLabelStyle(10)
                        .foregroundStyle(Theme.Ink.tertiary)
                    Text(column.value)
                        .font(.etchMetric(15, weight: .etchMedium))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Ink.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - The mark

/// The Etch wordmark, at a stated height.
///
/// A view rather than an `Image` at each call site, for one reason worth writing down: the asset
/// is trimmed to its own bounding box, so its frame *is* the letterforms. It did not used to be —
/// two thirds of it was transparent margin — and every place that sized it had learned to
/// compensate by roughly tripling the number. Those compensations are now wrong, and the way to
/// stop them coming back is for nobody to size the raw image again.
///
/// The asset carries an ink cut and a paper cut, so it inverts with the appearance on its own.
struct EtchWordmark: View {
    var height: CGFloat = 18

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Etch")
    }
}

// MARK: - The active filter

/// Says what the filter is currently hiding, and turns it off.
///
/// The whole reason a shared filter can be trusted. `RunFilter` lives on `AppModel` for the life
/// of the session, so a narrowing set on one surface is still narrowing on the next one — which
/// is the behaviour that was asked for, and also the single fastest way to convince someone the
/// app has lost their data. A filter you cannot see is indistinguishable from a bug.
///
/// So: same chip, same place, on every surface the filter reaches, and one tap clears it. It
/// draws nothing at all when nothing is filtered, so a clean view stays clean.
///
/// It deliberately does *not* show the activity scope. Scope already has a visible control
/// wherever it applies — the type selector in the map's pill, the scope picker on the Timeline —
/// and a chip repeating a control the user can already see reads as clutter rather than as
/// information.
///
/// Two surfaces carry no chip because the filter does not reach them. Studio is exempt on
/// purpose (see `StudioHomeView.scopedRuns`), and the Bag holds orders rather than activities —
/// a different noun, with none of these fields, and too few rows for filtering to be anything
/// but ceremony.
struct EtchFilterChip: View {
    let filter: RunFilter
    let clear: () -> Void

    var body: some View {
        if filter.isActive {
            HStack(spacing: 8) {
                Button(action: clear) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11, weight: .semibold))
                        Text(summary)
                            .font(.etch(.footnote, weight: .etchMedium))
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.12), in: .capsule)
                    .foregroundStyle(Theme.accentText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filtered: \(summary). Tap to clear.")
                Spacer(minLength: 0)
            }
        }
    }

    /// What is actually narrowing the view, named rather than counted.
    ///
    /// "3 filters" tells you a number and leaves you to go and find out which; the parts
    /// themselves fit, and are what someone needs in order to decide whether to clear them.
    private var summary: String {
        var parts: [String] = []
        if filter.mode != .all { parts.append(filter.mode.rawValue) }
        if filter.dateRange != .all { parts.append(filter.dateRangeLabel) }
        if let city = filter.city { parts.append(city) }
        else if let state = filter.state { parts.append(state) }
        else if let country = filter.country { parts.append(country) }
        if filter.surface != .any { parts.append(filter.surface.rawValue) }
        if filter.minDistance != nil || filter.maxDistance != nil { parts.append("Distance") }
        if filter.minDuration != nil || filter.maxDuration != nil { parts.append("Time") }
        return parts.isEmpty ? "Filtered" : parts.joined(separator: " · ")
    }
}

// MARK: - Header geometry

/// The numbers that keep the top of every tab in the same place.
///
/// Switching tabs used to move the mark and the avatar a few points in both axes, because the
/// map's header is a floating glass pill laid out by one set of paddings and every other tab's
/// header is flat content laid out by another. A few points is enough: the eye tracks a fixed
/// element across a transition, and one that shifts reads as the whole screen jumping.
///
/// So both are built from these, and the arithmetic is written down rather than tuned by eye:
///
///   · The mark's leading edge sits `side` from the screen edge on every tab. On the map that is
///     the pill's outer padding plus its own interior padding; on the others it is a single
///     padding. The two are set so they add to the same number.
///   · The avatar's trailing edge does the same, mirrored.
///   · The identity row's top sits `top` below the safe area, and the row is `rowHeight` tall,
///     so the two never disagree about the vertical centre.
///
/// Change one of these and both surfaces move together. That is the whole point of them being
/// here rather than inline.
enum EtchHeaderMetrics {
    /// Screen edge → the mark, and the avatar → screen edge.
    static let side: CGFloat = 20
    /// Safe area → the top of the identity row.
    static let top: CGFloat = 17
    /// The identity row's height. The avatar is the tallest thing in it, so they are the same
    /// number by definition rather than by coincidence.
    static let rowHeight: CGFloat = 34
    /// The avatar's diameter.
    static let avatar: CGFloat = 34
    /// The wordmark's height inside the identity row.
    ///
    /// Read against `rowHeight`, not in isolation: at 25 in a 34pt row the mark carries about
    /// four and a half points of air above and below, which is what lets it sit as the row's
    /// anchor rather than as one more small thing on a line of small things. Every surface takes
    /// its mark from here — the map pill and the flat page headers both — so the brand is one
    /// size across the app by construction rather than by four constants agreeing.
    static let mark: CGFloat = 25

    /// The map pill's own interior horizontal padding. Its outer padding is `side` minus this,
    /// which is what lands the mark at `side` from the screen edge on the map too.
    static let pillInterior: CGFloat = 11
    static var pillOuter: CGFloat { side - pillInterior }
}

// MARK: - The header row

/// Three slots on one line: something leading, something centred on the row's own midline, and
/// something trailing.
///
/// The centring is the reason this exists, and it took two wrong answers to get here.
///
/// A `Spacer` on each side does not centre anything — a spacer divides the space that is *left
/// over*, so the middle lands midway between the two outer slots. That is the row's centre only
/// when those slots are the same width, and they never are: a wordmark is wider than an avatar,
/// and the whole difference arrives as an offset on the one thing meant to be centred.
///
/// Measuring both slots and padding the narrower one does centre it, but only on the *second*
/// layout pass — the widths arrive through preferences, land in `@State`, and the row re-lays
/// out. Measured off two renders of the same screen, the title sat 20pt apart in light and dark
/// purely by which capture happened to catch the settled pass. A layout that is right only after
/// it has been wrong once is not right.
///
/// Giving both outer slots `maxWidth: .infinity` is the answer. SwiftUI divides the space left
/// after the centre among flexible siblings *equally*, so the two sides are the same width by
/// construction — no measurement, no state, no second pass, correct in the first frame. The
/// centre takes layout priority so it is sized to its content before the sides claim the rest.
///
/// It is a shared view rather than a technique applied twice because the app needs it in two
/// places that must agree exactly — the map's pill and every other tab's header. Two copies of a
/// layout trick is how those two drifted apart the first time.
struct EtchCenteredRow<Leading: View, Center: View, Trailing: View>: View {
    /// Gap between a slot and the space beside it. Declared before the slots so the synthesised
    /// initialiser puts the closures last and trailing-closure syntax works at the call site.
    var spacing: CGFloat = 9

    @ViewBuilder var leading: Leading
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: spacing) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            center
                .layoutPriority(1)
            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
