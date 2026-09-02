# Etch — everything left to do

Ordered so each step unblocks the next, with what is already done recorded so it does not get
done twice. Nothing here needs a Mac.

Status was re-read from the workflow run history on **2026-09-01**, not from memory — where a
thing is marked done, a green run says so. Nothing in the deploy history has moved since
2026-08-31: the last `Deploy app config` is still the 08-31 success, and `Apple Pay certificate`
is still three failures from 08-27.

The two goals have different critical paths, and only one of them is genuinely blocking:

- **Commerce live** — stages 1 → 2 → 3 → 4, then 9. Stage 1 (building the store) is the long
  pole; everything else in that chain is minutes of work that cannot start until it exists.
- **App Store live** — stages 6, 7, 8 and the metadata. Stage 6 is the hard blocker.
- **Apple Pay** (stage 5) blocks neither. Checkout works with a card without it.

Realistically the store has to be live before you submit, because review will exercise the
ordering flow — but that is a sequencing fact, not a dependency in the code.

---

## Already done

| | Evidence |
|---|---|
| Fulfilment worker deployed to Cloudflare; R2 bucket and D1 database provisioned | `Deploy fulfilment worker` green, 2026-08-29 |
| Repo secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `ETCH_UPLOAD_TOKEN`, `PRODIGI_API_KEY` | the deploys above could not have run without them |
| Prodigi SKUs verified against the live API | `Verify Prodigi SKUs` green, 2026-08-28 |
| Storefront theme pushed to Shopify — **unpublished** | `Deploy storefront` green, 2026-08-29 |
| App config v2 served — all six products priced and switched on | `Deploy app config` green, 2026-08-31 |

The worker is live, the catalogue is priced, the app knows what to sell. What is missing is the
store to sell it through, and the credentials that let the app reach it.

---

## 1 · Shopify — the store itself

**The long one.** Full detail in [`shopify-setup.md`](shopify-setup.md); this is the shape.

1. **Storefront API token** — Settings → Apps and sales channels → Develop apps → create
   `Etch iOS`, tick the three unauthenticated scopes, install, copy the token.
2. **Six products, ~20 variants** — exact SKUs in the setup doc. All physical products.
3. **Publish all six to the app's sales channel.** Skip this and every order fails with
   "variant not found" while the products look perfect in admin.
4. **Shipping zones.**
5. **`orders/paid` webhook** → `https://etch-fulfilment.clintpuhrmann.workers.dev/webhooks/shopify`,
   API version `2026-07`. Copy the signing secret it shows you once.

Three ways this fails silently, all covered in the setup doc: a handle Shopify kept from an older
title, `availableForSale` false because inventory tracking is on with zero stock, and products
not published to the token's channel.

## 2 · `SHOPIFY_WEBHOOK_SECRET` — the wire that makes orders real

The worker holds the literal string `not-configured-yet` in place of Shopify's secret, because
the store did not exist when it was last deployed. Every webhook currently fails signature
verification.

1. **Settings → Secrets and variables → Actions → New repository secret**, name
   `SHOPIFY_WEBHOOK_SECRET`, value from step 1.5.
2. **Actions → Deploy fulfilment worker → Run workflow.**

Until this is done a paid order produces nothing: Shopify sends, the worker rejects, no print is
made. No terminal needed — the workflow does the whole thing.

## 3 · Xcode Cloud — the two tokens the app ships with

`Etch/Config/CommerceSecrets.generated.swift` ships empty and `ci_scripts/ci_post_clone.sh`
fills it at build time. While they are empty, `CommerceConfig.isConfigured` is false and **every
order and Add to Bag button is hidden** — which is why CI screenshots of the Studio editors show
no bag button.

App Store Connect → Xcode Cloud → your workflow → **Environment Variables**:

| Name | Value | Secret |
|---|---|---|
| `ETCH_STOREFRONT_TOKEN` | the Storefront token from step 1.1 | ✅ |
| `ETCH_UPLOAD_TOKEN` | the same value as the repo secret of that name | ✅ |

Tick **Secret** on both, then start a build — values are read at clone time, so an in-flight
build will not pick them up.

## 4 · Publish the storefront theme

The theme is sitting in Shopify as an unpublished theme named **Etch**. Online Store → Themes →
preview it → **Publish**. Deliberately manual: the deploy has never touched your live storefront.

## 5 · Apple Pay — currently failing

`Apple Pay certificate` has failed three times, all at the same step: **Mint an access token**.
`SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` are missing or the app lacks its scopes.

1. Shopify **Dev Dashboard** → your app → API credentials. Copy the client id and secret.
2. Add both as repository secrets under those names.
3. The app needs `write_mobile_payments` and `read_mobile_payments` — Shopify grants these on
   request, so if minting still fails after the secrets are set, that approval is the reason.
4. Edit `.github/apple-pay-request.txt` with `create`, commit. The run produces a CSR artifact.
5. Upload that CSR to Apple's developer portal, download `apple_pay.cer`.
6. Edit the request file with `upload` and the certificate, commit.

Apple Pay is optional for launch — checkout still works with a card — so this can trail the rest.

## 6 · App Store Connect — the actual blocker

**This is the one that stops submission.** The v1.0 App Privacy answers say Etch collects
nothing. That was true of an app that only drew a map. It is false now: ordering a print uploads
the artwork and checkout takes a name, an email and a shipping address.

App Store Connect → your app → **App Privacy → Edit**:

- **Do you or your third-party partners collect data from this app?** → **Yes**
- **Contact Info** — Name, Email Address, Physical Address → collected, **linked**, used for
  **App Functionality**. Not used for tracking.
- **Purchases** — Purchase History → collected, linked, **App Functionality**.
- **User Content** — Photos or Videos, Other User Content → collected, linked,
  **App Functionality**.
- **Health & Fitness** → **not collected.** Health data never leaves the device; the composed
  *image* is what is uploaded.
- **Tracking** → **No.** No IDFA, no cross-app tracking.

The distinction, if it is ever questioned: Etch does not upload a workout. It uploads a picture
the customer made and asked us to print.

Also on that screen, from [`app-store-metadata.md`](app-store-metadata.md): the new **name**,
**subtitle**, **description**, **keywords** and **What's New** are all written and ready to paste.

## 7 · GitHub Pages — the two required URLs

Privacy Policy and Support URLs are mandatory and both currently 404.

Settings → **Pages** → Source: deploy from branch → **main** / **`/docs`** → Save.

Then confirm `https://puhrmcl.github.io/etch/privacy.html` resolves.

## 8 · Screenshots

6.9″ iPhone required. Capture from a device with real activities, and **include at least one
Studio product and one print mockup** — half the app is invisible in a screenshot set that is all
map.

Worth doing after step 3, so the bag and order buttons are actually visible to photograph.

## 9 · Prodigi — flip to production, last

Only after a real end-to-end order has gone through on sandbox:

1. `fulfilment/wrangler.toml` → `PRODIGI_BASE` from `https://api.sandbox.prodigi.com` to
   `https://api.prodigi.com`.
2. Replace the `PRODIGI_API_KEY` repo secret with the live key.
3. **Actions → Deploy fulfilment worker → Run workflow.**

Until this flip nothing is physically manufactured, which makes every test order before it free
and safe to repeat.

---

## Verify, in this order

Each fails differently, so stop at the first failure rather than changing two things at once.

1. **Order button appears at all** in Studio → step 3 is done.
2. **Add to Bag on a Fine-Art Print** — "variant not found" means a wrong SKU or handle;
   "unavailable" means `availableForSale` is false.
3. **The line lands in the bag** with title and price → the upload token matches.
4. **Checkout opens.**
5. **Place one real order** on the cheapest size, then check: Shopify shows it paid, the worker's
   ledger has a row (`GET /orders/by-shopify/<id>`), Prodigi sandbox shows it submitted.
6. **Then and only then**, step 9.

---

## 10 · The basemap — what lets the *map* posters be sold

Not a launch blocker (contour, paper and photo pieces sell without it) but it is the signature
product. Apple licenses its maps for display, not merchandise, so every map-panel edition
refuses to print until Etch's own basemap is live. The pipeline exists end to end; one object
is missing from the bucket.

1. Edit `.github/basemap-request.txt` (the Arizona default is fine to start) and commit — the
   **Build basemap** workflow extracts the region from the public Protomaps build and uploads it
   through the fulfilment worker with the `ETCH_UPLOAD_TOKEN` the repo already holds. No
   credentials to create anywhere.
2. When green: set `"basemapReady": true` in `fulfilment/config/app.json`, bump its version,
   commit. Every install flips to Etch cartography on its next config refresh; map editions
   become printable. Flip it back the same way if tiles ever misbehave.
3. Before the first live map-print sale, confirm the OpenStreetMap attribution line appears on
   the printed sheet (ODbL requires it).

Full reasoning and the widen-the-region plan: [`studio-redesign.md`](studio-redesign.md).

## Device verification backlog (does not block the store, does block shipping with confidence)

Everything below shipped since the checklist was first written and is **green in CI but unseen
on a real device**, because the preview harness has no Apple Health, no photo library, and
cannot tap. Worth walking once on the b514 TestFlight build before submission — a first
release is the worst place to find out one of them regressed.

| Build | What to check |
|---|---|
| b506 | **Syncing.** Activities that upload late now import. Settings should read `Health: N new workouts read, N imported`. Anything previously missing should appear. |
| b507 | The **Gallery** segment on the Timeline, the **filmstrip** in the photo viewer, and the drawn **tab glyphs**. |
| b510 | **Recover Missing Maps** — should show progress, be stoppable, and the badge should fall. |
| b511 | **Humphreys Peak files under Hikes**, and the Longest Run record returns to a real run. |
| b512 | **Tapping a city or state** in Achievements narrows the app; the photo wall opens on that place. |
| b513–514 | **Speed** — scrolling the Timeline and switching tabs. And the opposite risk: any count or list that now looks *stale* after an edit is a missing `updatedAt`, and a one-line fix. |

## Decisions still open (none block launch)

| | |
|---|---|
| **Colorado 14ers dataset** | `Resources/peak-lists.json` holds 9 of 58. The poster is gated off until it is complete. Give me a list, allow `14ers.com` through the egress proxy, or tell me to fill it from knowledge and flag every unverified row. |
| **Wordmark size** | The asset carries 31% transparent padding, so `height: 25` draws 17.2pt of letterform. Trim it and the constant means what it says — but it touches five call sites at once. |
| **"Year in Review" names two things** | The free animated recap, and the $119 book. |
| **"Collections" names two things** | The book product, and the curated-sets shelf on the same Studio page. |
| **Humphreys Peak** | The route is bundled. To put *your* hike in the library it needs a date and a moving time — Studio → Add from the library. |
| **Cities and States wording** | Fixed in code, unverifiable by CI: the preview harness cannot reach screens that are pushed from Achievements. |
