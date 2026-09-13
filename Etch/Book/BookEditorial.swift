import SwiftUI

/// The editorial layer: the vocabulary the picture-led pages are built from.
///
/// The book's original voice is poster language — tracked uppercase sans, everything inset inside
/// the margin, the route as the subject. That is right for a masthead and wrong for a page anyone
/// has to *read*. This file adds the second voice a picture book needs: prose set as prose, facts
/// that sit beside the photograph instead of on a ledger page of their own, and a route reduced to
/// the quiet locator mark it should have been all along.
///
/// See `docs/book-editorial-redesign.md` for the reasoning. The rules these components encode:
/// photographs bleed and type does not; one image commands each page; the route answers *where*
/// and then stops talking.
extension BookPageView {

    // MARK: Type

    /// The small accent line above a headline — a month, a section, a standing.
    func kicker(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.etch(size: 10.5, weight: .semibold))
            .tracking(4.5)
            .foregroundStyle(accent)
    }

    /// The serif headline. Sentence-cased by the caller when it is a name, upper when a masthead.
    func headline(_ text: String, size: CGFloat = 40, color: Color? = nil) -> some View {
        Text(text)
            .font(.etchSerif(size: size, weight: .regular))
            .tracking(0.5)
            .foregroundStyle(color ?? ink)
            .lineLimit(3)
            .minimumScaleFactor(0.55)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Prose — the deck under a title, or the caption beside a photograph. Serif, sentence case,
    /// real leading. The one place in the book where text is allowed to simply be text.
    func deck(_ text: String, size: CGFloat = 15.5, color: Color? = nil) -> some View {
        Text(text)
            .font(.etchSerif(size: size, weight: .regular))
            .lineSpacing(5)
            .foregroundStyle(color ?? subtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Facts

    /// One fact: the number large in the serif, its label small and tracked beneath.
    struct Fact: Identifiable {
        let id = UUID()
        let value: String
        let label: String
    }

    /// The fact rail — three to five data points stacked beside a photograph, hairline-separated.
    /// This is what puts the numbers *where the reader already is* instead of on a ledger page
    /// they have to reach.
    func factRail(_ facts: [Fact], valueSize: CGFloat = 30) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                if index > 0 {
                    Rectangle().fill(ink.opacity(0.14))
                        .frame(height: 1)
                        .padding(.vertical, 11)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(fact.value)
                        .font(.etchSerif(size: valueSize, weight: .regular))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(fact.label.uppercased())
                        .font(.etch(size: 9, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(subtle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // MARK: The locator

    /// The route, demoted. A hairline at 40% ink with the place named beneath it — the corner
    /// locator of a magazine feature, not the subject of the page. Draws nothing at all when the
    /// activity has no line, rather than holding an empty box open.
    @ViewBuilder
    func locator(_ run: Run?, height: CGFloat = 104, tint: Color? = nil) -> some View {
        if let run, run.coordinates.count > 1 {
            VStack(alignment: .leading, spacing: 9) {
                RouteShape(coordinates: run.coordinates)
                    .stroke(tint ?? ink.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(height: height)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let place = placeLine(run) {
                    Text(place.uppercased())
                        .font(.etch(size: 9, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(subtle.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    /// "Mesa, Arizona" — whatever of the two the activity actually knows.
    func placeLine(_ run: Run) -> String? {
        let parts = [run.city, PlaceNames.canonicalState(run.state)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: Photographs

    /// A photograph that fills its slot and bleeds. No frame, no inset — the frame is the thing
    /// the redesign exists to remove. A reference the library can no longer resolve draws a quiet
    /// ink field instead, so the proof shows the gap exactly as it would print.
    @ViewBuilder
    func bleedPhoto(_ image: UIImage?) -> some View {
        ZStack {
            ink.opacity(0.06)
            if let image {
                Color.clear.overlay(
                    Image(uiImage: image).resizable().scaledToFill()
                )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(subtle.opacity(0.4))
            }
        }
        .clipped()
    }

    /// The gradient that lets bone type sit on an unknown photograph. Rises from the foot only —
    /// a scrim over the whole image would flatten it to a grey field.
    func footScrim(height: CGFloat = 300, strength: Double = 0.88) -> some View {
        LinearGradient(
            colors: [ink.opacity(0), ink.opacity(strength * 0.55), ink.opacity(strength)],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    // MARK: The folio

    /// Page number and subject at the foot. The book had no folios at all before this — a real
    /// book numbers its pages. Covers and full-bleed plates are left alone by the caller.
    @ViewBuilder
    func folio(_ number: Int?, onDark: Bool = false) -> some View {
        if let number, number > 1 {
            HStack {
                Text(plan.subject.title.uppercased())
                    .font(.etch(size: 9, weight: .semibold))
                    .tracking(2.5)
                    .foregroundStyle(onDark ? ground.opacity(0.55) : subtle.opacity(0.75))
                Spacer(minLength: 12)
                Text("\(number)")
                    .font(.etch(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(onDark ? ground.opacity(0.55) : subtle.opacity(0.75))
            }
        }
    }
}

/// Editorial phrasing. A caption in this tradition earns its place by carrying something the
/// photograph cannot show — how far, how long, how it ranked within its month.
///
/// Everything here is derived from the activity in hand plus the set it belongs to. Nothing is
/// invented, and a claim that cannot be supported is simply not made: the phrasing degrades to
/// fewer clauses rather than to a vaguer one.
enum BookCaption {

    /// The sentence under a feature photograph. Names the activity and its date, then the one
    /// thing about it worth knowing in context.
    static func feature(_ run: Run, within chapter: [Run]) -> String {
        var sentence = "\(run.name), \(longDate(run.startDate))"
        if let standing = standing(run, within: chapter) {
            sentence += " — \(standing)"
        }
        if let detail = detail(run) {
            sentence += sentence.hasSuffix(".") ? " \(detail)" : ", and \(lowerFirst(detail))"
        }
        return sentence.hasSuffix(".") ? sentence : sentence + "."
    }

    /// The caption on a standalone plate: quieter, because the picture is doing the work.
    static func plate(_ run: Run?) -> String {
        guard let run else { return "From the library." }
        var sentence = run.name
        if let place = [run.city, PlaceNames.canonicalState(run.state)]
            .compactMap({ $0 }).filter({ !$0.isEmpty }).first {
            sentence += ", \(place)"
        }
        return sentence + ". " + longDate(run.startDate) + "."
    }

    /// How this activity ranked inside its own chapter — the context a reader cannot see.
    private static func standing(_ run: Run, within chapter: [Run]) -> String? {
        if run.isRace { return "a start line" }
        guard chapter.count > 1 else { return nil }
        let longest = chapter.max(by: { $0.distance < $1.distance })
        if longest?.id == run.id {
            return "the longest of the month's \(spelled(chapter.count))"
        }
        let climbed = chapter.max(by: { $0.elevationGain < $1.elevationGain })
        if climbed?.id == run.id, run.elevationGain >= 150 { return "the month's biggest climb" }
        return nil
    }

    /// The numeric clause: distance always, climb when it was worth the legs.
    private static func detail(_ run: Run) -> String? {
        guard let distance = StatMetric.distance.value(for: run) else { return nil }
        if run.elevationGain >= 150 {
            return "\(distance) with \(Format.elevation(run.elevationGain)) of climb"
        }
        return "\(distance)"
    }

    private static func spelled(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
                     "nine", "ten", "eleven", "twelve"]
        return count < words.count ? words[count] : count.formatted()
    }

    private static func lowerFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}
