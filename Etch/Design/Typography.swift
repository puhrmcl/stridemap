import SwiftUI
import UIKit

/// Etch's type system.
///
/// Three faces, bundled with the app:
///
///   · **Inter Tight** — display and titles. A tighter grotesk; the closing-up is what gives a
///     headline the density the brand's display type has.
///   · **Inter** — everything else. Body, labels, buttons, data, UI.
///   · **Newsreader** — the editorial serif, kept for the few moments that are meant to be read
///     rather than scanned.
///
/// These stand in for Neue Haas Grotesk and Tiempos Text, which are licensed faces the project
/// does not own. All three are SIL Open Font License, which permits embedding in an app and
/// serving on the web — see `Etch/Resources/Fonts/OFL.txt`.
///
/// **Weights are files, not traits.** Google ships each weight as its own font whose *family*
/// name is the weight ("Inter SemiBold"), so `Font.custom("Inter", …).weight(.semibold)` finds
/// nothing to switch to and CoreText draws a synthetic bold instead — a smeared outline that
/// looks exactly like the cheap thing it is. Every token below therefore resolves to a specific
/// PostScript name, and nothing in the app calls `.weight()` on a branded font.
enum EtchType {

    /// The three roles a face can play. Held as a type rather than a font so that things which
    /// choose a face dynamically — the poster's Title typeface picker, say — can pass one around.
    enum Face {
        case display   // Inter Tight
        case text      // Inter
        case editorial // Newsreader
    }

    // MARK: Resolution

    /// PostScript names, by face and weight. Taken from the shipped files' name tables rather
    /// than guessed: Newsreader's carries Google's optical-size instance naming, which no one
    /// would arrive at by reasoning about it.
    private static func postScriptName(_ face: Face, _ weight: Font.Weight) -> String {
        switch face {
        case .display:
            switch weight {
            case .semibold, .bold, .heavy, .black: return "InterTight-SemiBold"
            case .medium:                          return "InterTight-Medium"
            default:                               return "InterTight-Regular"
            }
        case .text:
            switch weight {
            case .semibold, .bold, .heavy, .black: return "Inter-SemiBold"
            case .medium:                          return "Inter-Medium"
            case .light, .thin, .ultraLight:       return "Inter-Light"
            default:                               return "Inter-Regular"
            }
        case .editorial:
            switch weight {
            case .semibold, .bold, .heavy, .black: return "Newsreader16pt16pt-SemiBold"
            case .medium:                          return "Newsreader16pt16pt-Medium"
            default:                               return "Newsreader16pt16pt-Regular"
            }
        }
    }

    /// Whether the bundled faces actually loaded.
    ///
    /// A font that fails to register is invisible: `Font.custom` silently falls back to the
    /// system, so the app looks *fine* and is simply not in its own typeface. This is the check
    /// that says which of the two happened — and `resolved` below is what makes the fallback a
    /// deliberate one rather than an accident nobody notices.
    static var isBranded: Bool {
        UIFont(name: "Inter-Regular", size: 12) != nil
    }

    /// Every face the app expects, and whether it actually registered.
    ///
    /// This exists because the failure mode is silent: a font that does not register makes
    /// `Font.custom` fall back to the system, so the app looks perfectly fine and is simply not
    /// in its own typeface. There is no Mac here to check on, and two neo-grotesques are not
    /// reliably tellable apart in a screenshot — so the app is asked rather than guessed at.
    /// Surfaced on the `components` preview screen.
    static var diagnostics: [(name: String, loaded: Bool)] {
        let faces: [(Face, Font.Weight)] = [
            (.display, .regular), (.display, .medium), (.display, .semibold),
            (.text, .light), (.text, .regular), (.text, .medium), (.text, .semibold),
            (.editorial, .regular), (.editorial, .medium), (.editorial, .semibold),
        ]
        return faces.map { face, weight in
            let name = postScriptName(face, weight)
            return (name, UIFont(name: name, size: 12) != nil)
        }
    }

    private static var missing: Set<String> = []

    /// The PostScript name if it loaded, nil if it did not — checked once per name.
    private static func resolved(_ face: Face, _ weight: Font.Weight) -> String? {
        let name = postScriptName(face, weight)
        if missing.contains(name) { return nil }
        if UIFont(name: name, size: 12) == nil {
            missing.insert(name)
            return nil
        }
        return name
    }

    /// The UIKit twin of `font(_:size:weight:)`, for code that must *measure* the branded face —
    /// the Filled masthead sizes its title from the glyphs' real widths.
    static func uiFont(_ face: Face, size: CGFloat, weight: Font.Weight = .regular) -> UIFont {
        if let name = resolved(face, weight), let font = UIFont(name: name, size: size) {
            return font
        }
        let uiWeight: UIFont.Weight = {
            switch weight {
            case .semibold, .bold, .heavy, .black: return .semibold
            case .medium:                          return .medium
            case .light, .thin, .ultraLight:       return .light
            default:                               return .regular
            }
        }()
        return .systemFont(ofSize: size, weight: uiWeight)
    }

    /// A branded font at a fixed size.
    static func font(_ face: Face, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard let name = resolved(face, weight) else {
            return .system(size: size, weight: weight,
                           design: face == .editorial ? .serif : .default)
        }
        return .custom(name, fixedSize: size)
    }

    /// A branded font that scales with Dynamic Type, anchored to a text style.
    ///
    /// `relativeTo:` is what keeps accessibility working: the size below is the style's size at
    /// the default content size, and the system scales from there. Dropping to a fixed size —
    /// which is what naming a custom font naively does — would freeze every label in the app at
    /// one size and quietly break the setting people rely on most.
    static func font(_ face: Face, _ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        guard let name = resolved(face, weight) else {
            return .system(style, design: face == .editorial ? .serif : .default).weight(weight)
        }
        return .custom(name, size: baseSize(style), relativeTo: style)
    }

    /// Each text style's point size at the default content size — the anchor Dynamic Type scales
    /// from. These are Apple's own values; matching them means switching a call site from
    /// `.system` to a branded face changes the face and nothing else.
    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle:  return 34
        case .title:       return 28
        case .title2:      return 22
        case .title3:      return 20
        case .headline:    return 17
        case .body:        return 17
        case .callout:     return 16
        case .subheadline: return 15
        case .footnote:    return 13
        case .caption:     return 12
        case .caption2:    return 11
        @unknown default:  return 17
        }
    }
}

// MARK: - Weights

extension Font.Weight {
    /// Inter Light, standing in for Neue Haas 45. Large display only — at text sizes a light
    /// grotesk stops being confident and starts being faint.
    static let etchLight = Font.Weight.light
    /// Regular — body, and the default for everything unremarkable.
    static let etchRoman = Font.Weight.regular
    /// Medium — headings, buttons, active labels. Etch's emphasis weight.
    static let etchMedium = Font.Weight.medium
    /// SemiBold — used rarely, for a value that has to win a whole screen.
    static let etchBold = Font.Weight.semibold
}

// MARK: - The call-site API

extension Font {

    /// A branded font at a fixed size. The direct replacement for `.system(size:weight:)`.
    static func etch(size: CGFloat, weight: Font.Weight = .regular,
                     face: EtchType.Face = .text) -> Font {
        EtchType.font(face, size: size, weight: weight)
    }

    /// A branded font on a Dynamic Type style. The direct replacement for `.system(_:)`.
    static func etch(_ style: Font.TextStyle, weight: Font.Weight = .regular,
                     face: EtchType.Face = .text) -> Font {
        EtchType.font(face, style, weight: weight)
    }

    /// The editorial serif at a fixed size.
    static func etchSerif(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        EtchType.font(.editorial, size: size, weight: weight)
    }

    /// The editorial serif on a Dynamic Type style.
    static func etchSerif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        EtchType.font(.editorial, style, weight: weight)
    }

    // MARK: Roles

    /// Display — the largest type on a screen. One per screen at most. Inter Tight.
    static func etchDisplay(_ size: CGFloat = 34) -> Font {
        EtchType.font(.display, size: size, weight: .etchMedium)
    }

    /// Screen and section titles. Inter Tight.
    static func etchTitle(_ size: CGFloat = 22) -> Font {
        EtchType.font(.display, size: size, weight: .etchMedium)
    }

    /// The editorial moment — titles of pieces, empty-state statements, the occasional line meant
    /// to be read rather than scanned. Used sparingly by design.
    static func etchEditorial(_ size: CGFloat = 24) -> Font {
        EtchType.font(.editorial, size: size, weight: .etchRoman)
    }

    /// Row headings, card titles, the label on a control.
    static func etchHeadline(_ size: CGFloat = 17) -> Font {
        EtchType.font(.text, size: size, weight: .etchMedium)
    }

    /// Running copy.
    static func etchBody(_ size: CGFloat = 17) -> Font {
        EtchType.font(.text, size: size, weight: .etchRoman)
    }

    /// Supporting copy, secondary rows.
    static func etchCallout(_ size: CGFloat = 15) -> Font {
        EtchType.font(.text, size: size, weight: .etchRoman)
    }

    /// Metadata, timestamps, footnotes.
    static func etchCaption(_ size: CGFloat = 12) -> Font {
        EtchType.font(.text, size: size, weight: .etchRoman)
    }

    /// A tracked, small, uppercase label — the brand's METADATA / LABEL style. Pair with
    /// `.etchLabelStyle()`; this is the one place Etch sets uppercase deliberately, and
    /// everything else stays sentence case.
    static func etchLabel(_ size: CGFloat = 11) -> Font {
        EtchType.font(.text, size: size, weight: .etchMedium)
    }

    /// Numerals that have to line up: distance, pace, time, elevation, dates, totals,
    /// coordinates, stats. Always tabular — a column of figures that shifts as it counts is the
    /// fastest way to make a considered layout look cheap. Inter's figures are tabular under
    /// `monospacedDigit()` without changing the face.
    static func etchMetric(_ size: CGFloat = 17, weight: Font.Weight = .etchMedium) -> Font {
        EtchType.font(.text, size: size, weight: weight).monospacedDigit()
    }
}

extension CGFloat {
    /// Tracking for the small uppercase label style.
    static let etchLabelTracking: CGFloat = 1.1
}

// MARK: - Convenience

extension View {

    /// The brand's tracked uppercase metadata label, in one modifier.
    func etchLabelStyle(_ size: CGFloat = 11) -> some View {
        self.font(.etchLabel(size))
            .tracking(.etchLabelTracking)
            .textCase(.uppercase)
    }

    /// Applies tabular figures to text that already has a font set.
    func etchTabularFigures() -> some View {
        self.monospacedDigit()
    }
}
