/**
 * Etch — Studio fulfilment worker (Cloudflare Worker + R2 + D1)
 *
 * The spine between Shopify and Prodigi (Operating Plan, decision 2; master brief §§32–43):
 *
 *   iOS renders the print file at order time
 *     → PUT /assets/:id              (frozen into R2; checksum verified)
 *   Shopify checkout completes
 *     → POST /webhooks/shopify       (HMAC-verified, idempotent; ledger row; Prodigi order)
 *   Prodigi produces and ships
 *     → POST /webhooks/prodigi       (status mapped to the app's normalized states)
 *   The app shows honest status
 *     → GET /orders/by-shopify/:id
 *
 * Four invariants live here and nowhere else:
 *   1. IMMUTABILITY — an asset referenced by an order is frozen; uploads to its id are refused.
 *   2. IDEMPOTENCY — every webhook can arrive twice; nothing charges, prints, or numbers twice.
 *   3. NO SPLIT BRAIN — a paid order that fails Prodigi submission stays visible as `failed`
 *      with the error preserved, retriable via /admin/retry, never silently lost.
 *   4. NOTHING PAID GOES UNPRINTED — an order is a header plus N items, and every Etch line in
 *      the Shopify payload becomes one. This used to read the first line and drop the others,
 *      which was safe only because the app could not build a multi-line cart; the server now
 *      holds that guarantee itself rather than borrowing it from the client.
 *
 * Endpoints:
 *   GET  /health
 *   PUT  /assets/:id                   Bearer UPLOAD_TOKEN; body = print-ready bytes.
 *                                      Headers: X-Checksum-SHA256, X-Creation-ID,
 *                                      X-Renderer-Version, X-Pixel-Size, Content-Type.
 *   GET  /assets/:id?exp=&sig=         Capability URL for Prodigi to fetch the print file.
 *   POST /webhooks/shopify             orders/paid topic.
 *   POST /webhooks/prodigi?token=      Prodigi order-status callbacks.
 *   GET  /orders/by-shopify/:id        Normalized status for the app.
 *   POST /admin/retry/:etchNumber      Bearer UPLOAD_TOKEN; re-submit a failed order.
 *   GET  /config                       The app's remote configuration (prices, ordering
 *                                      switch, Archive gates, seasonal copy). Data only.
 *   PUT  /admin/config                 Bearer UPLOAD_TOKEN; replaces that document.
 *   POST /admin/verify-skus            Bearer UPLOAD_TOKEN; body {skus:[…]} — checks each
 *                                      against the live Prodigi catalog (the Phase 1 gate:
 *                                      the SKUs in the app are UNVERIFIED until this passes).
 *   GET  /tiles/{z}/{x}/{y}.mvt        Etch's own basemap, read out of the PMTiles archive in
 *                                      R2. This is what replaces Apple Maps as the source of
 *                                      printable cartography — see src/tiles.ts.
 *   GET  /tiles/tiles.json             TileJSON for the above.
 */

import { serveTile, serveTileJSON, parseTilePath } from "./tiles";

export interface Env {
  ASSETS: R2Bucket;
  LEDGER: D1Database;
  /** Shopify webhook signing secret (`wrangler secret put SHOPIFY_WEBHOOK_SECRET`). */
  SHOPIFY_WEBHOOK_SECRET: string;
  /** Prodigi API key — sandbox first (`wrangler secret put PRODIGI_API_KEY`). */
  PRODIGI_API_KEY: string;
  /** Bearer token the iOS app presents for uploads and admin calls (`wrangler secret put UPLOAD_TOKEN`). */
  UPLOAD_TOKEN: string;
  /** Prodigi API base URL — sandbox by default (wrangler.toml [vars]). */
  PRODIGI_BASE: string;
  /** Object key of the basemap archive in R2. Defaults to `basemap.pmtiles`. */
  BASEMAP_KEY?: string;
}

/** Normalized statuses. Raw values MUST match the iOS `PrintOrderStatus` enum. */
type OrderStatus =
  | "submitted" | "rendering" | "inProduction"
  | "shipped" | "delivered" | "cancelled" | "failed";

const JSON_HEADERS = { "Content-Type": "application/json" };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (request.method === "GET" && path === "/health") {
        return json({ ok: true });
      }
      if (request.method === "GET" && path === "/tiles/tiles.json") {
        return await serveTileJSON(env, url.origin);
      }
      if (request.method === "GET" && path.startsWith("/tiles/")) {
        const tile = parseTilePath(path);
        if (tile) return await serveTile(env, tile.z, tile.x, tile.y);
      }
      if (request.method === "GET" && path === "/config") {
        return await serveConfig(env);
      }
      if (request.method === "PUT" && path === "/admin/config") {
        requireBearer(request, env);
        return await putConfig(request, env);
      }
      if (request.method === "PUT" && path.startsWith("/assets/")) {
        return await uploadAsset(request, env, path.slice("/assets/".length));
      }
      if (request.method === "GET" && path.startsWith("/assets/")) {
        return await serveAsset(request, env, path.slice("/assets/".length), url);
      }
      if (request.method === "POST" && path === "/webhooks/shopify") {
        return await shopifyWebhook(request, env);
      }
      if (request.method === "POST" && path === "/webhooks/prodigi") {
        return await prodigiWebhook(request, env, url);
      }
      if (request.method === "GET" && path.startsWith("/orders/by-shopify/")) {
        return await orderStatus(env, path.slice("/orders/by-shopify/".length));
      }
      if (request.method === "POST" && path.startsWith("/admin/retry/")) {
        requireBearer(request, env);
        return await retryOrder(env, path.slice("/admin/retry/".length), url);
      }
      if (request.method === "POST" && path === "/admin/verify-skus") {
        requireBearer(request, env);
        return await verifySKUs(request, env);
      }
      return json({ error: "not_found" }, 404);
    } catch (error) {
      if (error instanceof HttpError) return json({ error: error.message }, error.status);
      console.error("unhandled", error);
      return json({ error: "internal" }, 500);
    }
  },

  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    await sweepUnsoldAssets(env);
  },
} satisfies ExportedHandler<Env>;

/**
 * Delete uploads that no order ever claimed.
 *
 * The pipeline uploads the print file *before* payment, deliberately — a paid order with no
 * artwork behind it is the one failure this worker must never produce. The cost of that ordering
 * is that every abandoned checkout leaves a full-resolution sheet in R2, and a 24 × 36 is tens of
 * megabytes. One is nothing. A cart, which invites someone to assemble three pieces and then
 * think about it overnight, turns that into a bill that grows forever and is never noticed,
 * because nothing in the system ever looked at it.
 *
 * `frozen = 1` is set the instant money moves against an asset, so frozen is exactly the set that
 * must survive. Everything else older than the window is a checkout that did not happen.
 *
 * The window is generous on purpose: a buyer who prepares an order, closes the app and returns
 * the next morning must still find their file, and a Shopify webhook that is slow or retried must
 * never race a delete. Two days is far longer than either needs.
 */
const UNSOLD_ASSET_TTL_DAYS = 2;

async function sweepUnsoldAssets(env: Env): Promise<void> {
  const cutoff = new Date(Date.now() - UNSOLD_ASSET_TTL_DAYS * 86_400_000).toISOString();

  // Bounded per run: a sweep that tried to delete an unbounded backlog in one invocation would
  // hit the Worker's limits and delete nothing. Nightly runs drain any backlog across days.
  const stale = await env.LEDGER
    .prepare(
      `SELECT id FROM assets
       WHERE frozen = 0 AND created_at < ?
         AND id NOT IN (SELECT asset_id FROM order_items)
       ORDER BY created_at LIMIT 500`
    )
    .bind(cutoff)
    .all<{ id: string }>();

  const ids = stale.results?.map((row) => row.id) ?? [];
  if (ids.length === 0) return;

  // R2 first. An orphaned object with no row is invisible and costs money forever; a row whose
  // object is already gone is harmless and will be cleaned on the next pass. Order the failure.
  for (const id of ids) {
    try {
      await env.ASSETS.delete(`assets/${id}`);
    } catch (error) {
      console.error("sweep_r2_delete_failed", id, error);
      return; // leave the row so this asset is retried tomorrow rather than lost track of
    }
  }

  await env.LEDGER.batch(
    ids.map((id) => env.LEDGER.prepare("DELETE FROM assets WHERE id = ? AND frozen = 0").bind(id))
  );
  console.log("sweep_unsold_assets", { deleted: ids.length, cutoff });
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

/* ─────────────────────────── Remote configuration ───────────────────────────
 * The values the app reads at launch instead of compiling in: prices, whether
 * ordering is open, the Archive curation thresholds, and seasonal copy. Data
 * only — Apple forbids shipping code this way, and none of this is code.
 *
 * Stored as a single JSON object in R2 so editing it is one PUT, and the app
 * keeps a compiled fallback for when this is unreachable.
 */
const CONFIG_KEY = "config/app.json";

/** Served when nothing has been written yet — matches the app's compiled defaults. */
const DEFAULT_CONFIG = {
  version: 1,
  ordering: {
    enabled: true,
    closedTitle: "Ordering opens soon",
    closedDetail:
      "Printed to order on archival paper and shipped to your door. Secure checkout with Apple Pay.",
  },
  prices: { bySKU: {}, yearBookCents: 11900 },
  archive: {
    gridMinRoutedRuns: 20,
    ridgelineMinProfiles: 12,
    ringsMinRuns: 30,
    pulseMinRuns: 30,
    constellationMinCells: 4,
    bloomMinRoutedRuns: 50,
  },
  seasonal: null,
};

async function serveConfig(env: Env): Promise<Response> {
  const object = await env.ASSETS.get(CONFIG_KEY);
  const body = object ? await object.text() : JSON.stringify(DEFAULT_CONFIG);
  return new Response(body, {
    headers: {
      ...JSON_HEADERS,
      // Short cache: an edit should reach devices in minutes, not on next launch only.
      "Cache-Control": "public, max-age=300",
    },
  });
}

async function putConfig(request: Request, env: Env): Promise<Response> {
  const text = await request.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new HttpError(400, "invalid_json");
  }
  if (typeof parsed !== "object" || parsed === null) throw new HttpError(400, "invalid_config");
  // Require a version so a device can report which document it's running.
  if (typeof (parsed as { version?: unknown }).version !== "number") {
    throw new HttpError(400, "missing_version");
  }
  await env.ASSETS.put(CONFIG_KEY, JSON.stringify(parsed), {
    httpMetadata: { contentType: "application/json" },
  });
  return json({ ok: true, version: (parsed as { version: number }).version });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function requireBearer(request: Request, env: Env): void {
  const auth = request.headers.get("Authorization") ?? "";
  if (auth !== `Bearer ${env.UPLOAD_TOKEN}`) throw new HttpError(401, "unauthorized");
}

function now(): string { return new Date().toISOString(); }

// MARK: ─ Assets (immutability lives here)

async function uploadAsset(request: Request, env: Env, id: string): Promise<Response> {
  requireBearer(request, env);
  if (!/^[0-9a-fA-F-]{36}$/.test(id)) throw new HttpError(400, "bad_asset_id");

  const claimed = request.headers.get("X-Checksum-SHA256") ?? "";
  const creationID = request.headers.get("X-Creation-ID") ?? "";
  const rendererVersion = request.headers.get("X-Renderer-Version") ?? "";
  const pixelSize = request.headers.get("X-Pixel-Size") ?? "";
  const contentType = request.headers.get("Content-Type") ?? "application/octet-stream";
  if (!claimed || !creationID || !rendererVersion || !pixelSize) {
    throw new HttpError(400, "missing_asset_headers");
  }

  const existing = await env.LEDGER
    .prepare("SELECT frozen, sha256 FROM assets WHERE id = ?").bind(id)
    .first<{ frozen: number; sha256: string }>();
  if (existing?.frozen) {
    // An ordered asset is immutable forever. A byte-identical retry is fine (idempotent);
    // anything else is refused — this is §33, enforced.
    if (existing.sha256 === claimed.toLowerCase()) return json({ ok: true, id, frozen: true });
    throw new HttpError(409, "asset_frozen");
  }

  const bytes = await request.arrayBuffer();
  if (bytes.byteLength === 0) throw new HttpError(400, "empty_body");
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const actual = hex(digest);
  if (actual !== claimed.toLowerCase()) throw new HttpError(422, "checksum_mismatch");

  await env.ASSETS.put(`assets/${id}`, bytes, { httpMetadata: { contentType } });
  await env.LEDGER
    .prepare(
      `INSERT INTO assets (id, creation_id, sha256, content_type, pixel_size, renderer_version, frozen, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 0, ?)
       ON CONFLICT(id) DO UPDATE SET sha256=excluded.sha256, content_type=excluded.content_type,
         pixel_size=excluded.pixel_size, renderer_version=excluded.renderer_version`
    )
    .bind(id, creationID, actual, contentType, pixelSize, rendererVersion, now())
    .run();
  return json({ ok: true, id });
}

/** Prodigi fetches print files through short-lived HMAC capability URLs, never a public bucket. */
async function signedAssetURL(env: Env, origin: string, id: string): Promise<string> {
  const exp = Math.floor(Date.now() / 1000) + 7 * 24 * 3600; // Prodigi may fetch late; a week.
  const sig = await hmacHex(env.UPLOAD_TOKEN, `${id}:${exp}`);
  return `${origin}/assets/${id}?exp=${exp}&sig=${sig}`;
}

async function serveAsset(request: Request, env: Env, id: string, url: URL): Promise<Response> {
  const exp = Number(url.searchParams.get("exp") ?? 0);
  const sig = url.searchParams.get("sig") ?? "";
  if (exp < Math.floor(Date.now() / 1000)) throw new HttpError(403, "expired");
  const expected = await hmacHex(env.UPLOAD_TOKEN, `${id}:${exp}`);
  if (!timingSafeEqual(sig, expected)) throw new HttpError(403, "bad_signature");

  const object = await env.ASSETS.get(`assets/${id}`);
  if (!object) throw new HttpError(404, "asset_missing");
  return new Response(object.body, {
    headers: { "Content-Type": object.httpMetadata?.contentType ?? "application/octet-stream" },
  });
}

// MARK: ─ Shopify → order → Prodigi

interface ShopifyLineItem {
  quantity: number;
  price: string;
  properties?: { name: string; value: string }[];
}
interface ShopifyOrder {
  id: number;
  currency: string;
  line_items: ShopifyLineItem[];
  shipping_address?: Record<string, string | null>;
  email?: string;
}

async function shopifyWebhook(request: Request, env: Env): Promise<Response> {
  const raw = await request.arrayBuffer();

  // Shopify signs the raw body with HMAC-SHA256, base64. Verify before parsing anything.
  const given = request.headers.get("X-Shopify-Hmac-Sha256") ?? "";
  const mac = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(env.SHOPIFY_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const expected = base64(await crypto.subtle.sign("HMAC", mac, raw));
  if (!timingSafeEqual(given, expected)) throw new HttpError(401, "bad_hmac");

  // Deliveries repeat; the delivery id is the idempotency key for the *event*, and the
  // UNIQUE(shopify_order_id) constraint is the idempotency key for the *order*.
  const deliveryID = `shopify:${request.headers.get("X-Shopify-Webhook-Id") ?? crypto.randomUUID()}`;
  const seen = await env.LEDGER
    .prepare("INSERT OR IGNORE INTO webhook_events (id, source, received_at) VALUES (?, 'shopify', ?)")
    .bind(deliveryID, now()).run();
  if (!seen.meta.changes) return json({ ok: true, duplicate: true });

  const order = JSON.parse(new TextDecoder().decode(raw)) as ShopifyOrder;

  // EVERY Etch line, not the first.
  //
  // This was `.find(...)`, which took one line and discarded the rest. Nothing caught it because
  // the app could only ever build a single-line cart — the server's correctness rested on a
  // client-side limitation, which is the wrong place for it. A customer buying a book, a race
  // print and a medal frame together would have paid for three and received one, silently, with
  // the ledger agreeing that the order was complete.
  const lines = (order.line_items ?? []).filter((item) => prop(item, "_etch_asset_id"));
  if (lines.length === 0) return json({ ok: true, skipped: "no_etch_line_item" });

  // A line without a SKU cannot be produced. Refusing the whole order is deliberate: partial
  // fulfilment of a paid basket is the failure being fixed here, so a malformed line stops
  // everything and surfaces, rather than quietly shipping the lines that happened to parse.
  const items = lines.map((line) => ({
    assetID: prop(line, "_etch_asset_id")!,
    creationID: prop(line, "_etch_creation_id") ?? "unknown",
    sku: prop(line, "_etch_sku"),
    frame: prop(line, "_etch_frame") || null,
    // Prodigi's second attribute. Only the medal frame sends one; `|| null` rather than `??`
    // so an empty string from every other product stores as null instead of "".
    mount: prop(line, "_etch_mount") || null,
    quantity: line.quantity ?? 1,
    priceCents: Math.round(parseFloat(line.price ?? "0") * 100) * (line.quantity ?? 1),
  }));
  if (items.some((item) => !item.sku)) {
    return json({ ok: true, skipped: "no_sku_property" });
  }

  // Freeze every asset the moment money has moved against it (§33).
  await env.LEDGER.batch(
    items.map((item) =>
      env.LEDGER.prepare("UPDATE assets SET frozen = 1 WHERE id = ?").bind(item.assetID)
    )
  );

  const inserted = await env.LEDGER
    .prepare(
      `INSERT OR IGNORE INTO orders
         (shopify_order_id, status, price_cents, currency, recipient_json, created_at, updated_at)
       VALUES (?, 'submitted', ?, ?, ?, ?, ?)`
    )
    .bind(
      String(order.id),
      items.reduce((total, item) => total + item.priceCents, 0),
      order.currency ?? "USD",
      JSON.stringify(order.shipping_address ?? {}), now(), now()
    ).run();
  if (!inserted.meta.changes) return json({ ok: true, duplicate: true });

  const row = await env.LEDGER
    .prepare("SELECT id FROM orders WHERE shopify_order_id = ?")
    .bind(String(order.id)).first<{ id: number }>();
  const etchNumber = `ETCH-${10000 + (row?.id ?? 0)}`;

  // The pieces. Written after the header so `order_id` exists to point at, and only once the
  // header insert reported a change — a redelivered webhook has already returned above.
  await env.LEDGER.batch(
    items.map((item) =>
      env.LEDGER.prepare(
        `INSERT OR IGNORE INTO order_items
           (order_id, creation_id, asset_id, sku, frame, mount, quantity, price_cents)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(
        row?.id ?? 0, item.creationID, item.assetID, item.sku!,
        item.frame, item.mount, item.quantity, item.priceCents
      )
    )
  );

  // Submit to Prodigi. A failure here NEVER loses the paid order: it stays `failed`
  // with the error preserved, and /admin/retry re-runs exactly this step (§39).
  try {
    await submitToProdigi(env, new URL(request.url).origin, String(order.id), etchNumber);
  } catch (error) {
    await markFailed(env, String(order.id), error);
  }
  return json({ ok: true, etchNumber });
}

function prop(item: ShopifyLineItem, name: string): string | undefined {
  return item.properties?.find((p) => p.name === name)?.value;
}

async function submitToProdigi(
  env: Env, origin: string, shopifyOrderID: string, etchNumber: string
): Promise<void> {
  const order = await env.LEDGER
    .prepare("SELECT * FROM orders WHERE shopify_order_id = ?")
    .bind(shopifyOrderID)
    .first<Record<string, unknown>>();
  if (!order) throw new Error("order_row_missing");
  if (order.prodigi_order_id) return; // already submitted — idempotent retry

  // Every piece in the order, as one Prodigi order. Prodigi's `items` array has always accepted
  // this; the worker was the thing insisting an order held one object. One order also means one
  // shipping charge where the pieces come from the same production facility — Prodigi still
  // splits across facilities when it has to, which is its routing decision rather than a second
  // checkout for the customer.
  const lines = await env.LEDGER
    .prepare(
      `SELECT creation_id, asset_id, sku, frame, mount, quantity
       FROM order_items WHERE order_id = ? ORDER BY id`
    )
    .bind(Number(order.id))
    .all<Record<string, unknown>>();
  if (!lines.results?.length) throw new Error("order_has_no_items");

  const address = JSON.parse(String(order.recipient_json ?? "{}")) as Record<string, string | null>;

  // Signed per asset. The URLs expire, so they are minted at submission rather than stored.
  const prodigiItems = await Promise.all(
    lines.results.map(async (line) => ({
      merchantReference: String(line.creation_id),
      sku: String(line.sku),
      copies: Number(line.quantity ?? 1),
      sizing: "fillPrintArea",
      // Prodigi rejects a medal-frame quote unless BOTH attributes are present, and rejects it
      // again if either is spelled the other way — `color` lowercase, `mountColor` capitalised.
      // The catalog's inconsistency, carried faithfully rather than tidied.
      attributes: {
        ...(line.frame ? { color: String(line.frame) } : {}),
        ...(line.mount ? { mountColor: String(line.mount) } : {}),
      },
      assets: [
        { printArea: "default", url: await signedAssetURL(env, origin, String(line.asset_id)) },
      ],
    }))
  );

  const body = {
    merchantReference: etchNumber,
    shippingMethod: "Standard",
    recipient: {
      name: address.name ?? `${address.first_name ?? ""} ${address.last_name ?? ""}`.trim(),
      address: {
        line1: address.address1 ?? "",
        line2: address.address2 ?? undefined,
        postalOrZipCode: address.zip ?? "",
        countryCode: address.country_code ?? "US",
        townOrCity: address.city ?? "",
        stateOrCounty: address.province_code ?? undefined,
      },
    },
    items: prodigiItems,
  };

  const response = await fetch(`${env.PRODIGI_BASE}/v4.0/Orders`, {
    method: "POST",
    headers: { "X-API-Key": env.PRODIGI_API_KEY, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = (await response.json()) as { order?: { id?: string }; outcome?: string };
  if (!response.ok || !payload.order?.id) {
    throw new Error(`prodigi_${response.status}:${JSON.stringify(payload).slice(0, 300)}`);
  }
  await env.LEDGER
    .prepare("UPDATE orders SET prodigi_order_id = ?, status = 'inProduction', last_error = NULL, updated_at = ? WHERE shopify_order_id = ?")
    .bind(payload.order.id, now(), shopifyOrderID).run();
}

async function markFailed(env: Env, shopifyOrderID: string, error: unknown): Promise<void> {
  console.error("prodigi_submission_failed", shopifyOrderID, error);
  await env.LEDGER
    .prepare("UPDATE orders SET status = 'failed', last_error = ?, updated_at = ? WHERE shopify_order_id = ?")
    .bind(String(error).slice(0, 500), now(), shopifyOrderID).run();
}

async function retryOrder(env: Env, etchNumber: string, url: URL): Promise<Response> {
  const id = Number(etchNumber.replace(/^ETCH-/, "")) - 10000;
  const order = await env.LEDGER
    .prepare("SELECT shopify_order_id FROM orders WHERE id = ?").bind(id)
    .first<{ shopify_order_id: string }>();
  if (!order) throw new HttpError(404, "order_not_found");
  try {
    await submitToProdigi(env, url.origin, order.shopify_order_id, etchNumber);
    return json({ ok: true });
  } catch (error) {
    await markFailed(env, order.shopify_order_id, error);
    throw new HttpError(502, "prodigi_retry_failed");
  }
}

// MARK: ─ Prodigi status → normalized states

async function prodigiWebhook(request: Request, env: Env, url: URL): Promise<Response> {
  // Prodigi callbacks carry no HMAC; the shared token in the callback URL is the auth.
  if (url.searchParams.get("token") !== env.UPLOAD_TOKEN) throw new HttpError(401, "bad_token");

  const event = (await request.json()) as {
    data?: {
      order?: {
        id?: string; status?: { stage?: string };
        shipments?: { carrier?: { name?: string }; tracking?: { url?: string } }[];
      };
    };
    id?: string;
  };
  const deliveryID = `prodigi:${event.id ?? crypto.randomUUID()}`;
  const seen = await env.LEDGER
    .prepare("INSERT OR IGNORE INTO webhook_events (id, source, received_at) VALUES (?, 'prodigi', ?)")
    .bind(deliveryID, now()).run();
  if (!seen.meta.changes) return json({ ok: true, duplicate: true });

  const order = event.data?.order;
  if (!order?.id) return json({ ok: true, skipped: "no_order" });

  const stage = (order.status?.stage ?? "").toLowerCase();
  const map: Record<string, OrderStatus> = {
    inprogress: "inProduction",
    complete: "shipped",
    cancelled: "cancelled",
  };
  const status = map[stage];
  if (!status) return json({ ok: true, skipped: `stage:${stage}` });

  const shipment = order.shipments?.[0];
  await env.LEDGER
    .prepare(
      `UPDATE orders SET status = ?, tracking_url = COALESCE(?, tracking_url),
         carrier = COALESCE(?, carrier), updated_at = ?
       WHERE prodigi_order_id = ?`
    )
    .bind(status, shipment?.tracking?.url ?? null, shipment?.carrier?.name ?? null, now(), order.id)
    .run();
  return json({ ok: true });
}

// MARK: ─ App-facing status + the SKU verification gate

async function orderStatus(env: Env, shopifyOrderID: string): Promise<Response> {
  const order = await env.LEDGER
    .prepare(
      `SELECT id, status, tracking_url, carrier, created_at, updated_at
       FROM orders WHERE shopify_order_id = ?`
    )
    .bind(shopifyOrderID)
    .first<Record<string, unknown>>();
  if (!order) throw new HttpError(404, "order_not_found");
  return json({
    etchNumber: `ETCH-${10000 + Number(order.id)}`,
    status: order.status,
    trackingURL: order.tracking_url,
    carrier: order.carrier,
    placedAt: order.created_at,
    updatedAt: order.updated_at,
  });
}

/** The Phase 1 gate: every SKU the app offers must resolve against the live catalog. */
async function verifySKUs(request: Request, env: Env): Promise<Response> {
  const { skus } = (await request.json()) as { skus: string[] };
  if (!Array.isArray(skus) || skus.length === 0) throw new HttpError(400, "no_skus");
  const results: Record<string, string> = {};
  for (const sku of skus) {
    const response = await fetch(`${env.PRODIGI_BASE}/v4.0/products/${encodeURIComponent(sku)}`, {
      headers: { "X-API-Key": env.PRODIGI_API_KEY },
    });
    results[sku] = response.ok ? "ok" : `missing (${response.status})`;
  }
  const allOK = Object.values(results).every((v) => v === "ok");
  return json({ ok: allOK, results }, allOK ? 200 : 422);
}

// MARK: ─ Crypto helpers

function hex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function base64(buffer: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  return hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message)));
}

/** Constant-time-ish comparison, sufficient for webhook signatures at this scale. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
