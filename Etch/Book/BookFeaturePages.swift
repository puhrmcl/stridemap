import SwiftUI

/// The picture-led pages: the opening, the feature, and the plate.
///
/// These are the pages the redesign exists for. The rule the old photo pages stated outright —
/// *"the two never share a page"*, routes on one side, pictures on the other — is inverted here.
/// The photograph is the page; the numbers sit beside it and the route shrinks to a locator mark.
///
/// Nothing here is framed and nothing is inset. Images run to the trim, which is the move the old
/// collage could not make and the reason it read as a contact sheet.
extension BookPageView {

    // MARK: The opening — the book's first interior image

    /// Full-bleed hero under a foot scrim, with the book's own claim set over it. This is the page
    /// that tells the reader what kind of object they are holding, and it does it with a
    /// photograph rather than a wall of totals.
    var openingPage: some View {
        ZStack(alignment: .bottomLeading) {
            bleedPhoto(photos.first?.image)
                .frame(width: BookCatalog.pageSize.width, height: BookCatalog.pageSize.height)
            footScrim(height: 430)
            VStack(alignment: .leading, spacing: 16) {
                // The kicker is bone here, not accent: brand blue on a dark scrim over an
                // unknown photograph is the one place in the book where contrast cannot be
                // guaranteed. The accent keeps its voice as the rule above it.
                Rectangle().fill(accent).frame(width: 46, height: 2)
                Text((plan.subject.kind == .year ? "The year in pictures" : "In pictures").uppercased())
                    .font(.etch(size: 10.5, weight: .semibold))
                    .tracking(4.5)
                    .foregroundStyle(ground.opacity(0.82))
                headline(plan.subject.title.uppercased(), size: 84, color: ground)
                    .tracking(7)
                deck(openingDeck, size: 17, color: ground.opacity(0.88))
                    .frame(maxWidth: 620, alignment: .leading)
            }
            .padding(.horizontal, margin)
            .padding(.bottom, margin)
        }
    }

    /// One honest sentence about the span: how much, over how many days, across how many places.
    private var openingDeck: String {
        let stats = RunStatistics(plan.runs)
        let distance = Format.distanceValue(stats.totalDistanceMeters)
            .formatted(.number.precision(.fractionLength(0)))
        let unit = UnitSystem.current.label
        let places = Set(plan.runs.compactMap { run -> String? in
            guard let city = run.city, !city.isEmpty else { return nil }
            return city
        }).count
        var sentence = "\(stats.totalRuns) activities, \(distance) \(unit)"
        if places >= 2 { sentence += ", \(places) towns and cities" }
        return sentence + "."
    }

    // MARK: The feature — the core page of the redesign

    /// A chapter with photographs. The hero bleeds to three edges across roughly three-fifths of
    /// the sheet; the remainder is a bone column carrying the month, an editorial caption, three
    /// facts and the locator.
    ///
    /// `mirrored` flips the image to the right-hand side. Consecutive chapters alternate, so a
    /// reader turning through eight months never sees the same composition twice running — the
    /// cheapest and oldest trick in magazine layout, and the one the uniform grid gave up.
    func featurePage(_ start: Date, mirrored: Bool) -> some View {
        let chapter = plan.chapterRuns(start)
        let lead = plan.story.marquee(in: chapter) ?? chapter.first
        let hero = photos.first

        return HStack(spacing: 0) {
            if !mirrored { featureImage(hero) }
            featureColumn(start, chapter: chapter, lead: lead, hero: hero)
            if mirrored { featureImage(hero) }
        }
    }

    private func featureImage(_ hero: BookPagePhoto?) -> some View {
        bleedPhoto(hero?.image)
            .frame(width: BookCatalog.pageSize.width * 0.615,
                   height: BookCatalog.pageSize.height)
    }

    private func featureColumn(_ start: Date, chapter: [Run],
                               lead: Run?, hero: BookPagePhoto?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kicker(chapterName(start))
                .padding(.bottom, 14)

            headline(lead?.name ?? chapterName(start), size: 34)
                .padding(.bottom, 14)

            if let lead {
                deck(BookCaption.feature(lead, within: chapter))
            }

            // The whole block sits under the kicker with the slack below it, the way a magazine
            // sidebar is set. Putting the flexible gap in the middle instead left a dead band
            // between the caption and the numbers that read as an unfinished column.
            factRail(chapterFacts(chapter))
                .padding(.top, 40)

            locator(lead)
                .padding(.top, 30)

            Spacer(minLength: 16)

            folio(pageNumber)
        }
        .padding(.horizontal, 50)
        .padding(.vertical, margin - 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ground)
    }

    /// The month's three numbers. Distance and count always; the third is whichever of climb or
    /// places the month actually earned, so the rail never sets a zero.
    private func chapterFacts(_ chapter: [Run]) -> [Fact] {
        let stats = RunStatistics(chapter)
        var facts: [Fact] = [
            Fact(value: "\(Format.distanceValue(stats.totalDistanceMeters).formatted(.number.precision(.fractionLength(0)))) \(UnitSystem.current.label.uppercased())",
                 label: "Covered"),
            Fact(value: "\(chapter.count)", label: chapter.count == 1 ? "Activity" : "Activities")
        ]
        let climb = stats.totalElevationMeters
        let places = Set(chapter.compactMap { run -> String? in
            guard let city = run.city, !city.isEmpty else { return nil }
            return city
        })
        if climb >= 150 {
            facts.append(Fact(value: Format.elevation(climb), label: "Climbed"))
        } else if places.count >= 2 {
            facts.append(Fact(value: "\(places.count)", label: "Places"))
        } else if stats.totalMovingTime > 0 {
            facts.append(Fact(value: Format.duration(stats.totalMovingTime), label: "In motion"))
        }
        return facts
    }

    // MARK: The plate — the page that breathes

    /// One photograph, edge to edge, one sentence. No data, no route, no rail. A book of dense
    /// pages needs somewhere for the eye to rest, and this is it.
    var platePage: some View {
        ZStack(alignment: .bottomLeading) {
            bleedPhoto(photos.first?.image)
                .frame(width: BookCatalog.pageSize.width, height: BookCatalog.pageSize.height)
            footScrim(height: 240, strength: 0.8)
            HStack(alignment: .bottom) {
                deck(photos.first?.caption ?? "", size: 15, color: ground.opacity(0.9))
                    .frame(maxWidth: 560, alignment: .leading)
                Spacer(minLength: 20)
                folio(pageNumber, onDark: true)
                    .frame(width: 190)
            }
            .padding(.horizontal, margin)
            .padding(.bottom, margin - 14)
        }
    }
}
