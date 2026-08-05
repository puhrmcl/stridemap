# StrideMap — App Store Connect metadata (v1.0)

Copy-paste reference for the App Store Connect listing. Character limits are Apple's;
counts are approximate — verify in the form. Nothing here needs a Mac; it's all text you
paste into App Store Connect.

---

## App information

| Field | Value |
|---|---|
| **App Name** (≤30) | `StrideMap` |
| **Subtitle** (≤30) | `Map every run you've taken` |
| **Bundle ID** | `com.stridemap.StrideMap` |
| **SKU** | `STRIDEMAP-001` |
| **Primary language** | English (U.S.) |
| **Primary category** | Health & Fitness |
| **Secondary category** | Navigation *(or Sports)* |
| **Price** | Free |
| **Copyright** | `© 2026 Northwest Ag Technologies, L.L.C.` |
| **Team ID** | `UV4A75F95G` (Northwest Ag Technologies, L.L.C. — Organization) |

### Name alternatives (if "StrideMap" alone is taken)
- `StrideMap: Your Run Map`
- `StrideMap — Running Map`

---

## Promotional text (≤170, editable anytime without a new build)

> Every run you've ever taken, drawn on one beautiful map — automatically, from Apple
> Health. Apple Watch, Nike, Garmin, COROS, Strava and more. Private by design.

_(~150 chars)_

---

## Description (≤4000)

```
StrideMap turns your running history into a living map.

Every run you've ever taken — drawn as a glowing web across the streets, trails, and
cities you've explored. StrideMap isn't about charts or numbers. It's about one simple,
beautiful question: where have I run?

Your runs come straight from Apple Health, so workouts from Apple Watch, Nike Run Club,
Garmin, COROS, Polar, Wahoo, adidas Running, Runna — anything that saves runs to Health —
appear automatically on one map. Recent runs glow; older runs fade gently into the
background, revealing the shape of your running life over time.

MAP-FIRST, ALWAYS
• A full-screen Apple Map is the whole app
• Thousands of routes render smoothly
• Recent runs glow, older runs gently fade
• Gorgeous in light and dark

EVERYTHING IN ONE PLACE
• Automatic import from Apple Health — your entire history
• New runs sync in as you record them
• Filter by time, place, distance, races, road or trail
• Tap any route for distance, pace, time, elevation, and heart rate

EXPLORE WHERE YOU'VE BEEN
• Cities, states, and countries you've run
• Longest run, biggest climb, fastest pace
• A travel map with a pin for every place
• Year in Review with an animated playback of your year

BRING STRAVA IF YOU WANT (OPTIONAL)
• Connect Strava to add titles, gear, and race details
• Matching runs are merged — never any duplicate routes

PRIVATE BY DESIGN
• Your runs stay on your device
• No accounts, no servers, nothing uploaded
• Apple Health access is read-only

StrideMap is calm, minimal, and made for anyone who loves seeing where their feet have
taken them.
```

---

## Keywords (≤100 chars, comma-separated, NO spaces)

```
running,runner,heatmap,gps,routes,strava,garmin,coros,nike,workout,jog,marathon,trail,elevation
```

_(~95 chars. Words already in the app name/subtitle — "map", "run" — are indexed
separately, so they're intentionally omitted here to save space.)_

---

## What's New (release notes, v1.0)

```
The first StrideMap. Connect Apple Health and watch every run you've ever taken appear on
one beautiful map. Filter, explore, and relive your year. Thanks for running with us.
```

---

## URLs

| Field | Value |
|---|---|
| **Privacy Policy URL** (required) | `https://puhrmcl.github.io/stridemap/privacy.html` |
| **Support URL** (required) | `https://puhrmcl.github.io/stridemap/` *(served by `docs/index.html`)* |
| **Marketing URL** (optional) | `https://puhrmcl.github.io/stridemap/` |

> Both URLs are served by GitHub Pages from `/docs` once Pages is enabled. When
> `stridemap.nwagtech.com` is set up (see `PLATFORM.md`), switch these to
> `https://stridemap.nwagtech.com/privacy.html` and `https://stridemap.nwagtech.com/`.

---

## App Review Information

- **Sign-in required?** No. No account or login is needed; the app works with Apple Health
  alone.
- **Demo account:** Not applicable.
- **Contact:** software@nwagtech.com

### Review notes (paste into the "Notes" field — this is what prevents HealthKit rejections)

```
StrideMap visualizes the user's running workouts from Apple Health on a map. No account or
login is required — all core functionality works with Apple Health alone.

HEALTHKIT
On first launch the app requests READ-ONLY access to Health: running workouts, workout
routes (GPS), distance, duration, elevation, heart rate, active energy, and cadence. The
app never writes to Health.

IMPORTANT FOR TESTING: The map draws routes from running workouts stored in Health. If the
review device/simulator has no running workouts with GPS routes, the map will be empty
(this is expected). To see the app populated, please test on a device that has recorded
outdoor runs, or add a running workout in the Health app first. Granting the Health
permission prompt is required to load any data.

STRAVA (OPTIONAL)
Strava is an optional enhancement and is NOT required for review — it can be skipped
entirely. When connected, it only adds metadata (titles, gear, race flags) to runs that
already exist in Apple Health; it never creates duplicate runs.

PRIVACY
The app has no backend and no user accounts. All run data is stored on-device only and is
never uploaded. Health data is never used for advertising and is never shared with third
parties.

Questions: software@nwagtech.com
```

---

## App Privacy ("nutrition labels")

StrideMap does not transmit any user data off the device, so under Apple's definition it
does **not "collect"** data. Recommended answers:

- **Do you or your third-party partners collect data from this app?** → **No, we do not
  collect data from this app.** (All Health, location, and Strava data is used only
  on-device and never sent to our servers — we have none.)
- **Tracking (App Tracking Transparency):** No tracking. The app does not use IDFA or track
  users across apps/websites.

> If you later add analytics, crash reporting, or any server sync, you must revisit this
> section — those would count as collection.

---

## Age rating

- Answer every content question **"None."**
- Resulting rating: **4+**.

---

## Export compliance

- Uses only standard OS encryption (HTTPS). Already declared in Info.plist:
  `ITSAppUsesNonExemptEncryption = false`. Answer **"No"** to the non-exempt encryption
  question.

---

## Content rights

- The app displays the user's own data plus Apple Maps and (optionally, with the user's
  authorization) Strava. If asked whether the app contains third-party content, note that
  all third-party content is accessed with the user's authorization (Apple Health, Apple
  Maps, Strava via OAuth). No licensing issues.

---

## Still needed before submitting (require a Mac / your accounts)

- [ ] **Apple Developer Program** enrollment ($99/yr).
- [ ] **App icon** — real 1024×1024 (current asset is a placeholder).
- [ ] **Screenshots** — 6.9" iPhone (required) and 6.5"/6.7" as needed; iPad if you ship
      iPad. Capture from a device with real runs on the map.
- [ ] First **Xcode archive** on device → TestFlight → submit.
- [ ] Enable **GitHub Pages** so the Privacy Policy + Support URLs resolve (Settings →
      Pages → `main` / `/docs`).
