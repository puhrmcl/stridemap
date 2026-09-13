# The Etch Book — editorial redesign

*Design of record, 2026-09-13. Supersedes the photo handling in `yearbook-strategy.md` §Phase 1.
The brief: pictures lead, routes and maps become secondary, and facts, highlights, insight and a
timeline run throughout rather than being quarantined on statistics pages.*

---

## 1 · What is wrong with the current book

The book is typographically disciplined and print-safe. It is also, as a *picture* book, wrong in
five specific ways — each of which is a decision in the code, not an accident.

**Photographs are filed, not published.** `photoCollage` lays every picture into equal-height rows
inside a hairline frame with a tracked uppercase micro-caption beneath. That is a contact sheet.
It is how a picture editor *reviews* images, not how a magazine *publishes* one.

**Nothing bleeds.** Every photograph sits inside the 76pt design margin and a 1pt border. The
single most reliable move in coffee-table and travel-book design — letting an image run off the
trim — is not available anywhere in the book. Framed-and-inset is the visual language of a
catalogue.

**There is no scale hierarchy.** Within a page every photograph is the same size. Editorial design
runs on dominance: one image commands, the rest support at a fraction of the area. Equal sizing
reads as "we could not decide which of these mattered", which is the opposite of curation.

**Photographs are quarantined from the data.** `BookPhotoPages` states the rule outright — *"the
two never share a page"*. A month with pictures becomes two pages: routes and numbers on one,
pictures on the other. So the photograph never gets to be *about* anything, and the numbers never
get a face. This is the single most consequential thing to invert.

**Captions carry no information.** `"MESA MARATHON · FEB 14"`, uppercase, tracked 1.4, 10.5pt. A
caption in this tradition earns its place by telling you something the picture cannot: how far,
how hard, how it ranked, what was new. Set in caps at 10.5pt it is a label on a specimen jar.

And one absence: **the book has no page numbers.** There is no folio anywhere in 4,100 lines.

## 2 · Principles

1. **One photograph commands each spread.** Everything else on the page is at most a third of its
   area. If two images want to be the hero, one of them belongs on another page.
2. **Photographs bleed; type does not.** Images run to the trim. The margin exists to protect
   type, and only type.
3. **The route is a locator, not a subject.** Drawn as a hairline at ~120pt, ink at 40%, captioned
   with a place. It answers *where*, quietly, the way a locator map does in the corner of a
   National Geographic feature. It stops performing.
4. **Every picture page carries facts.** Three to five, in a rail beside the image. Facts appear
   where the reader already is, not on a separate ledger they have to reach.
5. **Captions are sentences.** Sentence case, serif, and each one carries a number or a rank the
   photograph cannot show by itself.
6. **The span has a spine.** A timeline page renders the whole book chronologically — every
   activity as a stroke, the marks called out, photographs pinned to their dates.

## 3 · The page archetypes

| Page | Ground | Treatment |
| --- | --- | --- |
| `opening` | photo | Full-bleed hero. Scrim from the foot. Kicker, serif title, one-sentence deck. The book's first interior image, immediately after the title. |
| `feature(start:)` | split | **The core page.** Hero photograph bleeding to three edges across ~62% of the sheet; a bone type column holds kicker, serif headline, editorial caption, a three-fact rail, and the locator route. Mirrors left/right on alternating chapters so consecutive months never compose identically. |
| `plate(index:)` | photo | One photograph, full-bleed, one caption in a foot scrim. Carries no data. This is the page that lets the dense ones breathe. |
| `timeline` | bone | The span's spine: a horizontal axis, every activity a vertical stroke scaled by distance, races in accent, the marks called out with leader lines, photographs pinned at their dates. |
| `chapter(start:)` | bone | **Retained unchanged** for chapters with no photographs. A month without pictures is honestly a month of routes, and forcing a picture layout onto it would print empty frames. |

`feature` replaces the `chapter` + `chapterPhotos` *pair* whenever a chapter carries photographs,
so a picture month now costs one page rather than two while giving its photograph four times the
area.

## 4 · Typography

The book currently sets nearly everything in tracked uppercase sans. That is poster language — it
is right for a masthead and wrong for anything a reader has to *read*. The editorial layer adds:

- **Deck / caption** — serif, 15–17pt, sentence case, line spacing 5. Prose, set as prose.
- **Fact value** — serif 30pt; **fact label** — sans 9pt, tracking 2.5, ink 55%.
- **Kicker** — sans 10.5pt, tracking 4.5, accent. Retained from the existing vocabulary.
- **Folio** — sans 9pt at the foot: page number and subject. New.

Uppercase survives only for kickers, labels and mastheads.

## 5 · What is deliberately not changed

The pipeline is sound and stays untouched: `BookRenderer`'s stream-to-disk PDF with one page in
memory at a time, the authoring-points → 300-DPI scale system, the page-count envelope guards, the
hide-key contract, the proof gate, and the whole commerce path. The cover treatments, the marks,
numbers, review, atlas, cities, race-history and index pages keep their current design; this pass
is about how the book handles **pictures**, and widening it further would put a working product at
risk for no additional answer to the brief.

## 6 · Review

Book pages were previously invisible to CI — the preview harness could open the book *studio*, but
no workflow ever photographed a rendered page, so no book layout has ever been visually reviewed
in this project. The redesign adds `book-opening`, `book-feature`, `book-plate` and
`book-timeline` capture scenarios rendering real `BookPageView` output at print aspect, so every
future change to the book is reviewable from the build artifacts.
