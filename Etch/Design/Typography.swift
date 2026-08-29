import SwiftUI
import UIKit

/// Etch's type system.
///
/// The brand specifies Neue Haas Grotesk for everything structural and Tiempos Text for
/// editorial moments. Both are commercially licensed and neither ships with iOS, so this file
/// is written to *resolve* a face rather than to name one: it asks the system for the branded
/// family first and falls back to the closest native equivalent when the font files are not
/// installed.
///
/// That means shipping the licensed faces later is a two-step change with no code in it —
/// drop the `.otf` files into the target and list them under `UIAppFonts` in Info.plist, and
/// every token below switches over on the next launch. `EtchType.isBranded` reports which of
/// the two states the running app is in.
///
/// The fallbacks are deliberate rather than incidental:
///   · SF Pro (`.default`) stands in for Neue Haas Grotesk. Both are neutral grotesques; SF is
///     the face the brand system itself nominates for iOS.
///   · New York (`.serif`) stands in for Tiempos Text. Both are Times-lineage text serifs.
///   · `.rounded` appears nowhere. A geometric rounded face is the one thing the brand rules
///     out, and it used to be the app's default.
enum EtchType {

    // MARK: - Face resolution

    /// Candidate PostScript names for the branded sans, in preference order. Monotype ships
    /// Neue Haas Grotesk under several naming conventions depending on the licence bundle, so
    /// all of the plausible ones are tried before falling back.
    private static let sansFamilies = [
        "NeueHaasGrotesk-Text", "NeueHaasGroteskText", "NHaasGroteskTXPro", "Neue Haas Grotesk Text",
    ]

    /// Candidate PostScript names for the branded serif.
    private static let serifFamilies = [
        "TiemposText-Regular", "TiemposText", "Tiempos Text",
    ]

    /// Whether the licensed brand faces are actually installed in this build.
    /// False on every build shipped so far — see the file comment.
    static var isBranded: Bool { resolvedSans != nil }

    private static let resolvedSans: String? = firstAvailable(sansFamilies)
    private static let resolvedSerif: String? = firstAvailable(serifFamilies)

    private static func firstAvailable(_ names: [String]) -> String? {
        names.first { UIFont(name: $0, size: 12) != nil }
    }

    /// Neue Haas Grotesk where licensed, SF Pro otherwise.
    static func sans(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if let family = resolvedSans {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// Tiempos Text where licensed, New York otherwise.
    static func serif(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if let family = resolvedSerif {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Weights

extension Font.Weight {
    /// Neue Haas Grotesk 45 Light. Reserved for large display type, where light weight reads
    /// as confidence rather than as thinness.
    static let etchLight = Font.Weight.light
    /// 55 Roman — body, and the default for everything unremarkable.
    static let etchRoman = Font.Weight.regular
    /// 65 Medium — headings, buttons, active labels. Etch's emphasis weight.
    static let etchMedium = Font.Weight.medium
    /// 75 Bold — used rarely, for a value that has to win a whole screen.
    static let etchBold = Font.Weight.semibold
}

// MARK: - Roles

extension Font {

    /// Display — the largest type on a screen. One per screen at most.
    static func etchDisplay(_ size: CGFloat = 34) -> Font { EtchType.sans(size, .etchMedium) }

    /// Editorial headline — the Tiempos moment. Titles of pieces, empty-state statements, the
    /// occasional line that is meant to be read rather than scanned. Used sparingly by design.
    static func etchEditorial(_ size: CGFloat = 24) -> Font { EtchType.serif(size, .etchRoman) }

    /// Screen and section titles.
    static func etchTitle(_ size: CGFloat = 22) -> Font { EtchType.sans(size, .etchMedium) }

    /// Row headings, card titles, the label on a control.
    static func etchHeadline(_ size: CGFloat = 17) -> Font { EtchType.sans(size, .etchMedium) }

    /// Running copy.
    static func etchBody(_ size: CGFloat = 17) -> Font { EtchType.sans(size, .etchRoman) }

    /// Supporting copy, secondary rows.
    static func etchCallout(_ size: CGFloat = 15) -> Font { EtchType.sans(size, .etchRoman) }

    /// Metadata, timestamps, footnotes.
    static func etchCaption(_ size: CGFloat = 12) -> Font { EtchType.sans(size, .etchRoman) }

    /// A tracked, small, uppercase label — the brand's METADATA / LABEL style. Pair with
    /// `.etchLabelTracking` and `.textCase(.uppercase)`; this is the one place Etch sets
    /// uppercase deliberately, and everything else stays sentence case.
    static func etchLabel(_ size: CGFloat = 11) -> Font { EtchType.sans(size, .etchMedium) }

    /// Numerals that have to line up: distance, pace, time, elevation, dates, totals,
    /// coordinates, stats. Always tabular — a column of figures that shifts as it counts is
    /// the fastest way to make a considered layout look cheap.
    static func etchMetric(_ size: CGFloat = 17, weight: Font.Weight = .etchMedium) -> Font {
        EtchType.sans(size, weight).monospacedDigit()
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

    /// Applies tabular figures to any text that already has a font set. Cheaper than swapping
    /// the whole font when a view is already styled and only the digits need fixing.
    func etchTabularFigures() -> some View {
        self.monospacedDigit()
    }
}
