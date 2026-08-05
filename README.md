# StrideMap

Every run you've ever taken, woven into one living map.

StrideMap connects to your Strava account and visualizes your entire running history
on a beautiful, interactive Apple Map. The focus isn't analytics — it's *"where have
I run?"* As your completed streets accumulate, they gradually form a glowing web across
the cities you've explored.

Built with SwiftUI, MapKit, SwiftData, and Strava OAuth for iOS 26.

---

## Features

- **Strava login** via OAuth (`ASWebAuthenticationSession`) with the token set stored
  securely in the Keychain and refreshed automatically.
- **Incremental import** — the first sync pulls your entire history; later syncs fetch
  only new activities (`after` cursor). Everything is cached locally with SwiftData.
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
- **Settings** — connect/disconnect Strava, sync, appearance (system/light/dark),
  units (mi/km), delete cache, GPX export, and a privacy summary.

## Getting started

1. Open `StrideMap.xcodeproj` in **Xcode 26** or later.
2. Create a Strava API application at <https://www.strava.com/settings/api>.
   - Set the **Authorization Callback Domain** to `stridemap`.
3. Open `StrideMap/Config/StravaConfig.swift` and paste your **Client ID** and
   **Client Secret**.
4. Select an iOS 26 simulator or device and run.

> **Security note.** Strava's token exchange requires the client secret. Embedding a
> secret in a shipping app is inherently insecure — for a public release you should
> proxy the token exchange through a small backend you control. For a personal build,
> the values in `StravaConfig` are sufficient. Consider moving them into a
> git-ignored `Secrets.xcconfig`.

## Architecture

```
StrideMap/
├─ StrideMapApp.swift          App entry, SwiftData container, environment wiring
├─ Config/                     Strava OAuth configuration
├─ Models/
│  ├─ Run.swift                SwiftData model + derived values
│  └─ RunFilter.swift          Composable filter (date / mode / surface / place)
├─ Services/
│  ├─ PolylineDecoder.swift    Google encoded-polyline decoder
│  ├─ KeychainStore.swift      Secure token storage
│  ├─ StravaModels.swift       API DTOs
│  ├─ StravaAuthService.swift  OAuth flow + token refresh
│  ├─ StravaAPIClient.swift    v3 REST client
│  └─ SyncService.swift        Incremental import into SwiftData
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
struggles with thousands of overlays. Routes are diffed by activity id between updates,
coloured by recency, and hit-tested for taps in map-point space.

## Notes & limitations

- Strava's `summary_polyline` carries only latitude/longitude, so GPX exports contain
  positions and a per-run start time, but not per-point elevation or timestamps.
- City / state / country come from Strava's per-activity detail endpoint. Large first
  imports may hit Strava's rate limits during enrichment; location is filled in
  best-effort and the rest of the run still imports.
- The **Completion View** (per-city street completion percentages) described in the
  product brief requires OpenStreetMap road data and is intentionally left as a future
  integration — the analytics scaffolding (`RunStatistics`) is in place to support it.
