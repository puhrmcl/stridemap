# Etch — Studio fulfilment worker

The spine between Shopify and Prodigi (see the Operating Plan and
`docs/studio-backend-spec.md`): frozen production assets in R2, the
order↔creation↔asset ledger in D1, Shopify paid-order webhooks in, Prodigi
orders out, status mapped back to the app's normalized states.

```
iOS render ──PUT /assets/:id──▶ R2 (frozen at order)
Shopify orders/paid ──HMAC──▶ worker ──▶ Prodigi /v4.0/Orders
Prodigi callbacks ──token──▶ worker ──▶ ledger status ──▶ app GET /orders/by-shopify/:id
```

## One-time setup

```bash
cd fulfilment
npm install
npx wrangler login
npx wrangler r2 bucket create etch-production-assets
npx wrangler d1 create etch-fulfilment      # paste database_id into wrangler.toml
npx wrangler d1 execute etch-fulfilment --file=schema.sql
npx wrangler secret put SHOPIFY_WEBHOOK_SECRET
npx wrangler secret put PRODIGI_API_KEY     # sandbox key first
npx wrangler secret put UPLOAD_TOKEN        # generate: openssl rand -hex 32
npx wrangler deploy
```

### Upgrading a database created before multi-item orders

`schema.sql` is a bootstrap of `CREATE TABLE IF NOT EXISTS`, so it fixes new databases and leaves
existing ones untouched. A database created before orders became headers-plus-items needs its
migration run once:

```bash
npx wrangler d1 execute etch-fulfilment --file=migrations/001-multi-item-orders.sql --remote
```

With no orders yet placed, dropping `orders` and re-running `schema.sql` is equally correct and
quicker. Either way it must happen **before** deploying the worker: the new code writes
`order_items`, which the old schema has no table for.

Then point:
- Shopify webhook `orders/paid` → `https://…workers.dev/webhooks/shopify`
- Prodigi callback URL → `https://…workers.dev/webhooks/prodigi?token=<UPLOAD_TOKEN>`

## The Phase 1 gate

The SKUs in the iOS `PrintCatalog` are **unverified**. Before anything else:

```bash
curl -X POST https://…workers.dev/admin/verify-skus \
  -H "Authorization: Bearer $UPLOAD_TOKEN" -H "Content-Type: application/json" \
  -d '{"skus":["GLOBAL-FAP-12X18","GLOBAL-FAP-16X24","GLOBAL-FAP-24X36","GLOBAL-CFPM-12X18","GLOBAL-CFPM-16X24"]}'
```

Anything not `ok` must be replaced in `Etch/Studio/PrintCatalog.swift` before an
order can exist. The §36 POC chain (activity → artwork → checkout → Prodigi
sandbox → status) exits this phase only when it has run clean twice, including
one forced mid-chain failure recovered via `/admin/retry`.

## Invariants (do not weaken)

1. **Immutability** — an asset referenced by an order is frozen; uploads to its
   id are refused (§33).
2. **Idempotency** — every webhook can arrive twice; `webhook_events` +
   `UNIQUE(shopify_order_id)` make replays harmless (§39).
3. **No split brain** — a paid order that fails Prodigi submission stays
   `failed` with the error preserved and is retriable; it is never lost.
