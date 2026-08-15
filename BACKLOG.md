# Etch — Backlog

Deferred ideas and follow-ups we've agreed to come back to. Not scheduled; no order implied.

## Video support (pinned)
Run videos in galleries and video output in Etch Studio for digital sharing.

- **Open decision — gallery media model:** separate `videoReferences: [String]` (simplest; posters/prints stay image-only by construction) **vs** a unified, capture-time-ordered typed media list (nicer gallery, more model/migration work). *Pinned — decide when we pick this up.*
- **Phase 1 — videos in galleries (low complexity):**
  - Photo refs are already `PHAsset.localIdentifier` strings, so videos are just assets with `mediaType == .video` — no new storage (we only store references).
  - Widen `PhotoLibrary.matchingIdentifiers` predicate to `image OR video` (videos carry creationDate + location, so time/location matching is unchanged).
  - Thumbnails: `PHImageManager.requestImage` already returns a poster frame for videos — show a play badge overlay.
  - Full-screen viewer (`RunPhotoViews.swift`): branch to `VideoPlayer` backed by `PHImageManager.requestPlayerItem` (handles iCloud download).
  - Photo picker filter: `.images` → `.any(of: [.images, .videos])`.
  - Risks: iCloud-only videos need a network fetch (spinner); Live Photos treated as image for v1.
- **Phase 2 — Studio "Motion / Reel" export (high complexity, digital-only):**
  - New output type — not the static `ImageRenderer` → PNG path. Composite the run video with an Etch overlay (route trace + title + key stats) burned in, export a vertical 9:16 MP4 for Stories/Reels.
  - Pipeline: `AVMutableComposition` + `AVMutableVideoComposition` + `CALayer` overlay via `AVVideoCompositionCoreAnimationTool` → `AVAssetExportSession` (with progress UI).
  - MVP: static burned overlay. V2: animate the route drawing in as the clip plays.
  - Risks: export time/memory on older devices, portrait/landscape source handling, audio keep/mute, share file size. Prints stay image-only.

## Indoor / treadmill runs (b139 shipped capture + tiles)
- Effort-trace visual for indoor tiles (pace/HR ribbon) in place of a route glyph.
- "＋ N indoor runs" acknowledgment in the home-map totals so indoor runs aren't silently absent from the map.
- Map Strava's "trainer" flag → `isIndoor` (currently HealthKit-only).
- One-time backfill: flag `isIndoor` on already-stored routeless runs (today only newly synced runs get flagged).

## Studio output sizes / aspect ratios
Two separate problems: **pixels/DPI** (trivial — we already scale to ~5400px @ 300 DPI, PNG) and
**aspect + layout** (the real work — compositions are authored at fixed aspects: Wall Art portrait
is 2:3, single-state ~5:7, framed/footer variants are taller non-standard ratios).

- **Core capability:** make the composition **aspect-adaptive**, driven by an `OutputTarget`
  (aspect + pixel target + optional bleed/safe zone/format). Build once; both social and print ride on it.
- **Social sizes (digital, do first — good forcing function):** an "Output" picker for **1:1**
  (IG square), **4:5** (IG feed), **9:16** (Story/Reel/TikTok). 9:16 needs a genuine tall layout,
  not a crop. No bleed/DPI concerns — digital only. De-risks the aspect-adaptive layout for print.
- **Print / drop-shipping (defer to Prodigi wiring):** files must match each SKU's exact aspect +
  bleed (3–5mm) + safe zone, 300 DPI at physical size, sRGB, JPEG. Standard frame sizes are mixed
  aspects (8×10 & 16×20 = 4:5, 18×24 = 3:4, A-series ≈ 1:1.41), so print needs the same aspect
  flexibility. Exact dims/bleed come from the Prodigi product catalog — build when that lands.

## Multi-activity (hikes, then walks) — Phase 1 shipped (b146)
The `Run` model already carries `ActivityType` (run/walk/hike/…); we're teaching the importer and
UI to be type-aware rather than adding a model. Decisions made: **per-type** achievements/superlatives
(pace/PRs stay run-only; hikes get longest/most-climb/highest); include hikes now, **walks later with
an opt-out** (Apple Watch auto-logs many short walks, so walks need the toggle before import).

- **Phase 1 (done):** HealthKit query expanded to `.running` + `.hiking`; `activityType` set from the
  workout type; hike routes hydrate; time-of-day default name is type-aware ("Morning Hike"); sync
  summary reports the hike count. *Note:* until Phase 2, hikes appear mixed into the runs UI (counted
  in "N runs", eligible for run superlatives) — that's the confirmation they landed.
- **Phase 2 (done, b147):** activity selector on the left of the totals pill (All / Runs / Hikes,
  default All each launch, icons); count relabels ("928 activities" / "886 runs" / "42 hikes");
  consistent scope across Home map/totals, Timeline, Studio, Achievements; **walks** added with an
  "Include walks" setting (Settings, default off) that gates import + the selector. Pace superlatives
  (Fastest, distance PRs) hidden for hikes/walks.
- **Phase 3 (partial / todo):** per-type sectioning in Achievements when scope = All (currently the
  achievements scope to the selected type; a dual Runs/Hikes layout for "All" is still todo);
  hike-appropriate Studio hero (elevation instead of pace) and type-aware Studio metric defaults;
  scope the secondary surfaces (Profile, Year in Review, Search, States) too; walk **backfill** on
  toggle-on (today only forward sync imports walks — a full Delete & re-sync backfills older ones).
- **AllTrails history:** no public API. Realistic paths — (a) Apple Health sync (AllTrails → Health,
  picked up automatically going forward); (b) GPX import via the existing file pipeline for historical.
  Nike Run Club is runs-only (not a hike source).

## Maps
- Countries choropleth: select-to-isolate + run pins, mirroring the state-selection behavior (b134). Optional: higher-res country boundary data if the 110m simplification looks too coarse up close.
- Home-map cluster rebuild: optional cross-fade / smoother threshold if the zoom re-draw feels flickery.

## Studio / prints
- Optional: auto-keep exported posters (vs the current explicit bookmark) so every export lands in "Your Etches".
- Wall Art state filter: full state names ("Arizona") via point-in-polygon vs the stored abbreviations ("AZ").
- Distance-PR milestones: add 1K / 1-mile if we want finer granularity than 5K+.
