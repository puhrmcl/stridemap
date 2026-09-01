# Feature Spec — Run Photos (auto-match + manual)

Attach photos to runs so a run detail can show the moments from that run. Two
sources, designed so **every** run can have photos regardless of its origin
(Nike Run Club, Strava, or Apple Health):

1. **Auto-match** — pull photos from the user's own camera roll that were taken
   *during* the run's time window and *near* its route. Zero tagging, works for
   all runs. **Primary.**
2. **Manual attach** — a photo picker to add/remove specific photos. Covers
   anything auto-match misses (screenshots, others' photos AirDropped in, etc.).

This sidesteps the Strava/NRC API limitations entirely: it keys off the user's
photo library, not the run's source.

---

## 1. Permissions

- Add `NSPhotoLibraryUsageDescription` to Info.plist:
  *"Etch finds photos you took during a run so they can appear with it. Your
  photos stay on your device."*
- Request **limited or full** photo-library access via `PHPhotoLibrary`.
  - Auto-match needs read access to asset metadata (date + location). Works with
    `.authorized`. With `.limited`, only user-selected assets are visible — so
    auto-match degrades gracefully to "match within the limited set"; the manual
    `PhotosPicker` still works fully.
- Request lazily, the first time the user opens a run detail or taps "Add
  Photos" — never at launch. If denied, hide auto-match and keep manual picker
  (which uses the out-of-process picker and needs no permission).

## 2. Matching algorithm (auto-match)

Inputs per run: `startDate`, `elapsedTime` (→ end), the route's bounding box and
coordinates.

1. **Time window**: `[startDate − padBefore, endDate + padAfter]`, pad ≈ 5 min
   each side (photos taken right before/after count). Query the library with a
   `PHFetchOptions` predicate on `creationDate` in that window
   (`mediaType == .image`). This is indexed and fast.
2. **Location filter**: for each candidate asset with a `location`
   (`PHAsset.location`), keep it if within **~250 m** of the route (distance to
   nearest route point, or inside the bounding box + margin). Assets with no GPS
   (many indoor/edited photos) fall back to **time-only** match, flagged
   lower-confidence.
3. **Confidence / ranking**: time+location = high; time-only = medium. Sort by
   `creationDate`. Cap to a sane number per run (e.g. 30) for the UI.
4. **Cache** the matched local identifiers on the run (see data model) so we
   don't re-scan every open; re-scan on demand ("Find photos") and when the run
   is first seen.

Notes:
- Elapsed vs moving time: use **elapsed** for the window (photos happen during
  stops).
- Route-less runs (Nike, no GPS): time-only match still works — a huge win, since
  those are the runs that otherwise have no imagery at all.

## 3. Data model

Store **references**, not image bytes (avoid bloating the SwiftData store and
duplicating the library):

```
// New model, or fields on Run
@Model final class RunPhoto {
    var assetLocalIdentifier: String?   // PHAsset id for auto-matched / picked library photos
    var importedFileName: String?       // for photos copied into app storage (e.g. from Strava)
    var addedManually: Bool
    var createdAt: Date
    var run: Run?                       // relationship
}
```

- **Auto-matched & picker photos**: store the `PHAsset.localIdentifier`; load
  thumbnails/full images on demand via `PHImageManager`. No copying — respects
  the library as source of truth.
- **Caveat**: a local identifier breaks if the user deletes that photo from
  Photos. Handle gracefully (skip missing assets; optionally offer "keep a copy"
  for favorites).
- **Imported photos** (future Strava source): download and copy into the app's
  Application Support directory, reference by filename. Only these consume app
  storage.
- Persist the auto-match cache as a set of local identifiers + a
  `photosScannedAt` date on `Run` so we can show instantly and re-scan lazily.

## 4. UI

- **Run detail**: a horizontal photo strip below the map (thumbnails, tap → full
  screen pager). Empty state: a subtle "Add photos" affordance. If auto-match
  found candidates the user hasn't confirmed, show them with a light "from your
  library during this run" caption and a way to remove.
- **Add Photos**: SwiftUI `PhotosPicker` (multi-select). Selected assets append
  as `RunPhoto` with `addedManually = true`.
- **Full-screen viewer**: standard pager with share/remove.
- **Timeline tie-in** (optional, later): a run's tile could use its top photo as
  the thumbnail instead of the route drawing — very Photos-like.

## 5. Performance

- Thumbnails via `PHCachingImageManager` with target sizes matched to the strip;
  prefetch visible ones.
- Auto-match scan is bounded (indexed date predicate first, then a cheap
  distance check on the small candidate set) — run it off the main actor and
  cache the result. Do **not** scan all runs eagerly; scan per run on first view,
  or a bounded background pass for recent runs.

## 6. Edge cases

- **Limited library access** → auto-match only sees selected assets; lean on
  manual picker; surface a "Select more photos" hint.
- **No location on photos** → time-only match (medium confidence).
- **Wrong matches** (e.g. a passenger photo mid-drive to the trailhead) → always
  let the user remove; keep auto-matched photos visually distinct from confirmed
  ones until kept.
- **Deleted library asset** → skip silently, prune the cached id.
- **Time zones / DST** → compare in absolute time (`Date`), not local components.
- **Privacy** — everything stays on device; nothing uploaded. Reflect in the
  existing Privacy copy.

## 7. Phasing

1. **v1** — manual `PhotosPicker` on run detail + `RunPhoto` model + viewer.
   (Small, ships the storage + UI foundation.)
2. **v2** — auto-match by time (+ location when available), with a per-run "Find
   photos from this run" action and cached results.
3. **v3** — optional Strava photo import (download + copy), and using a run's top
   photo as its Timeline tile.

## 8. Frameworks

`Photos` / `PhotosUI` (PHAsset, PHFetchOptions, PHImageManager, PhotosPicker),
`CoreLocation` (distance), SwiftData (RunPhoto). No third-party dependencies.
