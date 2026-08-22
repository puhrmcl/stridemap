# Etch Studio — Print Backend Specification

Status: **proposed**. Nothing in this document is built yet. The iOS client contracts it
describes *are* built (`Etch/Studio/Fulfilment.swift`, `PrintGeometry.swift`, `PrintCatalog.swift`),
so this spec is the other half of an interface that already exists.

Fulfilment partner: **Prodigi**.

---

## 1. The one rule

> The device never renders the file that gets printed, and never holds a fulfilment credential.

The app sends a **recipe** — which activity, which poster configuration, which SKU. The backend
renders the print-ready artwork, uploads it, and creates the Prodigi order.

This is not fastidiousness. It buys three things that are expensive to retrofit:

1. **Reprints.** A damaged print must be reproducible months later, byte-identically. That is only
   possible if the server owns the render.
2. **Colour.** One renderer, one colour pipeline, one set of proofs. The Etch Blue route is the most
   sRGB→CMYK drift-prone colour in the product; it must be managed in exactly one place.
3. **Credentials.** An IPA is not a secret store. A Prodigi API key shipped in a build is a Prodigi
   API key published.

It also removes a hard ceiling: `StudioRenderer.maxLongEdgePixels` is 6,000 px, which is ~20″ at
300 DPI. A 24×36″ print needs 10,800 px and can *only* ever be produced server-side.

---

## 2. Flow

```
device                    backend                     prodigi
------                    -------                     -------
configure poster
  │
  ├─ POST /quote ────────► price + ship + tax
  │◄──────────────────────┘
  │
  ├─ Apple Pay ──────────► Stripe PaymentIntent
  │
  ├─ POST /orders ───────► validate recipe
  │                        render @300 DPI + bleed
  │                        upload to object storage
  │                        POST /v4.0/Orders ────────► order created
  │◄── order id ──────────┘
  │
  │                        ◄─── webhook: status ──────┘
  │◄── GET /orders/{id} ──┘
```

---

## 3. Endpoints

All authenticated as the Etch user. All money in minor units. All times RFC 3339 UTC.

### `POST /studio/quote`

Body: `PrintOrderRequest` minus payment. Returns `PrintQuote`
(`itemsCents`, `shippingCents`, `taxCents`, `currency`, `estimatedDeliveryDays`).

Server **must** recompute price from its own catalogue. The client's `priceCents` is a display
convenience and is never trusted.

### `POST /studio/orders`

Body: `PrintOrderRequest` + Stripe payment token.

`orderID` (client-generated UUID) is the **idempotency key**. A retry with the same key returns the
original order and must never render, charge, or print twice. Persist the key before doing any
work.

Ordering of operations matters:

1. Validate recipe + SKU + resolution. Reject early — see §6.
2. Capture payment.
3. Render + upload.
4. Create Prodigi order.
5. If (4) fails, the order enters `failed` and refund is automatic. Never leave a captured payment
   without either a Prodigi order or a refund.

### `GET /studio/orders/{id}` · `GET /studio/orders`

Returns `PrintOrder` — status, tracking URL, carrier, estimated delivery.

### `POST /webhooks/prodigi`

Signature-verified. Maps Prodigi callbacks onto `PrintOrderStatus`. Must be idempotent; providers
retry and re-order.

| Prodigi stage | `PrintOrderStatus` |
|---|---|
| `InProgress` / `Ready` | `inProduction` |
| `Shipped` / `Complete` | `shipped` |
| `Cancelled` | `cancelled` |
| Any error stage | `failed` |

---

## 4. The renderer

The heaviest piece. `StudioComposition` is SwiftUI, so the pragmatic path is a **macOS render
service** running the same composition code — one composition for preview and print was the
existing architecture's best idea and is worth preserving. A headless reimplementation in another
language would be a second source of truth for the artwork, and it would drift.

Input: the `PosterConfig` recipe plus the activity's route.
Output: one print-ready asset per order.

Requirements:

- **300 DPI at trim.** 12×18 → 3,600 × 5,400 px. 16×24 → 4,800 × 7,200 px. 24×36 → 7,200 × 10,800 px.
- **0.125″ bleed on all four edges.** The artwork extends into it; the ground colour continues, never
  white. `PrintGeometry.bleedPixels` gives the canvas; `safeRectInBleedCanvas` gives the box no type
  may cross.
- **sRGB, explicitly tagged.** Let Prodigi convert. Do not ship untagged.
- **PDF/X-4** where Prodigi accepts it for the line; otherwise 8-bit TIFF. PNG is correct for the
  digital download and wrong for print.
- **Deterministic.** Same recipe + same route ⇒ same bytes. Pin fonts and map tile versions.

The map panel is the one genuinely hard part: it is an `MKMapSnapshotter` raster authored at
1,000 pt. Upsampled to 10,800 px it will be visibly soft. Options, in order of preference:

1. Snapshot at the target resolution server-side (MapKit on macOS supports large snapshots).
2. Restrict 24×36 to the vector-led styles (Minimal, Trail Journal, Midnight Atlas) that have no
   raster map at all.
3. Accept softness only on Satellite, where photographic grain reads as texture.

---

## 5. Storage

| Asset | Where | Retention |
|---|---|---|
| Print-ready file | Private object storage, signed URLs only | 90 days (reprint window) |
| Recipe (`PosterConfig` JSON) | Primary DB, with the order | Indefinite — this is what makes a reprint possible after the file expires |
| Preview / mockup | CDN, public | Ephemeral |

Never make a print file publicly addressable. Prodigi fetches via a signed URL with a short TTL.

---

## 6. Refusing bad orders

Reject **before** charging:

- SKU does not resolve against `GET /v4.0/products/{sku}`. Validate the whole catalogue at boot and
  alarm on drift — Prodigi retires SKUs.
- Activity has fewer than 2 route coordinates and the style needs a route.
- Achieved DPI < 200 (`PrintGeometry.isAcceptable`). Ship nothing soft.
- Aspect mismatch between the recipe's `printAspect` and the SKU's geometry.
- Shipping country not in the served set.

Each returns a `FulfilmentError` the client already models, so the UI can say something true.

---

## 7. Partner criteria (why Prodigi, and what to hold it to)

Weight what is hard to change later, not what is easy to evaluate:

| Criterion | Why it ranks where it does |
|---|---|
| **True white-label** | Binary and disqualifying. No provider branding, no inserts, custom packing slip. Verify with a sample order, not a sales page. |
| **Frame consistency** | Frames are where cheapness shows, and consistency across facilities is the risk. |
| **Archival paper** | The Fine-Art line has to justify the word. |
| **Webhooks** | Polling for order status does not scale and reads as slow. |
| **Reprint/damage API** | A support case that needs a human on the provider's side becomes a support case that needs a human on yours. |
| **Sample orders** | Order every SKU before launch. Photograph the packaging. |
| API quality | Lowest weight — the adapter is written once. |

`FulfilmentProvider` exists so Prodigi is an implementation detail. The first partner is rarely the
last.

---

## 8. Before the first real order

- [ ] Validate every SKU in `PrintCatalog` against the live Prodigi catalogue (currently **unverified**).
- [ ] Reprice from real Prodigi quotes + margin (currently **placeholder**).
- [ ] Order one sample of every SKU; check trim, colour, framing, packaging.
- [ ] Proof the Etch Blue route specifically — most drift-prone colour in the product.
- [ ] Confirm bleed handling with Prodigi for both the print and framed lines.
- [ ] Decide the 24×36 map-panel strategy (§4).
- [ ] Write the refund and reprint runbook before it is needed, not during.
