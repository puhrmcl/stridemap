# StrideMap

Every run you've ever taken, woven into one living map.

StrideMap visualizes your entire running history on a beautiful, interactive Apple Map.
The focus isn't analytics — it's *"where have I run?"* As your completed streets
accumulate, they gradually form a glowing web across the cities you've explored.

Your running history belongs to **you**, not to any single platform. **Apple Health is
the primary source**, so runs recorded by Apple Workouts, Nike Run Club, Garmin, COROS,
Polar, Wahoo, adidas Running, Runna, Strava — anything that writes running workouts into
HealthKit — all appear automatically. **Strava is an optional enrichment** that adds
titles, gear, and race details on top.

Built with SwiftUI, MapKit, SwiftData, HealthKit, and Strava OAuth for iOS 26.

---

## Features

- **Apple Health as the primary source** — reads running workouts, GPS routes, distance,
  duration, elevation, heart rate, active energy, and cadence via HealthKit, with an
  observer query + background delivery to keep syncing as new workouts arrive.
- **Multi-ecosystem** — any app that writes running workouts into Apple Health shows up
  automatically (Apple Workouts, Nike Run Club, Garmin, COROS, Polar, Wahoo, adidas
  Running, Runna, …). The origin app is detected and shown, subtly, on the detail screen.
- **Strava as optional enrichment** via OAuth (`ASWebAuthenticationSession`), token in the
  Keychain, auto-refreshed. Adds titles, gear, race identification, and place names.
- **Intelligent merging** — HealthKit and Strava copies of the same run are matched by a
  confidence score (start time, distance, duration, GPS start proximity) and merged into a
  single activity, so the map never shows a duplicate route.
- **Provider abstraction** — every source conforms to `ActivityProvider` and feeds a
  provider-agnostic `ImportedActivity`; the UI only ever sees the unified `Run` model, so
  new integrations (Garmin, COROS, Polar, Suunto …) drop in without UI changes.
- **Incremental import** — the first sync pulls your entire history; later syncs fetch
  only newer activities. Everything is cached locally with SwiftData.
- **Full-screen map** rendering thousands of routes smoothly via a MapKit
  `UIViewRepresentable`. Recent runs glow; older runs fade into a subtle web.
- **Floating glass controls** — total distance & run count up top; search, filters,
  timeline, explore, travel, and settings floating at the bottom.
- **Quick modes** — All Runs · Recent · Long Runs · PRs · Races.
- **Filters** — date ranges (7/30 days, month, year, custom), surface (road/trail),
  races, and city / state / country.
- **Run details** — distance, time, pace, elevation, an interactive map preview, and
  an *Open in Strava* button.
- **Timeline** grouped by month & year; tap any run to zoom the map straight to it.
- **Explore** — cities / states / countries reached, longest run, highest climb,
  fastest pace, northernmost & southernmost runs, and most-visited route.
- **Travel map** — a pin for every place you've run; tap to see that trip's runs.
- **Year in Review** — an auto-generated recap with an animated playback that draws
  every run of the year across the map.
- **Search** across names, cities, states, races, and dates.
- **Data sources** — Apple Health (primary) and Strava (optional) managed in Settings,
  plus sync, appearance (system/light/dark), units (mi/km), delete cache, GPX export, and
  a privacy summary.

## Getting started

1. Open `StrideMap.xcodeproj` in **Xcode 26** or later.
2. Signing & entitlements are pre-wired: the target ships `StrideMap.entitlements` with
   the **HealthKit** (and HealthKit background-delivery) entitlement, and the Info.plist
   carries `NSHealthShareUsageDescription`. With automatic signing, select your team and
   run — HealthKit is enabled from the entitlements file.
3. Run on a device (or a simulator with sample workouts added in the Health app). On first
   launch, grant Apple Health access — your entire running history imports and maps.
4. *(Optional)* To enable Strava enrichment:
   - Create an API application at <https://www.strava.com/settings/api> and set the
     **Authorization Callback Domain** to `stridemap`.
   - Deploy the token-proxy Worker in [`worker/`](worker/README.md) (Cloudflare, free) —
     it holds your Strava **client secret** server-side so it never ships in the app.
   - Paste your **Client ID** and the Worker URL into `StrideMap/Config/StravaConfig.swift`
     (`clientID`, `tokenProxyURL`). Then connect Strava from onboarding or Settings.

> **Notes.** HealthKit needs a real device or a simulator seeded with running workouts;
> it isn't available on Mac (Designed for iPad). The Strava client secret is **never** in
> the app — the Cloudflare Worker in `worker/` performs token exchange/refresh (see
> `worker/README.md`). The app ships only the public Client ID.

## Architecture

```
StrideMap/
├─ StrideMapApp.swift          App entry, SwiftData container, environment wiring
├─ Config/                     Strava OAuth configuration
├─ Models/
│  ├─ Run.swift                Unified SwiftData model (UUID id, provider, metrics, gear…)
│  ├─ ImportedActivity.swift   Provider-agnostic import DTO
│  ├─ ActivitySource.swift     Source taxonomy + fuzzy detection from HealthKit
│  └─ RunFilter.swift          Composable filter (date / mode / surface / place)
├─ Services/
│  ├─ ActivityProvider.swift   Provider protocol (primary vs. enrichment roles)
│  ├─ HealthKitService.swift   Authorization, availability, background observation
│  ├─ HealthKitProvider.swift  Reads workouts, routes & metrics → ImportedActivity
│  ├─ StravaProvider.swift     Strava as an enrichment provider
│  ├─ ActivityMatcher.swift    Confidence scoring for de-duplication
│  ├─ SyncService.swift        Orchestrates providers, merges, geocodes → SwiftData
│  ├─ LocationEnricher.swift   Best-effort reverse geocoding (HealthKit has no places)
│  ├─ PolylineDecoder.swift    Google polyline codec + bounding-box helper
│  ├─ KeychainStore.swift      Secure token storage
│  ├─ StravaModels.swift       Strava API DTOs
│  ├─ StravaAuthService.swift  OAuth flow + token refresh
│  └─ StravaAPIClient.swift    v3 REST client
├─ ViewModels/
│  ├─ AppModel.swift           Shared UI state (filter, selection, camera)
│  └─ RunStatistics.swift      Pure derived analytics (Explore/Travel/Recap)
├─ Design/                     Theme + Liquid-Glass controls
├─ Map/                        High-performance MKMapView route renderer
├─ Utilities/                  Formatters, GPX export
└─ Views/                      Onboarding, Home, Filters, Details, Timeline,
                               Explore, Travel, Year in Review, Search, Settings
```

The map layer (`Map/RunMapView.swift`) wraps `MKMapView` because SwiftUI's `Map`
struggles with thousands of overlays. Routes are diffed by run id between updates,
coloured by recency, and hit-tested for taps in map-point space.

### Adding a new provider

Conform a type to `ActivityProvider`, translate its native activities into
`ImportedActivity`, and add it to `SyncService`'s provider list. Set `role` to
`.enrichment` if it should merge into existing runs rather than create new ones. Nothing
in the UI changes — it only ever consumes the unified `Run` model.

## Notes & limitations

- **Place names.** HealthKit doesn't geocode, so city / state / country are filled in
  by best-effort reverse geocoding (`LocationEnricher`), bounded per sync to respect
  `CLGeocoder` limits — locations populate gradually across syncs. Strava, when connected,
  provides them directly.
- **Merging.** The match threshold and field weights live in `ActivityMatcher`; tune them
  there if you find false merges/splits. Runs with no GPS still match on time/distance/
  duration.
- **GPX export** contains positions and per-run start time, but not per-point elevation or
  timestamps (summary routes don't carry them).
- **Rate limits.** Strava enrichment fetches per-activity detail; very large first imports
  may hit Strava's limits — enrichment is best-effort and never blocks the HealthKit runs.
- The **Completion View** (per-city street completion percentages) still requires
  OpenStreetMap road data and remains a future integration — `RunStatistics` is in place
  to support it.
