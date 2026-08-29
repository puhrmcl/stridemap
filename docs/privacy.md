# Etch — Privacy Policy

_Last updated: August 29, 2026_

**The short version.** Your activities stay on your iPhone. There is no account, no sign-in,
and nothing syncs. We never sell your data or use it for advertising.

Two things do leave your device, and we would rather say so plainly than bury them:

1. **If you order a print,** the artwork you composed is uploaded so a print lab can make
   it, and checkout takes the name and address needed to post it to you.
2. **A few features ask the outside world a question about a place** — naming the city a
   route ran through, finding the elevation under it, looking up the weather on the day.
   Those requests carry coordinates. They never carry your name, and they are listed in
   full in section 3.

This Privacy Policy explains how the Etch app ("Etch", "the app", "we", "us") handles your
information. Etch maps the runs, rides, hikes and walks in your Apple Health history, and
lets you turn them into printed artwork. By using Etch you agree to this policy.

---

## 1. What the app reads on your device

### Apple Health (HealthKit)

With your permission, Etch reads workouts and their associated data from Apple Health so it
can draw them on a map. This may include:

- Running, cycling, hiking and walking workouts, with their dates and times
- Workout routes (GPS coordinates)
- Distance and duration
- Elevation gain
- Heart rate
- Active energy (calories)
- Cadence, when available

This access is **read-only** — Etch never writes to Apple Health. What it reads is stored
only on your device.

### Location

Etch may show your current position on the map to give your activities context. Your live
location is used for on-screen display and is not recorded or transmitted by the app.

### Photos

If you attach photographs to an activity or to a piece of artwork, Etch reads them from
your photo library with your permission. They stay on your device unless you order a print
that contains them — see section 4.

### Imported files

You can import GPX, TCX and FIT files, or a Nike activity export. These are read on your
device and turned into activities stored there. Nothing about the import is transmitted.

---

## 2. Strava (optional)

Connecting Strava is entirely optional and the app is fully usable without it. If you
connect it, Etch uses Strava's official OAuth sign-in and requests **read-only** access to
your activities, in order to add detail Apple Health does not carry — titles, gear,
descriptions, race identification.

The OAuth code exchange passes through a small service we operate, because Strava requires
a client secret that must not ship inside an app. That service handles the exchange and
does not store your activities. Your Strava access token is then kept in the iOS Keychain
on your device, and the enrichment data is cached locally alongside your other activities.

You can disconnect Strava at any time in Settings, which removes the stored token. You can
also revoke Etch's access from your Strava account settings.

---

## 3. What leaves your device, and when

This is the complete list. Everything not on it stays on your phone.

| When | What is sent | Where | Why |
|---|---|---|---|
| You look at the map | The area you are viewing | Apple (MapKit) | To draw the map |
| An activity is imported | The coordinates of its start point | Apple (CLGeocoder) | To name the city, state and country it happened in |
| You open the Landmarks overlay | The map region you are viewing | Apple (MKLocalSearch) | To find parks and landmarks nearby |
| An activity has no recorded weather | Its coordinates and date | Apple (WeatherKit) | To fill in the weather on the day |
| You compose a contour or topographic piece | A grid of coordinates around the route | Open-Meteo | To find the elevation of the land, so the contour lines can be drawn |
| You compose a printable map piece | The map tiles for that area | Our fulfilment service | To draw the map from OpenStreetMap rather than Apple's data, because Apple's may not be printed |
| The app starts | Nothing about you | Our fulfilment service | To read configuration (prices, whether a product is available) |
| You order a print | See section 4 | Our fulfilment service, Shopify, the print lab | To make and post the thing you bought |

None of these requests carry your name, your email address, an account identifier, or an
advertising identifier. Etch has no analytics and no crash reporting.

**Your workout records are never uploaded.** Not to us, not to anyone. The requests above
send a coordinate or a region — the sort of question any map app asks — and never the
underlying Health data.

---

## 4. Ordering a print

Etch Studio lets you compose artwork and order it as a physical object — a print, a framed
print, a book, a medal frame. This is the one part of the app that necessarily involves
other people, because someone has to make the thing and post it to you.

When you place an order:

- **The finished artwork is uploaded to our fulfilment service.** This is a single flattened
  image (or PDF, for the book) — the piece exactly as you composed it. It may contain a map
  of your route, statistics you chose to show, text you typed, and photographs you added.
  It does not contain your Health records, and no workout data travels with it.
- **Checkout is handled by Shopify**, including Apple Pay. Shopify takes your name, email
  address, shipping address and payment details. We never see your card number; Shopify and
  its payment processors handle payment.
- **Your artwork and shipping address are passed to the print lab** (Prodigi) so they can
  print the piece and post it to you. They receive what is needed to make and deliver the
  order, and nothing else.
- **A record of the order is kept** — the order number, its status, and a reference to the
  artwork — so the app can show you where your parcel is, and so we can help if something
  goes wrong.

**Retention.** Artwork you composed but never ordered is deleted from our service within
seven days. Artwork attached to a placed order is kept while the order is being made and
delivered, and afterwards for as long as we may need it to reprint a damaged item or answer
a question about it. You can ask us to delete an order record at any time (section 8).

**We do not use anything about your order for advertising**, and we do not sell it.

---

## 5. How your information is used

Everything the app reads is used for one purpose: to show you your activities and to let you
make something out of them. Processing happens on your iPhone.

**Our commitments regarding Health data.**

- We do **not** use Apple Health data for advertising or marketing.
- We do **not** share Apple Health data with any third party — including Shopify and the
  print lab.
- We do **not** sell your data.
- We do **not** store Apple Health data in iCloud or on any server.
- We do **not** use it for anything other than showing you your activities and composing
  the artwork you ask for.

---

## 6. Where your data is stored

Your activities are stored on your device using Apple's on-device storage (SwiftData).
Authentication tokens are kept in the iOS Keychain. There is no account and nothing syncs
between devices — if you install Etch on a second phone, it builds its map again from that
phone's Apple Health.

The only data we hold on a server is what section 4 describes: the artwork for an order, and
the order record itself.

---

## 7. Third-party services

- **Apple** — HealthKit, MapKit, CLGeocoder, MKLocalSearch and WeatherKit all run through
  Apple and are governed by [Apple's Privacy Policy](https://www.apple.com/legal/privacy/).
- **Open-Meteo** — receives coordinates to look up ground elevation for contour artwork.
  See [Open-Meteo's terms](https://open-meteo.com/en/terms).
- **OpenStreetMap** — the basemap printed artwork is drawn from. Map data © OpenStreetMap
  contributors, licensed [ODbL](https://www.openstreetmap.org/copyright). Tiles are served
  by us; OpenStreetMap receives nothing about you.
- **Shopify** — handles checkout and payment for orders.
  [Shopify's Privacy Policy](https://www.shopify.com/legal/privacy).
- **Prodigi** — the print lab that manufactures and ships orders.
  [Prodigi's Privacy Policy](https://www.prodigi.com/privacy/).
- **Strava** (only if you connect it) — [Strava's Privacy
  Policy](https://www.strava.com/legal/privacy). Etch requests read-only access and never
  posts to or modifies your Strava account.

---

## 8. Your choices and controls

- **Health access.** Review or revoke Etch's access at any time in _Settings → Privacy &
  Security → Health → Etch_, or in the Health app.
- **Location.** Manage in _Settings → Privacy & Security → Location Services_.
- **Photos.** Manage in _Settings → Privacy & Security → Photos_.
- **Strava.** Disconnect in the app's Settings, and revoke Etch's access from your Strava
  account settings.
- **Delete your data on the device.** Use _Delete Cache_ in the app's Settings to remove all
  stored activities. Deleting the app removes all of its local data.
- **Delete an order record.** Email **software@nwagtech.com** with your order number and we
  will delete the artwork and the order record, subject to any records we are required to
  keep for tax or accounting purposes.

---

## 9. Data security

Data on your device is protected by iOS, and credentials are kept in the iOS Keychain.
Artwork uploaded for an order travels over HTTPS, is stored with a random unguessable
identifier, and is checksummed on arrival so a corrupted file can never reach the press.
Payment details never touch our systems.

No system is perfectly secure, but keeping your activities on-device — rather than syncing
them to an account we would then have to defend — removes entire categories of risk.

---

## 10. Children's privacy

Etch is not directed to children under 13, and we do not knowingly collect personal
information from children.

---

## 11. Changes to this policy

We may update this Privacy Policy from time to time. When we do, we will revise the "Last
updated" date above. Material changes will be reflected in an updated version of the app or
on this page.

---

## 12. Contact

Questions about this Privacy Policy: **software@nwagtech.com**

Northwest Ag Technologies, L.L.C.
