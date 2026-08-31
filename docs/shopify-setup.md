# Shopify setup — the outstanding work

Everything Etch needs from Shopify before an order can be placed, in the order it has to
happen. Every value here is quoted from the code that will read it, with the file named, so
each one can be checked rather than trusted.

Nothing in here needs a Mac. It is all Shopify admin, one Cloudflare CLI session, and two
fields in Xcode Cloud.

> **Never paste a token into a chat or a commit.** Tokens go straight from the page that
> issues them into the field that consumes them.

---

## How the app finds a product (read this first)

This one paragraph explains why the SKUs below have to be exact.

`ShopifyStorefront.variant(sku:productHandle:)` runs one GraphQL query: fetch
`product(handle:)`, read `variants(first: 50)`, and pick the node whose **`sku` matches the
requested string exactly**. Then it checks `availableForSale` and throws `.unavailable` if
that is false.

Three consequences:

1. **The handle must match exactly.** Shopify derives the handle from the title, so a product
   called "Fine Art Print" gets `fine-art-print` — but a later title edit can leave the handle
   behind. Set it explicitly in **Search engine listing → Edit → URL handle**.
2. **The SKU must match exactly** — case, hyphens, all of it. `GLOBAL-HGE-12X18` is not
   `GLOBAL-HGE-12x18`.
3. **`availableForSale` must be true**, or the order fails at the last step with "unavailable".
   Since Prodigi prints to order and Shopify holds no stock, either untick *Track quantity* or
   tick *Continue selling when out of stock* on every variant. This is the single most common
   way this setup fails silently.

A product is also invisible to the Storefront API until it is **published to the sales channel
the token belongs to**. See Step 3.

---

## Step 1 — Storefront API access token

The app talks to Shopify as an unauthenticated buyer. The token is public by design — it can
read products and create carts, nothing else.

1. Shopify admin → **Settings → Apps and sales channels → Develop apps**.
2. **Create an app**, name it `Etch iOS`.
3. **Configuration → Storefront API** → Configure. Tick:
   - `unauthenticated_read_product_listings`
   - `unauthenticated_write_checkouts`
   - `unauthenticated_read_checkouts`
4. **Save**, then **API credentials → Install app**.
5. Copy the **Storefront API access token**. It goes into Xcode Cloud in Step 7 — not into a
   file, not into a message.

**Check the API version.** `CommerceConfig.storefrontAPIVersion` is `"2026-07"`
(`Etch/Config/CommerceConfig.swift`). The webhook in Step 5 must be on the same version. If
Shopify no longer offers `2026-07`, tell me and I will move the constant rather than you
guessing a version that the query may not parse under.

The shop domain is already set: `zn1ddh-it.myshopify.com`. `byetch.com` is the customer-facing
alias; the API is addressed by the permanent `myshopify.com` name, so leave that constant
alone.

---

## Step 2 — Create the products

Six products. Roughly twenty variants. Every one of these is a **physical product** — tick
*This is a physical product* so Shopify collects an address and applies shipping.

Prices below are what the app currently displays. **Shopify is the source of truth at
checkout** — if the two disagree, the customer pays the Shopify price and the app's number was
a lie on the tile. Keep them in step.

### 1. Fine-Art Print — handle `fine-art-print`

Carries the map posters, gallery posters, Anthology and Lithograph. The busiest product in the
range.

| Variant SKU | Price |
|---|---|
| `GLOBAL-HGE-12X18` | $59 |
| `GLOBAL-HGE-16X24` | $79 |
| `GLOBAL-HGE-24X36` | $109 |

Suggested option name: **Size**, values `12 × 18″`, `16 × 24″`, `24 × 36″`.

### 2. Framed Print — handle `framed-print`

Eight variants: each size in four frame colours. The SKU is the Prodigi SKU **plus the finish
suffix**, which is how `PrintSize.shopifySKU(finish:)` builds it.

| Variant SKU | Price |
|---|---|
| `GLOBAL-CFP-12X18-NATURAL` | $139 |
| `GLOBAL-CFP-12X18-BLACK` | $139 |
| `GLOBAL-CFP-12X18-WHITE` | $139 |
| `GLOBAL-CFP-12X18-DARKGREY` | $139 |
| `GLOBAL-CFP-16X24-NATURAL` | $179 |
| `GLOBAL-CFP-16X24-BLACK` | $179 |
| `GLOBAL-CFP-16X24-WHITE` | $179 |
| `GLOBAL-CFP-16X24-DARKGREY` | $179 |

Two options: **Size** (`12 × 18″`, `16 × 24″`) × **Frame** (`Natural`, `Black`, `White`,
`Dark Grey`). Note `DARKGREY` has **no space and no hyphen** in the SKU.

### 3. Print with Hanger — handle `print-with-hanger`

| Variant SKU | Price |
|---|---|
| `POSTER-HANGER-60-24X36-PORT-BLACK` | $129 |
| `POSTER-HANGER-60-24X36-PORT-NATURAL` | $129 |
| `POSTER-HANGER-60-24X36-PORT-WHITE` | $129 |

One size so far — the 12×18 and 16×24 hangers were not on Prodigi's product page and have to be
read off it before they can be listed. Option: **Wood** (`Black`, `Natural`, `White`).

The hanger is the cheapest finish in the range and needs no new artwork: its 24×36 print area is
7200 × 10800, identical to `GLOBAL-HGE-24X36` and `GLOBAL-CFP-24X36`. The one geometry rule it
does carry is that the wooden battens cover 15mm at the top and bottom, so the composition keeps
those bands clear — handled in the renderer, nothing to configure here.

### 4. Year in Review / Collections — handle `year-book`

| Variant SKU | Price |
|---|---|
| `BOOK-FE-A4-L-LF-G` | $119 |

**One product serves both books.** Year in Review and Collections are the same physical object
— same Prodigi SKU, same price, same production file — bound around a different subject. The
handle stayed `year-book` through the rename because it is a join key, not copy
(`Etch/Book/BookCatalog.swift`). If you would rather they appeared as separate lines on a
receipt, say so and I will split the handle; it is a code change, not a Shopify one.

### 5. Photo Wall — handle `photo-wall`

| Variant SKU | Price |
|---|---|
| `GLOBAL-MPF-12X12` | $199 |
| `GLOBAL-MPF-20X30` | $199 |
| `GLOBAL-MPF-24X36` | $199 |

One price across sizes today: `photoWallCents` prices the product rather than the size, because
the three frames cost within a few dollars of each other wholesale and a three-rung ladder on a
$199 object is a decision the buyer does not need to make.

### 6. Medal Frame — handle `medal-frame`

| Variant SKU | Price |
|---|---|
| `MEDAL-FRA-CLA-MOUNT-30X40` | $249 |

Frame and mount colours travel as **line-item attributes**, not variants, so there is one
variant here — eight frame colours and two mount colours would otherwise be sixteen variants of
an identical object.

---

## Step 3 — Publish to the right sales channel

Storefront API tokens only see products published to their channel. Miss this and every order
fails with "variant not found" while the products look perfectly fine in admin.

For each of the six products: **Product page → Publishing → Manage** → tick the channel the
`Etch iOS` app created (usually named after the app, or **Headless**).

Fastest path: select all six in the product list → **Bulk actions → Add available channel**.

---

## Step 4 — Shipping

Checkout collects the address; Shopify quotes the rate.

1. **Settings → Shipping and delivery → General shipping rates**.
2. Add the zones you will actually ship to. Prodigi produces in the **US, UK and EU** for most
   of the range — but **the Medal Frame is made only in the UK**, so a US buyer's landed cost
   carries transatlantic shipping. That is documented in `MedalFrameCatalog` and is why its
   margin is the thinnest in the catalogue.
3. Add a flat rate per zone, or free shipping above a threshold. Whatever you choose, the app
   never quotes shipping — it says "Printed to order and shipped to your door" and lets
   checkout do the arithmetic.

Taxes: **Settings → Taxes and duties**. US sales tax needs nexus configured; if you are not
registered anywhere yet, leave it and revisit before volume.

---

## Step 5 — The `orders/paid` webhook

This is the wire that turns a payment into a print. Without it, money moves and nothing is
manufactured.

1. **Settings → Notifications → Webhooks → Create webhook**.
2. **Event:** `Order payment` (`orders/paid`).
3. **Format:** JSON.
4. **URL:** `https://etch-fulfilment.clintpuhrmann.workers.dev/webhooks/shopify`
5. **API version:** `2026-07` — the same version as Step 1.
6. Save. Shopify then shows a **signing secret** once. Copy it; it goes into Step 6.

The worker verifies the HMAC on every request (`fulfilment/src/index.ts`), so a webhook without
the matching secret is rejected — which looks exactly like the webhook not firing.

---

## Step 6 — The webhook secret (no terminal needed)

**This step was wrong in the first version of this document.** It told you to run
`wrangler secret put` locally, which contradicts the premise of this whole project — you have no
machine to run it on. `.github/workflows/deploy-fulfilment.yml` already does it: it provisions
the R2 bucket and the D1 database, deploys the worker, and pushes every secret from repository
secrets. There is nothing to install.

The worker is already deployed and holding `UPLOAD_TOKEN` and `PRODIGI_API_KEY`. The one secret
it does *not* have is Shopify's, because the store did not exist when it was last deployed — the
workflow writes the literal `not-configured-yet` in its place, so webhook verification currently
rejects everything.

1. GitHub → repository **Settings → Secrets and variables → Actions → New repository secret**.
2. Name `SHOPIFY_WEBHOOK_SECRET`, value the signing secret Shopify showed you in Step 5.
3. **Actions → Deploy fulfilment worker → Run workflow.** That pushes it to the worker.

Until this is done, a paid order produces nothing: Shopify sends the webhook, the worker rejects
the signature, and no Prodigi order is created.

## Step 7 — Xcode Cloud environment variables

The app ships with two empty token constants
(`Etch/Config/CommerceSecrets.generated.swift`); `ci_scripts/ci_post_clone.sh` overwrites that
file at build time from the environment. Until these are set, `CommerceConfig.isConfigured` is
false and **every order and Add to Bag button is hidden** — which is exactly why CI screenshots
of the Studio editors show no bag button.

App Store Connect → Xcode Cloud → your workflow → **Environment Variables**:

| Name | Value | Secret |
|---|---|---|
| `ETCH_STOREFRONT_TOKEN` | the Storefront token from Step 1 | ✅ |
| `ETCH_UPLOAD_TOKEN` | the same string you gave `wrangler secret put UPLOAD_TOKEN` | ✅ |

Tick **Secret** on both. Then start a build — the values are read at clone time, so an
in-flight build will not pick them up.

---

## Step 8 — Verify, in this order

Each step fails differently, so do them in sequence and stop at the first failure.

1. **Products are visible to the token.** In the app: open Studio → any product → the order
   button appears at all. If it does not, Step 7 is not done.
2. **A variant resolves.** Tap **Add to Bag** on a Fine-Art Print. "variant not found" means
   the SKU or handle is wrong (Step 2); "unavailable" means `availableForSale` is false
   (untick *Track quantity*).
3. **The upload lands.** The bag line appears with its title and price. If it fails at
   "Preparing your order…", `UPLOAD_TOKEN` does not match between Steps 6 and 7.
4. **Checkout opens** and Apple Pay or a card is offered.
5. **Place one real order**, cheapest size. Then check:
   - Shopify shows the order paid.
   - The worker's ledger has a row: `GET /orders/by-shopify/<id>`.
   - Prodigi sandbox shows a submitted order.
6. **Only then** flip `PRODIGI_BASE` in `fulfilment/wrangler.toml` from
   `https://api.sandbox.prodigi.com` to `https://api.prodigi.com`, swap in the live
   `PRODIGI_API_KEY`, and redeploy. Until that flip, nothing is physically manufactured — which
   makes step 5 safe to run as many times as you like.

---

## Settled, and what it means for Step 2

Both of these were open when this document was written. They are decided now, and the served
configuration (`fulfilment/config/app.json`, v2) reflects it.

### The Medal Frame and the Photo Wall are being sold

They gate on their price being set:

```swift
static var isAvailable: Bool { EtchConfig.current.prices.medalFrameCents != nil }
```

The served document previously set only `yearBookCents`, while the built-in fallback in
`Etch/Config/RemoteConfig.swift` also set the other two — so the products were hidden when the
document loaded and visible when the app fell back to its defaults. The same build behaved as two
different shops depending on connectivity.

`medalFrameCents` (24900) and `photoWallCents` (19900) are now in the served document, matching
the fallback. Both products are listed in every state. **Create products 5 and 6.**

### The hanger is listed

`PosterHangerCatalog.isAvailable` resolves true — the banded print writer removed the size ceiling
that used to gate it — so "Print with Hanger" already appears in the shop's format picker.
`POSTER-HANGER-60-24X36-PORT` is priced at 12900 in the served document. **Create product 3**, or
that format fails at checkout.

### One rule worth carrying

Deleting a price key from the served document removes a product from the app. It reads as a
pricing edit and behaves as a delisting. The deploy workflow now range-checks all three
non-per-SKU prices, so a typo fails the deploy rather than reaching a device — but a *missing*
key is a valid document, and the shop quietly shrinks.

## What is not on this list

- **App Store Connect App Privacy answers.** Unrelated to Shopify, still the hard blocker on
  submission — see `docs/app-store-metadata.md`.
- **Prodigi production key and `PRODIGI_BASE`.** Deliberately last: see Step 8.6.
