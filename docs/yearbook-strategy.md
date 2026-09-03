# The Etch Year Book — from archive to story

*Strategy of record, 2026-09-03 (b552). Companion to the implementation phases landing on
`claude/rebrand-etch`. The brief: evolve "a book of every line you ran" into "the story of your
year in motion" — moments → achievements → places → progress → activities.*

---

## 1 · Critique of the current implementation

The current book (`Etch/Book/`, ~1,250 lines) is honest, print-safe, and brand-true — and it is
an **archive, not a story**. Specifically:

- **One layout per month, regardless of what the month held.** `chapterPage` is a uniform 4-column
  grid of up to eight route cells. A marathon month and a three-recovery-run month get the same
  page. A 1.1-mile recovery run and a PR marathon get identical cells.
- **It quietly drops activities.** `Array(mapped.prefix(8))` — a 20-activity month shows eight
  routes and *discards twelve without a trace*, while the header counts all twenty. The book's own
  closing line ("every line above was run") is undermined by lines that never appear.
- **Photos barely exist.** One photo, on race pages only, chosen implicitly (first reference),
  requested at 1800px (thin for a 300-DPI half-page). No curation, no heroes, no year-in-photos.
- **Zero achievement awareness** — despite `RunStatistics` already computing distance PRs,
  longest/fastest/highest-climb, milestones, and most-visited places. The engine exists; the book
  never asks it anything.
- **Zero geography** — despite `USStateBoundaries`/`WorldCountryBoundaries` vector data and Etch's
  own print-licensed cartography sitting in the same codebase.
- **No customization at all** beyond the subject picker. No captions, no reflection, no cover or
  theme choice, no way to feature or hide anything.
- **The arc is truncated.** Cover → title → stats → months → races → one closing line. No year in
  review, no reflection, no index. The emotional shape is front-loaded and then flat.
- **`BookPageView` is a monolith** that will not scale past ~8 templates.

What's *good* — and it's substantial — is below.

## 2 · What to preserve

- **The pipeline.** `BookRenderer`'s stream-to-disk PDF (one page in memory at a time), the
  authoring-points → 300-DPI scale system, the page-count envelope guards, the stable
  `creationID` slugs, the proof gate, the full commerce wiring. All of it stays.
- **`BookSubject`.** Already sport-agnostic ("activities", not "runs") and already an axis
  abstraction (year / state / city / favorites / races). This is the right spine.
- **The brand voice.** Bone ground, ink serif mastheads, wide tracking, the route as vector art,
  generous margins, "EVERY LINE ABOVE WAS RUN, NOT DRAWN." Statistics as complications. All kept.
- **Honest fallbacks** (indoor-miles line, chapter month→year fallback for long collections).

## 3 · What to remove or change

- The uniform chapter grid → replaced by a profiled template family (see §6).
- Silent activity dropping → replaced by the Activity Index; a month page that shows a subset says
  so ("+ 12 more — in the index").
- The monolithic page file → split by page family.
- The flat arc → replaced by the architecture in §5.
- The implicit race photo → replaced by the Moments system (§7).

## 4 · Information hierarchy (the product's spine)

1. **Moments** — curated photos with context (what it meant)
2. **Achievements** — detected + user-confirmed marks (what stood out)
3. **Places** — where the year happened (the map, firsts, range)
4. **Progress** — the aggregate story (miles, months, streaks, PRs over time)
5. **Activities** — the complete record (indexed, never dropped, never dominant)

Every page exists to serve one of these, in roughly this order of editorial weight.

## 5 · Book architecture (the new arc)

```
COVER            chosen from 3 Etch covers (route / typographic year / map)
TITLE            year · date range · optional dedication
THE YEAR         hero statistics (kept, refined)
THE MARKS        achievements spread (detected, 4–6 cards)
THE MAP          year on the map (states tinted, cities dotted, races starred, callouts)
MONTH CHAPTERS   profiled per month (feature / photo / standard / quiet), races as set pieces
YEAR IN PHOTOS   editorial mosaic of 6–12 curated photos
YOUR YEAR, ETCHED   review: hero mileage, numbers, highlights, places, PRs
REFLECTION       one prompt: "What will you remember about this year?"
ACTIVITY INDEX   every activity, compact, by month
CLOSING          "EVERY LINE ABOVE WAS RUN, NOT DRAWN." — always the last words
BACK COVER
```

Book length is dynamic inside Prodigi's 18–122 envelope. Degradation order when a huge history
presses the ceiling: month pages merge before the index shrinks before races are capped.

## 6 · Page/template system

Chapter profile is decided by content (the **Composer** rules, §11):

- **FEATURE** — the month's event leads (race spread follows), supporting activities beneath.
- **PHOTO** — hero image, monthly stats, 2–4 routes, caption.
- **STANDARD** — stats + up to ~7 routes with the month's marquee activity at double cell size.
- **QUIET** (≤4 activities) — single elegant column; one route drawn large; a line-listing.

Race pages grow toward true spreads: photo-led, map+route, placement/bib (fields exist), optional
memory caption. Achievement cards, review, reflection, index, and map pages are new families.
Every template lives in its own file; `BookPageView` becomes a dispatcher.

## 7 · Photos / Moments architecture

A per-subject **`BookCuration`** SwiftData model (keyed by subject slug):
`selectedPhotoIDs`, per-photo role overrides (hero / month / race / mosaic), `captions`
(page-keyed), `reflection`, `dedication`, `coverStyle`, `theme`, `featuredRunIDs`,
`hiddenRunIDs`, per-chapter `layoutOverride`.

Auto-association is nearly free: `photoReferences` already binds photos to activities → activity →
date → month → race. The curation step invites 10–25 picks (the Photo Wall picker pattern),
association is automatic, overrides are one tap. Principle: **activity data says what happened;
photos say what it meant; Etch combines them.**

Print sizing: heroes request full-resolution assets (`PhotoLibrary.fullImage`), month/mosaic
images ≥2400px on the long edge. Never upscale past the asset.

## 8 · Achievement detection architecture

A pure **StoryEngine** (`BookStory.swift`) over `(subjectRuns, fullHistory)` — testable, no UI:

- From existing primitives: distance PRs (benchmark bands, run-type-guarded), longest, biggest
  climb, fastest pace, most-visited place.
- New detections: highest-mileage month; longest daily streak; cumulative-mile milestones crossed
  this year (100/250/500/1,000/2,000…); **new cities/states** (first visit relative to the full
  history — this is why the engine sees both sets); race count and marathon completion; races as
  PRs (best time in class among races).
- User layer: favorite activity and confirmed highlights from `BookCuration` outrank detections.
- All phrased by the engine (title/value/detail/date), so pages render marks without re-deriving.

Honesty rule: whole-activity bests at ~benchmark distances (we store no per-point timing);
labeled "5K best", never "fastest 5K split".

## 9 · Geographic architecture

"THE MAP" uses assets already in the repo — no new licensing, all self-rendered vectors:

- `USStateBoundaries` / `WorldCountryBoundaries` polygons: visited states tinted by mileage
  (three-step bone→blue ramp), unvisited hairline.
- City dots sized by activity count; race locations starred in accent.
- Callouts: most-run city, farthest from home (home = modal start cell, the geohash logic that
  exists), new states/cities this year, geographic range (N–S span from
  northernmost/southernmost).
- Collections reuse the family: a state book shows the state with city dots; a city book shows a
  route-density figure. International histories fall back to country polygons.

## 10 · Controlled customization UX

**Users curate. Etch designs.** The flow (§15 of the brief) becomes:

1. Pick year → Etch analyzes (progress moment: "Reading your year…")
2. Photo curation sheet (skippable) → auto-association shown, tap to reassign
3. Highlights confirmation (detected marks pre-checked; user unchecks/adds favorite)
4. Reflection + dedication prompts (optional, one line each)
5. Full preview pager → per-page context menu where the template supports it:
   *Change Photo · Feature Activity · Hide Activity · Add Caption · Swap Layout* (rotates
   2–4 approved layouts for that content)
6. Proof gate → order (existing)

Themes: **Etch Light** (current), **Etch Ink** (ink ground / bone type), **Warm** (harbor
palette). Covers: **Route** (current), **Year** (typographic), **Map** (the year's geography).
Nothing else: no fonts, no colors, no sizes, no dragging, no freeform anything.

## 11 · Smart layout rules (the Composer)

Pure function: `(chapter runs, photos, achievements, curation) → template + emphasis`.

- race or top-3 achievement in month → FEATURE (+ race spread)
- ≥1 curated photo → PHOTO (unless FEATURE already claims it)
- ≤4 activities → QUIET
- else STANDARD, marquee = featured run (user pick > race > milestone > longest)
- months with high volume + race + photos may take two pages; the plan owns pagination
- global: hard page ceiling triggers the degradation order (§5); minimum keeps blank padding

## 12 · Data-model changes

- **`BookCuration`** (new SwiftData model) — §7 fields. Keyed by subject slug so reorders
  reproduce. Books remain derivable with an empty curation (the magic default).
- `Run` needs nothing new for phases 1–4 (bib, finishPlace, notes, weather, photos all exist).
  Age-group placement would be a new field if ever wanted — not required.
- `BookPlan` becomes template-addressed: pages carry `(template, content reference)`, and the
  plan carries the computed `BookStory` so pages never re-derive.

## 13 · PDF/print implications

Pipeline unchanged (stream-per-page). Changes: hero photos at full asset resolution with aspect
crops decided before render; JPEG quality 0.92 for photo-bearing pages; index typography ≥9.5pt
at print; map linework ≥0.75pt; dynamic pagination bounded by the envelope with the §5
degradation order; blanks remain the even-count fix; fonts are system-rendered into raster pages
(no embedding risk). Full-page bleed art keeps the existing no-bleed contract (Prodigi layflat
takes trimmed pages); interior heroes run to the page edge minus nothing — the lab's spec allows
edge-to-edge on this product because pages are supplied at final trim.

## 14 · Implementation risks

- **Photo permissions/coverage** — many activities carry no photos; every photo surface must
  compose beautifully empty (the QUIET/STANDARD paths are photo-free by design).
- **Render time** — more templates and photos lengthen export; the per-page stream keeps memory
  flat, and preview renders the visible page first.
- **Envelope pressure** — big years (500+ activities) push the index; degradation order + the
  existing trim guard protect the file.
- **Detection embarrassment** — a "fastest 5K" from GPS noise; mitigated by the plausibility
  guards that already exist and by the highlights-confirmation step (users veto before print).
- **Scope creep toward Canva** — resisted structurally: customization is enum-shaped, never
  free-form.

## 15 · Phases

1. **Story foundation** *(this change)* — StoryEngine; plan carries the story; THE MARKS page;
   YOUR YEAR, ETCHED review; ACTIVITY INDEX (nothing dropped, ever); QUIET months; STANDARD
   months gain a marquee cell + "+N more in the index" honesty line; closing moves to last.
2. **The Map** — state/country tinting, city dots, race stars, callouts.
3. **Moments** — BookCuration model, photo picker step, PHOTO months, race photos chosen not
   implied, YEAR IN PHOTOS mosaic, captions, reflection + dedication pages.
4. **Race spreads** — two-page set pieces, bib/placement, memory captions.
5. **Controlled customization** — themes, covers, per-page controls, swap-layout, highlight
   confirmation UX.
6. **Beyond running** — verb/noun audit (the subject already speaks "activities"); sport-aware
   phrasing ("climbed" vs "descended", "races" vs "events") via `ActivityType`, no architecture
   change required — that's the point of the story vocabulary.

## 16 · Ideas beyond the brief

- **The spine.** Layflat spines are visible on a shelf; year + name + miles on the spine is the
  decades-later object. (Needs Prodigi spine-art support check for this SKU.)
- **Weather as memory.** We store per-activity weather; "the coldest morning: 9°F, January 21"
  is a better memory than a pace. Cheap, evocative, already in the model.
- **The streak calendar.** A year-at-a-glance dot calendar (one dot per active day) as a single
  quiet page — progress made visible without a single route.
- **Dedication + gift path.** One line inside the cover turns the book into a gift object; pairs
  with the gift-card flow already shipped.
- **Next year's first page.** The last interior page could leave one printed line: "Volume II
  begins January 1." Retention, in print.
