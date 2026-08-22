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
 * Three invariants live here and nowhere else:
 *   1. IMMUTABILITY — an asset referenced by an order is frozen; uploads to its id are refused.
 *   2. IDEMPOTENCY — every webhook can arrive twice; nothing charges, prints, or numbers twice.
 *   3. NO SPLIT BRAIN — a paid order that fails Prodigi submission stays visible as `failed`
 *      with the error preserved, retriable via /admin/retry, never silently lost.
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
 *   POST /admin/verify-skus            Bearer UPLOAD_TOKEN; body {skus:[…]} — checks each
 *                                      against the live Prodigi catalog (the Phase 1 gate:
 *                                      the SKUs in the app are UNVERIFIED until this passes).
 */

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
} satisfies ExportedHandler<Env>;

class HttpError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
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
  const line = order.line_items?.find((item) => prop(item, "_etch_asset_id"));
  if (!line) return json({ ok: true, skipped: "no_etch_line_item" });

  const assetID = prop(line, "_etch_asset_id")!;
  const creationID = prop(line, "_etch_creation_id") ?? "unknown";
  const sku = prop(line, "_etch_sku");
  const frame = prop(line, "_etch_frame") ?? null;
  if (!sku) return json({ ok: true, skipped: "no_sku_property" });

  // Freeze the asset the moment money has moved against it (§33).
  await env.LEDGER.prepare("UPDATE assets SET frozen = 1 WHERE id = ?").bind(assetID).run();

  const inserted = await env.LEDGER
    .prepare(
      `INSERT OR IGNORE INTO orders
         (shopify_order_id, creation_id, asset_id, sku, frame, quantity, status,
          price_cents, currency, recipient_json, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 'submitted', ?, ?, ?, ?, ?)`
    )
    .bind(
      String(order.id), creationID, assetID, sku, frame, line.quantity ?? 1,
      Math.round(parseFloat(line.price ?? "0") * 100), order.currency ?? "USD",
      JSON.stringify(order.shipping_address ?? {}), now(), now()
    ).run();
  if (!inserted.meta.changes) return json({ ok: true, duplicate: true });

  const row = await env.LEDGER
    .prepare("SELECT id FROM orders WHERE shopify_order_id = ?")
    .bind(String(order.id)).first<{ id: number }>();
  const etchNumber = `ETCH-${10000 + (row?.id ?? 0)}`;

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

  const address = JSON.parse(String(order.recipient_json ?? "{}")) as Record<string, string | null>;
  const assetURL = await signedAssetURL(env, origin, String(order.asset_id));

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
    items: [
      {
        merchantReference: String(order.creation_id),
        sku: String(order.sku),
        copies: Number(order.quantity ?? 1),
        sizing: "fillPrintArea",
        attributes: order.frame ? { color: String(order.frame) } : {},
        assets: [{ printArea: "default", url: assetURL }],
      },
    ],
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
      `SELECT id, status, tracking_url, carrier, sku, frame, created_at, updated_at
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
