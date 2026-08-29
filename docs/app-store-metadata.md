# Etch — App Store Connect metadata

Copy-paste reference for the App Store Connect listing. Character limits are Apple's;
the counts beside each field were measured, but verify in the form. Nothing here needs a
Mac; it's all text you paste into App Store Connect.

> **Rewritten for the expanded app.** The v1.0 listing described a running heat map, which
> is no longer what Etch is: it covers runs, rides, hikes and walks, and half the product
> is now Studio — turning any of it into a print that gets made and shipped. Two things in
> the old listing were not just narrow but **wrong**, and both are corrected below: the
> description claimed "nothing uploaded", and the App Privacy answers claimed no data is
> collected. Ordering a print uploads the artwork and takes a name, an email and a shipping
> address. See **App Privacy** — that section needs changing in App Store Connect before
> the next submission, not just here.

---

## App information

| Field | Value |
|---|---|
| **App Name** (≤30) | `Etch: Activity Map & Prints` *(27)* |
| **Subtitle** (≤30) | `Every mile, mapped and framed` *(29)* |
| **Bundle ID** | `com.nwagtech.etch` |
| **SKU** | `ETCH-001` |
| **Primary language** | English (U.S.) |
| **Primary category** | Health & Fitness |
| **Secondary category** | Navigation *(or Sports)* |
| **Price** | Free *(with in-app purchase of physical goods)* |
| **Copyright** | `© 2026 Northwest Ag Technologies, L.L.C.` |
| **Team ID** | `UV4A75F95G` (Northwest Ag Technologies, L.L.C. — Organization) |

### On the name

"Running Map" was doing the search work and is now inaccurate — a cyclist searching for
this app would bounce off it, and a runner arriving would not learn that the prints exist.
"Activity Map & Prints" keeps two indexed phrases, covers both halves of the product, and
leaves the brand first.

### Tagline

- **"Remember Everything. Etch It."** (primary) · *"Made to move. Made to last."*

---

## Promotional text (≤170, editable anytime without a new build)

```
Every run, ride, hike and walk you've taken, on one map — automatically, from Apple Health. Then turn any of it into a gallery-grade print, made and shipped to you.
```

---

## Description (≤4000)

```
Etch turns everything you've done into something you can keep.

Every run, ride, hike and walk you've ever recorded, drawn as one map of the streets, trails and cities you've moved through. Not charts. Not a leaderboard. One beautiful answer to a simple question: where have I been?

And then — because a map on a phone is still a map on a phone — Etch Studio turns any of it into a real object. A print, on real paper, made and shipped to your door.

EVERYTHING ON ONE MAP
• Runs, rides, hikes and walks, all together or one type at a time
• Your whole history arrives automatically from Apple Health
• Thousands of routes render smoothly, recent ones bright, older ones fading back
• Filter by time, place, distance, races, road or trail
• Tap any route for distance, pace, time, elevation and heart rate

EVERY PLACE YOU'VE BEEN
• Cities, states and countries you've moved through, counted and mapped
• Landmarks and national parks you've reached
• Longest, highest, fastest — the days worth remembering
• Year in Review, with your year played back

ETCH STUDIO — MAKE SOMETHING REAL
• Map Prints — one route, over real geography
• Gallery Prints — photos, map and elevation, composed
• Anthology — everything you've done, as one object
• Lithograph — every city you've run, set as type
• Photo Wall — forty days, one frame
• Year Book — a year of it, bound
• Medal Frame — the medal, and the day you earned it

PRINTED PROPERLY
• Museum-grade paper, printed and shipped by a professional lab
• Fine-art prints, prints with a wood hanger, or framed behind glass
• Choose your paper, your layout, your type and your colours
• Add several pieces to a bag and check out once, or buy one with Apple Pay

BRING YOUR HISTORY WITH YOU
• Apple Health carries workouts from Apple Watch, Nike Run Club, Garmin, COROS, Polar, Wahoo, adidas Running, Runna and more
• Import GPX, TCX and FIT files, or a Nike export, for anything Health never saw
• Connect Strava (optional) to add titles, gear and race details
• Matching activities are merged — never a duplicate route

YOUR DATA
• Your activities stay on your device. There is no account and no sync.
• Apple Health access is read-only, and Health data is never used for advertising or shared with anyone.
• If you order a print, that artwork is uploaded so the lab can make it, and checkout takes the name and address needed to post it to you. Nothing else leaves your phone.

Etch is calm, minimal, and made for anyone who wants their miles to end up as more than a number.
```

---

## Keywords (≤100 chars, comma-separated, NO spaces)

```
run,ride,hike,walk,heatmap,gps,route,strava,garmin,coros,poster,marathon,cycling,trail,medal
```

_(91 chars. Words already in the app name and subtitle — "map", "print", "activity",
"mile" — are indexed from those fields, so they are left out here to buy room for the
activity types the old listing never claimed.)_

---

## What's New (release notes)

```
Etch is no longer just for runs. Rides, hikes and walks now sit on the same map, with every city, state and park you've reached counted alongside them.

And Etch Studio is here: turn any of it into a real print — a poster of one route, a year bound as a book, every city set as type, your medal framed with the day you earned it. Museum-grade paper, made and shipped to you.

New look throughout, in Etch's own typeface and colour.
```

---

## URLs

| Field | Value |
|---|---|
| **Privacy Policy URL** (required) | `https://puhrmcl.github.io/etch/privacy.html` |
| **Support URL** (required) | `https://puhrmcl.github.io/etch/` *(served by `docs/index.html`)* |
| **Marketing URL** (optional) | `https://puhrmcl.github.io/etch/` |

> Both URLs are served by GitHub Pages from `/docs` once Pages is enabled. When
> `etch.nwagtech.com` is set up (see `PLATFORM.md`), switch these to
> `https://etch.nwagtech.com/privacy.html` and `https://etch.nwagtech.com/`.
>
> The privacy policy and the support page have both been corrected to match this file —
> `docs/privacy.md`, `docs/privacy.html` and `docs/index.html`.

---

## App Review Information

- **Sign-in required?** No. No account or login is needed; the app works with Apple Health
  alone, and Studio can be used without buying anything.
- **Demo account:** Not applicable.
- **Contact:** software@nwagtech.com

### Review notes (paste into the "Notes" field)

```
Etch shows the user's workouts from Apple Health on a map, and lets them turn those
into printed artwork that is manufactured and shipped by a third-party print lab.
No account or login is required for any part of the app.

HEALTHKIT
On first launch the app requests READ-ONLY access to Health: running, cycling, hiking
and walking workouts, workout routes (GPS), distance, duration, elevation, heart rate,
active energy and cadence. The app never writes to Health.

IMPORTANT FOR TESTING: The map draws routes from workouts stored in Health. If the review
device/simulator has no workouts with GPS routes, the map will be empty (this is expected).
To see the app populated, please test on a device that has recorded outdoor activities, or
add a workout in the Health app first. Granting the Health permission prompt is required to
load any data.

PHYSICAL GOODS (NOT IN-APP PURCHASE)
Etch Studio sells physical printed goods — paper prints, framed prints, a bound book, a
medal frame. These are physical products shipped to the customer, so under App Store Review
Guideline 3.1.3(e)/3.1.5(a) they are paid for outside of In-App Purchase. Checkout is
handled by Shopify, including Apple Pay. Nothing digital is sold, and no digital content or
functionality inside the app is unlocked by a purchase.

Health data is never used to price, target or advertise anything, and is never shared with
the print lab or with Shopify. What is sent to fulfil an order is the finished image the
user composed plus the shipping details they entered at checkout.

STRAVA (OPTIONAL)
Strava is an optional enhancement and is NOT required for review — it can be skipped
entirely. When connected, it only adds metadata (titles, gear, race flags) to activities
that already exist in Apple Health; it never creates duplicates.

Questions: software@nwagtech.com
```

---

## App Privacy ("nutrition labels") — **must be changed**

The v1.0 answers said Etch collects nothing. That was true of an app that only drew a map.
It is **not** true now: ordering a print uploads the composed artwork to our fulfilment
worker, and Shopify's checkout takes the customer's name, email address, shipping address
and payment details.

Recommended answers:

- **Do you or your third-party partners collect data from this app?** → **Yes.**
- **Contact Info** — Name, Email Address, Physical Address → collected, **linked** to the
  user, used for **App Functionality** (fulfilling and shipping an order). Not used for
  tracking.
- **Purchases** — Purchase History → collected, linked, **App Functionality**.
- **User Content** — Photos or Videos, Other User Content → collected, linked,
  **App Functionality**. This is the artwork the customer composes and orders; it may
  include their own photographs and the shape of a route.
- **Health & Fitness** → **not collected.** Health data stays on the device. It is read to
  draw maps and compose artwork, and the composed *image* is what is uploaded, never the
  underlying workout records.
- **Tracking (App Tracking Transparency):** No tracking. No IDFA, no cross-app or
  cross-site tracking.

> The distinction that matters if this is ever questioned: Etch does not upload a workout.
> It uploads a picture the customer made and asked us to print. Everything in the Health
> &amp; Fitness category stays on the phone.

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
  authorization) Strava. All third-party content is accessed with the user's authorization.
- **Printed artwork is drawn from OpenStreetMap**, not Apple Maps: Apple licenses its map
  data for display inside an app, not for merchandise. `EtchCartography` renders the print
  from an OpenStreetMap basemap, and ODbL attribution — "© OpenStreetMap contributors" —
  travels with anything published or sold. A piece that could only be drawn from an Apple
  snapshot is marked display-only in the shop and cannot be ordered.

---

## Still needed before submitting

- [ ] **App icon** — the 1024×1024 is the new grotesk mark on Etch Ink; confirm it renders
      correctly under Apple's mask.
- [ ] **Screenshots** — 6.9" iPhone (required) and 6.5"/6.7" as needed. Capture from a
      device with real activities, and include at least one Studio product and one print
      mockup — half the app is invisible in a screenshot set that is all map.
- [ ] Enable **GitHub Pages** so the Privacy Policy + Support URLs resolve (Settings →
      Pages → `main` / `/docs`).
