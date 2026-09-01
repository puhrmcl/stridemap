# Etch — launch status and outstanding work

*Context brief for handing to another AI assistant. Companion to [`app-summary.md`](app-summary.md),
which describes what the app is. Written 2026-09-01 against build b514; status re-read from the
GitHub Actions run history, not from memory.*

## The situation in one paragraph

Etch is a finished iOS app on TestFlight with a print shop built into it. The code is done. What
is missing is the **commercial plumbing around it** — a Shopify store that does not exist yet, the
credentials that let the app reach it, and a set of App Store Connect answers that are now wrong.
There are two independent tracks to being live, and only one hard blocker in each.

## Constraints that decide what advice is useful

- **The author has no Mac.** Everything ships through Xcode Cloud (build → TestFlight) and GitHub
  Actions (everything else). Advice that requires a local Xcode, a simulator, Instruments,
  `wrangler` from a terminal, or a shell on macOS **cannot be acted on**.
- Secrets live in three places and never in chat: **GitHub repository secrets** (worker deploys),
  **Xcode Cloud environment variables** (values baked into the app at build time), and **Shopify
  admin**. Every deploy is a workflow, not a command.
- Cloudflare Workers are deployed by GitHub Actions using a stored API token. Editing the relevant
  file and committing is what triggers a deploy.

## Already done — with evidence

| | Evidence |
|---|---|
| Fulfilment worker deployed to Cloudflare; R2 bucket and D1 database provisioned | `Deploy fulfilment worker` green, 2026-08-29 |
| Repo secrets `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `ETCH_UPLOAD_TOKEN`, `PRODIGI_API_KEY` | the deploys could not have run without them |
| Prodigi SKUs verified against the live API | `Verify Prodigi SKUs` green, 2026-08-28 |
| Storefront theme pushed to Shopify — **unpublished** | `Deploy storefront` green, 2026-08-29 |
| Remote app config v2 served — all products priced and switched on | `Deploy app config` green, 2026-08-31 |
| App itself feature-complete on TestFlight | build b514 |

So: the worker is live, the catalogue is priced, the app knows what to sell. **What is missing is
the store to sell it through, and the credentials that let the app reach it.**

---

## Track A — Commerce live

Strictly sequential. Steps 2–4 are minutes of work each and none can start until step 1 exists.

### A1 · Build the Shopify store — the long pole

The only task here measured in days rather than minutes.

1. **Storefront API token** — Settings → Apps and sales channels → Develop apps → create an app,
   tick the three unauthenticated scopes, install, copy the token.
2. **Six products, roughly twenty variants**, all physical, with exact SKUs that must match what
   the app asks for.
3. **Publish all six to the app's sales channel.** Skipping this is the classic failure: the
   products look perfect in admin and every order fails with "variant not found".
4. **Shipping zones.**
5. **`orders/paid` webhook** pointing at the fulfilment worker's `/webhooks/shopify` endpoint, API
   version `2026-07`. Copy the signing secret — Shopify shows it once.

**Three ways this fails silently**, all worth checking before blaming the app:
- Shopify keeps a product *handle* from an earlier title, so the handle no longer matches the SKU.
- `availableForSale` is false because inventory tracking is on with zero stock.
- Products are not published to the token's sales channel.

### A2 · `SHOPIFY_WEBHOOK_SECRET`

The worker currently holds the literal string `not-configured-yet`, because the store did not
exist when it was last deployed. **Every webhook fails signature verification right now**, so a
paid order would produce nothing: Shopify sends, the worker rejects, no print is made.

Add it as a GitHub repository secret, then re-run the fulfilment deploy workflow. Two minutes.

### A3 · Two Xcode Cloud environment variables

`Etch/Config/CommerceSecrets.generated.swift` ships empty and a CI post-clone script fills it at
build time. While the values are empty, `CommerceConfig.isConfigured` is false and **every order
and Add to Bag button in the app is hidden.**

Set `ETCH_STOREFRONT_TOKEN` (from A1) and `ETCH_UPLOAD_TOKEN` (same value as the repo secret of
that name) as **Secret** environment variables on the Xcode Cloud workflow, then start a build.
Values are read at clone time, so an in-flight build will not pick them up.

### A4 · Publish the storefront theme

The theme sits in Shopify as an unpublished theme. Online Store → Themes → preview → Publish.
Deliberately manual — the deploy workflow has never touched the live storefront.

### A5 · Verify, then flip Prodigi to production

Each check fails differently, so stop at the first failure rather than changing two things at
once. **Nothing is physically manufactured until the last step**, which makes every test order
before it free and safe to repeat.

1. An order button appears in Studio at all → A3 took effect.
2. Add to Bag on a print succeeds. *"variant not found"* → wrong SKU or handle. *"unavailable"* →
   `availableForSale` false.
3. The line lands in the bag with title and price → the upload token matches on both sides.
4. Checkout opens and offers a card.
5. Place one real order on the cheapest size. Confirm all three: Shopify shows it paid, the
   worker's ledger has a row, Prodigi **sandbox** shows it submitted.
6. Only then: replace `PRODIGI_API_KEY` with the live key, then change `PRODIGI_BASE` from
   `api.sandbox.prodigi.com` to `api.prodigi.com` and commit. In that order, so the live key is in
   place before the base URL points at it.

---

## Track B — App Store live

Independent of Track A in the code. In practice the store should be live first, because review
will exercise the ordering flow — that is a sequencing fact, not a dependency.

### B1 · App Privacy answers — **the hard blocker**

The v1.0 answers say Etch collects nothing. That was true of an app that only drew a map. It is
false now: ordering a print uploads the artwork, and checkout takes a name, an email and a
shipping address.

Required answers:

- **Collect data?** Yes.
- **Contact Info** — Name, Email Address, Physical Address → collected, linked, **App
  Functionality**. Not used for tracking.
- **Purchases** — Purchase History → collected, linked, App Functionality.
- **User Content** — Photos or Videos, Other User Content → collected, linked, App Functionality.
- **Health & Fitness** → **not collected.** Health data never leaves the device.
- **Tracking** → **No.** No IDFA, no cross-app tracking.

The distinction if review questions it: *Etch does not upload a workout. It uploads a picture the
customer made and asked us to print.*

### B2 · GitHub Pages

Privacy Policy and Support URLs are mandatory for submission and both currently 404. Repo Settings
→ Pages → deploy from branch → `main` / `/docs`. The pages already exist in the repo; they are
simply not being served.

### B3 · Screenshots

6.9″ iPhone, captured from a device with real activities. **Include at least one Studio product
and one print mockup** — half the app is invisible in a screenshot set that is all map, and the
prints are the half that makes money. Do this *after* A3, or the order buttons will not be there
to photograph.

### B4 · Listing metadata

Name, subtitle, description, keywords and What's New are written and ready to paste from
`docs/app-store-metadata.md`. The live listing still describes a running map, with no mention of
the shop.

---

## Track C — Apple Pay (blocks nothing)

Checkout works with a card without it, so this can trail the launch entirely.

The `Apple Pay certificate` workflow has failed three times, always at the same step: **minting an
access token**. That means `SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET` are missing as repo
secrets, or the Shopify app lacks the `write_mobile_payments` / `read_mobile_payments` scopes,
which Shopify grants on request.

Once the secrets are in place the flow is: trigger the workflow in `create` mode → it produces a
CSR → upload the CSR to Apple's developer portal → download the certificate → trigger the workflow
again in `upload` mode with it.

---

## Track D — Device verification (does not block, but should not be skipped)

Eight builds shipped in the last few days. All are green in CI and **none has been seen on a real
device**, because the screenshot harness has no Apple Health, no photo library, and cannot tap.

| Build | What it changed |
|---|---|
| b506 | Health import rewritten to an anchored query — activities that upload late now import at all |
| b507 | Gallery scope on the Timeline, filmstrip in the photo viewer, custom-drawn tab glyphs |
| b510 | "Recover Missing Maps" rebuilt: progress, cancel, honest counts |
| b511 | Library summits file as hikes, not runs — a hike was holding a running record |
| b512 | Location filters: canonical state matching, tap-a-city-to-filter, photo wall honours it |
| b513–b514 | Performance: derived data computed once per change rather than once per property access |

Worth one deliberate walkthrough on b514 before submission. The specific regression risk from the
last two builds is the opposite of the bug they fixed: if any count or list looks **stale** after
an edit, that is a mutation somewhere failing to bump a timestamp, and a one-line fix.

---

## Summary

| Track | Blocking? | Real cost |
|---|---|---|
| **A1** Build the Shopify store | Yes, for commerce | Days |
| **A2–A4** Secret, tokens, publish theme | Yes | ~15 minutes total, after A1 |
| **A5** Test order, then Prodigi live | Yes | An hour, mostly waiting |
| **B1** App Privacy answers | **Yes — hardest blocker for submission** | 10 minutes |
| **B2** GitHub Pages | Yes | 1 minute |
| **B3** Screenshots | Yes | An hour, after A3 |
| **B4** Metadata | Yes | 10 minutes, already written |
| **C** Apple Pay | No | Half a day including Apple's round-trip |
| **D** Device verification | No | An hour |

**Single highest-value next action: build the Shopify store.** It gates four of the five commerce
steps. The App Privacy answers are the only other true blocker and take ten minutes whenever they
get done.
