# Etch Studio — audit, cartography decision, and the road to "pick the one you love"

*Written 2026-09-01 against b518, from a full read of the Studio sources (41 files, ~15k lines).
The brief: make Studio feel like configuring a premium product, not using design software —
Choose → Personalize → Preview → Buy.*

## The one-paragraph verdict

Most of what the brief asks for is not missing — it is built, recently, and well: a custom
cartography system on OpenStreetMap that Etch owns end to end, a print pipeline that streams
true 300-DPI sheets on a phone, a curated preset/look/material system that replaced a
twelve-axis configurator, and a drawn framed-product mockup. What was missing was the **front
door** (Studio opened on a question instead of an answer — fixed in b518), the **merchandising
brain** (nothing read the activity — fixed in b518), and **one operational object**: the
basemap archive is not in the bucket, so today *zero map-panel posters are legally sellable*.
That last item is the single highest-leverage task in the company and it is not code.

---

## 1 · Audit

### Architecture, as found

```
PosterConfig (value-type recipe, ~30 fields)  ← the single source of truth
   ├── StudioEdition   13 authored palettes/surfaces (map / paper / photo / contour)
   ├── StudioPreset    7 finished combinations (template + map + look)
   ├── StudioLook / StudioPalette / StudioTypeSystem   coordinated one-tap systems
   ├── MapMaterial     5 materials × Look → resolves to an authored edition
   └── MapLayout       nameplate / statement / minimal / photo / fullBleed

StudioRenderer  → StudioComposition (SwiftUI, authored at 1000pt)  → preview images
             └→ banded print engine → PrintFileWriter (streaming PNG, 300 DPI, any size)

Map panel:  EtchMapSnapshotter (MapLibre + Etch style from EtchCartography)
            → falls back to Apple's MKMapSnapshotter for *display only*
            → the print path refuses the fallback outright (licensing)

Tiles:      Protomaps .pmtiles in R2, served by fulfilment/src/tiles.ts (range reads, ~free)
Commerce:   PrintShopView → Shopify cart / Apple Pay → fulfilment worker → Prodigi
```

Data, design, map rendering, print rendering, product configuration and commerce are already
separated along almost exactly the lines the brief's §16 asks for. The component names differ
(`StudioEdition` ≈ ColorTheme+MapStyle, `MapLayout` ≈ PosterTemplate, `StatMetric` slots ≈
MetadataBlock) but the factoring is right and should not be rebuilt.

### KEEP — do not touch

- **The print pipeline.** `PrintFileWriter` streams a 24×36 at 300 DPI in twelve 26 MB bands
  through a hand-built PNG encoder with Accelerate colour conversion. Type, route and hairlines
  render as vectors at full sheet resolution; only the map/photo panel is a raster (capped at
  5000px — 208+ DPI on the widest sheet, above the 200 floor the code refuses to ship under).
  CI proves it every run (`print-engine` self-check). This is *better* than most competitors,
  who upscale screenshots.
- **The cartography decision.** MapLibre Native (BSD, SPM) + Protomaps/OSM in R2. See §2 — the
  evaluation the brief asks for was done here and the conclusion stands.
- **The edition system.** Thirteen authored palettes where ground/ink/route/accent were chosen
  together, and the map style is *derived* from the edition so the palette can never fork.
- **The framed mockup.** Drawn, not photographed — moulding faces, rebate line, glazing
  reflection, two shadows — so it shows the buyer's own artwork in every finish at zero plates.
- **The commerce spine.** Frozen assets in R2, ledger in D1, webhooks → Prodigi. Untouched.

### IMPROVE

- **Customize still carries six per-element type scales** (title/location/date/hero/stat ×
  global). They are behind the Customize tab, which satisfies "advanced is secondary", but
  five of the six should eventually collapse into the TypeSystem balance (§5 of the brief:
  curated, not granular). Low priority; they no longer greet anyone.
- **Size range.** Three sizes (12×18 / 16×24 / 24×36). The brief wants 8×10–24×36. Prodigi's
  GLOBAL-HGE range carries the smaller sizes; adding them is a `verify-prodigi` run + catalogue
  rows + config prices, no rendering work (the engine is size-agnostic). Do after launch.
- **Race data on the sheet.** Bib/finish/place metrics exist; the curator now surfaces them
  for races. A dedicated "Course" treatment (start/finish markers exist per task #20; mile
  markers do not) is the strongest template gap. Phase 2.
- **The editor's preview could show FRAME context.** The mockup exists but lives in the shop.
  An ART / FRAME toggle above the editor preview is cheap and sells the object earlier. ROOM
  (lifestyle scale shot) is Phase 2 — needs one good photographed plate per orientation.

### REMOVE

- **The Map/Gallery product fork as the entry screen** — removed in b518. The two families
  survive as facts about a piece, not as a question for the customer.
- **`MapStyle.atlas` / `.atlasDark` from anything customer-facing** (already withdrawn from
  pickers; they exist only so old saved posters keep rendering). When the basemap goes live,
  Satellite is the one style that stays honestly display-only — OSM has no imagery. Either
  license imagery later or let Satellite quietly retire.

### REBUILD — done in b518

- **The front door.** `StudioCurator` reads the activity — race → Harbor marathon print with
  time/pace/place; summit (hike, or >450 m climb) → the contour journals with the climb;
  photos → a Memory piece; decisively east–west route → landscape — and lays out 4–5 finished
  pieces rendered with the customer's own route. Choose one → the editor opens seeded.
  Choose → Personalize → Preview → Buy, in that order, for the first time.

### Defects found by the audit (fixed in b518)

- **The remote config was dead.** `EtchRemoteConfig`'s synthesized decoder required every key;
  the served document predates `basemapReady`; decoding failed silently behind a `try?`; the
  app has been running on compiled defaults. Prices happened to match, so it was invisible —
  but the ordering kill switch and every future price edit did nothing. Decoding is now
  per-field with fallbacks, which is what the file's own doc comment always claimed.

---

## 2 · The mapping architecture (the brief's §2–3, answered)

**Recommendation: keep and finish the system that exists.** It is the right one.

| Option | Verdict |
|---|---|
| **MapLibre Native + Protomaps/OSM on R2** *(current)* | **Yes.** BSD renderer, total style control, one 127-byte-header file in a bucket Etch already pays for, served by a worker Etch already runs. Cost ≈ $1.80/mo for the planet. ODbL: print freely with "© OpenStreetMap contributors" on the sheet margin or back label. |
| Mapbox | Style control is equal, but print/merchandise use of Mapbox styles requires their print licensing terms, static-image rates bill per render, and the SDK is proprietary. Pays monthly for what Etch now owns. |
| MapTiler / other hosted OSM | Fine products; solves nothing Protomaps-on-R2 doesn't, adds a vendor and a bill. |
| Custom MVT → Core Graphics renderer | The purist answer (resolution-independent panels, no GPU snapshot ceiling). Not justified today: the raster panel already exceeds print floor at every offered size, and the eye-critical marks are already vector. Revisit only if a >36" product appears. |

**Why the current shape is print-first:** the panel is deliberately *not* the subject. Type,
route, markers and rules draw at the sheet's native 300 DPI; the muted map beneath them is a
5000px raster that no viewer reads at arm's length. Preview and print share one composition
authored at 1000pt, so they cannot disagree except in resolution.

**The Etch cartographic signature** already has a point of view worth protecting: six layers,
not thirty (land, water, buildings-at-close-zoom, two road weights, optional places); land is
set to the poster's own paper so the map has no edge; water takes 16% of the route's colour so
the coastline rhymes with the run; labels default *off* because the composition names the place
in type Etch controls. That *is* "recognizable as Etch without the logo". Phase-2 candidates:
a hairline graticule option, parks as a 6% tint, and a terrain/hillshade source for the Terrain
edition (Mapzen/AWS DEM tiles, public).

**What is actually missing: the archive.** `basemap.pmtiles` is not in the bucket, so
`basemapReady` is false, so every map-panel edition falls back to Apple on screen and refuses
to print. b518 ships `.github/workflows/build-basemap.yml`: it extracts a region from the
public Protomaps daily build **over HTTP ranges** (no 120 GB download), uploads to R2 with the
AWS CLI (multipart), and verifies the worker serves it. Needs two one-time dashboard secrets
(`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`). Start with the Arizona bbox in
`.github/basemap-request.txt`, place one end-to-end sandbox order, then widen region by region.
Flip `basemapReady: true` in `fulfilment/config/app.json` to go live — no app release, and the
same edit turns it back off if tiles misbehave.

### Migration path (§18): **A — Studio only.**

The home map stays MapKit: it is interactive, free, familiar, and nothing about it is sold.
Studio is where cartographic ownership converts directly to revenue, and it is already off
Apple for print by construction (the print path *cannot* use Apple). Adopt MapLibre app-wide
only if a concrete need appears (offline, or a brand-consistency push after launch); that
would be a quality/risk trade with no revenue on it today.

---

## 3 · The template system (§4, §9), mapped to what exists

The brief's eight names land on today's system almost one-to-one — the work is merchandising
and gaps, not greenfield:

| Brief | Etch today | Gap |
|---|---|---|
| Signature | Gallery edition + Nameplate | — (the default) |
| Editorial | Statement layout + Editorial type | naming only |
| Blueprint | Streets / Streets Noir | — |
| Terrain | Terrain edition; Trail Journal / Midnight Atlas contours | hillshade later |
| Course | Nameplate + race metrics + start/finish markers | mile markers, split band — **Phase 2, the strongest gap** |
| City | Streets at city framing; Lithograph (city index) | — |
| Legacy | Harbor (navy/gold) + Medal Frame | — |
| Tour | Lithograph tour-poster layout; Anthology; Collections book | — |

Emotional catalogue coverage (§9): marathon/PR → Harbor + Course; favourite route/hometown →
Gallery/Streets; every street in a city → Lithograph; year in running / 1000-mile year →
Anthology + Year in Review book; race collection → Collections book + Medal Frame; states and
parks → Collections + peak lists. The products people buy for identity already exist; the
curator's job (now shipped) is to put the right one first.

---

## 4 · Roadmap

**Phase 1 — shipped in b518.** Gallery front door + curator; remote-config repair; basemap
build workflow.

**Phase 2 — sell the map (operational, ~1 sitting of user time).**
1. Create the two R2 secrets → re-run Build basemap (Arizona default).
2. Order the cheapest map print end-to-end on sandbox; check the sheet's panel is Etch
   cartography (the export refuses Apple, so if it renders, it is ours).
3. `basemapReady: true`, config v4. Map editions go on sale. Widen the bbox regionally.

**Phase 3 — the funnel deepens (app work, in rough order of $/effort):**
- ART / FRAME toggle on the editor preview (mockup already drawn).
- Course treatment: mile/km markers + splits band for races.
- 8×10 / 11×14 / 18×24 via `verify-prodigi` + catalogue rows.
- ROOM view: one photographed wall plate per orientation, artwork composited at true scale.
- Collapse the six type scales into the TypeSystem balances.

**Phase 4 — later, evidence-driven:** hillshade/terrain source; graticule + parks layers;
imagery licensing decision for Satellite (or retire it); app-wide MapLibre only if a concrete
need appears.

### Risks

- **MLNMapSnapshotter ceiling**: the 5000px panel sits inside GPU texture limits on modern
  devices; if a larger panel is ever needed, render the map in tiles and stitch (the banded
  writer already composes per-band) or build the CG vector renderer.
- **Archive size vs runner disk** for a nationwide basemap: widen in steps; the workflow
  prints sizes. Fallback: Protomaps' hosted API (~$40/mo) with the same styles.
- **ODbL attribution on product**: "© OpenStreetMap contributors" must appear on the sheet
  (margin or back). `EtchCartography.attribution` exists; verify the print composition places
  it before the first live sale of a map edition.
- **Blank-tile regressions**: covered — the snapshotter proves pixels drew, trips a breaker
  after three blanks, and print refuses fallback.

### The two questions, answered constantly

*Would someone pay $100+ to put this on their wall?* — The Harbor, Trail Journal and Streets
pieces, at 300 DPI with authored palettes on archival stock: yes, credibly, once the basemap is
live. *Could someone who has never used a design tool make it in under 60 seconds?* — As of
b518: open activity → Make a Print → the finished piece is the first thing on screen → Order.
Zero design decisions required, all of them available.
