# Etch — app summary

*Context brief for handing to another AI assistant. Written 2026-09-01, against build b514.*

## What it is

Etch is a native iOS app that turns your entire activity history into one living map — and
then lets you print pieces of it. The premise is not analytics. It is *"where have I been?"*
Every route you have ever recorded accumulates into a glowing web across the cities you have
run, hiked, ridden and walked.

Two halves, one product:

1. **The library.** Your whole history, on a map, in a timeline, and as a set of records.
2. **Studio.** A print shop built on that history — posters, books and framed objects
   generated from your own routes and photographs, ordered in-app and drop-shipped.

The commercial idea is that the second half only exists because the first half is complete.
Nobody prints a poster of three runs.

## Platform and stack

| | |
|---|---|
| Platform | iOS 18+, iPhone |
| UI | SwiftUI |
| Persistence | SwiftData, entirely on-device |
| Maps | MapKit (`UIViewRepresentable` for the route map) |
| Health data | HealthKit |
| Commerce | Shopify checkout (`ShopifyCheckoutSheetKit`) → Cloudflare Worker → Prodigi |
| Backends | Two Cloudflare Workers (see below). No app server, no accounts, no user database. |
| CI/CD | Xcode Cloud → TestFlight; GitHub Actions for everything else |
| Owner | Northwest Ag Technologies, L.L.C. (`nwagtech.com`), Apple Team ID `UV4A75F95G` |

Roughly 37,000 lines of Swift across ~150 files, plus a TypeScript fulfilment worker, a
Shopify theme, and a small OAuth proxy.

## Where the data comes from

**Apple Health is the primary source, deliberately.** Anything that writes workouts into
HealthKit shows up automatically — Apple Workouts, Nike Run Club, Garmin, COROS, Polar,
Wahoo, adidas Running, Runna, Strava itself. The user's history belongs to them, not to
whichever platform they happened to use in 2019.

**Strava is optional enrichment.** OAuth via `ASWebAuthenticationSession`, token in the
Keychain, auto-refreshed. It adds titles, gear, race identification and place names on top of
what Health already has. The client secret never ships in the app — a Cloudflare Worker
performs the token exchange.

**Merging.** HealthKit and Strava copies of the same activity are matched by a confidence
score (start time, distance, duration, GPS start proximity) and merged into one activity, so
the map never draws a duplicate route.

**Provider abstraction.** Every source conforms to `ActivityProvider` and produces a
provider-agnostic `ImportedActivity`; the UI only ever sees the unified `Run` model. New
integrations drop in without UI changes.

**Reading Health correctly is subtler than it looks.** The import uses an
`HKAnchoredObjectQuery`, not a start-date predicate. A watch or third-party app often writes a
workout into Health hours after it happened, so its *start* date is older than the last sync —
a date-bounded query would skip it permanently. The anchor keys off arrival in the store
instead. Anchors are held per workout type and advance only after the ingested workouts are
saved.

Activity types imported: **runs, hikes, rides, walks.** Walks are off by default (Apple Watch
logs many short ones). Each type can be toggled in Settings, and turning one on backfills its
whole history.

## Structure of the app

Four tabs plus the system's detached search:

- **Map** — the full-screen route map. Thousands of routes rendered smoothly; recent runs
  glow, older ones fade into the web. A floating glass header carries the totals; activity
  view (All / Recent / PRs / Races / Favorites) and the place overlays (city pins, state and
  country choropleths, landmarks) are chosen from a sheet.
- **Timeline** — Apple Photos' model: **Years / Months / All / Gallery**. Oldest at the top,
  newest at the foot, and the page opens on the newest. Gallery is every photograph from every
  activity as one wall, with a full-screen viewer and a filmstrip.
- **Achievements** — reach (cities, states, countries), a per-discipline breakdown, records
  and personal bests, and Year in Review recaps. Tapping a city or state narrows the whole app
  to it.
- **Studio** — the shop.

The **Bag** lives in Studio's header rather than on the bar; a shopping basket does not deserve
a permanent quarter of the navigation on a screen most people open to look at where they have
been. The tab bar's five glyphs are custom-drawn vector assets on one 28pt grid, not SF Symbols.

**A shared filter** (`RunFilter`) spans date range, mode, surface, city/state/country and
distance/duration bounds. It is session-wide: set it on the map and the Timeline, the Gallery
and Achievements all narrow with it, with a chip naming what is set. Studio deliberately
ignores it — someone arrives there to print a specific activity, and a filter set twenty
minutes ago silently hiding it reads as the app having lost the run.

## Studio — the products

| Product | What it is |
|---|---|
| **Map Prints** | One route, over real geography |
| **Gallery Prints** | Photos, map and elevation, composed |
| **Anthology** | The whole history as one object — five generative styles: grid, ridgeline, rings, thread, strata |
| **Lithograph** | A city-index tour poster over a world / country / state ground |
| **Year in Review** | A year of it, bound — a printed photo book |
| **Collections** | The same book scoped to a state, a city, favourites or races |
| **Photo Wall** | Forty photographs in one frame |
| **Medal Frame** | The medal, and the day you earned it |

Formats ladder by price: bare print ($59–$109) → poster hanger ($129) → framed under glass
($139–$179). Books are $119, photo wall $199, medal frame $249.

Everything is rendered on-device at full print resolution (a 20×30" sheet is ~78 million
pixels), frozen to R2 at order time, and produced by Prodigi.

There is also an **event library** — a catalogue of races and summits with official courses,
so a user can add a race they ran before they had the app, or log a peak. It carries state
high points and Colorado 14ers as peak lists, which gate a special-edition summit poster.

## Backends

Two Cloudflare Workers, both thin:

1. **`worker/`** — Strava OAuth token exchange and refresh. Exists so the client secret is not
   in the app bundle.
2. **`fulfilment/`** — the spine between Shopify and Prodigi. Frozen production assets in R2,
   an order↔creation↔asset ledger in D1, Shopify `orders/paid` webhooks in (HMAC-verified),
   Prodigi orders out, status mapped back to the app's normalized states. It also serves a
   remote config (`app.json`) that carries prices and feature gates, so pricing can change
   without an App Store release.

`storefront/` is the Shopify theme. `docs/` is served by GitHub Pages (privacy policy, support).

## How it is built and shipped

**The author has no Mac.** Everything ships through CI:

- Pushing to the working branch triggers **Xcode Cloud**, which builds, signs and delivers to
  **TestFlight**.
- **GitHub Actions** stands in for a terminal: a *Preview screens* workflow builds for the
  simulator, launches the app with `ETCH_PREVIEW=<screen>` against a synthetic 220-activity
  history, and posts base64 screenshots into the job log — so a UI change can be *looked at*
  in about five minutes instead of a full TestFlight cycle. Other workflows deploy the workers
  and the storefront, verify the Prodigi catalogue, and run map diagnostics.
- `AppInfo.changeTag` is hand-bumped on every meaningful change (`b514` at time of writing) and
  shown in Settings, so the build actually installed on a device is identifiable.

Practical consequence for anyone advising on this project: **suggestions that require a local
Xcode, a simulator, Instruments, or a shell on a Mac are not actionable.** Anything that needs
running must run in CI or on the device.

## Design principles worth knowing

- **Apple Photos is the reference** for the Timeline: one scope control, oldest at the top,
  the page opens on the newest thing.
- **Name what is happening, don't count it.** The filter chip says "Races · Flagstaff", not
  "2 filters".
- **Vocabulary follows the data.** A year of nothing but hikes says "hikes", a mixed history
  says "activities", never "runs".
- **A door to an empty room is worse than no door.** Controls disappear when they lead nowhere
   — the Gallery segment is absent until there is a photograph.
- **Measure the render, don't eyeball it.** Layout claims get verified with a screenshot from
  CI, not asserted.

## Known state and open questions

- Pre-launch. The app is feature-complete and on TestFlight; the outstanding work is a Shopify
  store build, App Store Connect privacy answers, and flipping Prodigi from sandbox to
  production.
- The 14ers dataset holds 9 of 58 peaks — the poster's completion gate is honest about it.
- Performance was recently overhauled: the heavy screens now derive their data once per change
  rather than once per property access, keyed on the newest `updatedAt` across the library.
  Any screen that looks stale after an edit means a mutation somewhere is not bumping that
  timestamp.
- The README in the repo predates the commerce half and describes some retired features
  (a "Long Runs" mode, an "Explore" tab). This document is the current picture.
