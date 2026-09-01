-- 001 · Orders become headers; pieces become items.
--
--   npx wrangler d1 execute etch-fulfilment --file=migrations/001-multi-item-orders.sql --remote
--
-- Run this ONCE against a database created before multi-item orders. `schema.sql` is a bootstrap
-- of CREATE TABLE IF NOT EXISTS statements, so editing it fixes fresh databases and does nothing
-- at all to a deployed one — which is what this file is for.
--
-- If the store has never taken an order (the case at the time of writing: no Shopify products
-- exist yet and no checkout has completed), the faster and equally correct route is to drop the
-- `orders` table and re-run `schema.sql`. This migration exists so that stops being a
-- requirement, and so the procedure is on record either way.
--
-- Safe to run against a database that has already been migrated only in the sense that it will
-- fail loudly on the first statement rather than corrupt anything: `orders.creation_id` no longer
-- exists after a successful run.

-- Defer FK checks: `order_items.order_id` references `orders`, which is dropped mid-flight.
PRAGMA defer_foreign_keys = true;

-- 1 · Every existing order carried exactly one piece. Move it, preserving the Etch order number
--     by reusing `orders.id` as `order_id`.
INSERT OR IGNORE INTO order_items (order_id, creation_id, asset_id, sku, frame, quantity, price_cents)
SELECT id, creation_id, asset_id, sku, frame, quantity, price_cents FROM orders;

-- 2 · Rebuild the header without the line columns. SQLite cannot drop several columns in place,
--     so this is the standard create-copy-drop-rename.
CREATE TABLE orders_migrated (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  shopify_order_id TEXT NOT NULL UNIQUE,
  status           TEXT NOT NULL DEFAULT 'submitted',
  prodigi_order_id TEXT,
  tracking_url     TEXT,
  carrier          TEXT,
  price_cents      INTEGER,
  currency         TEXT,
  recipient_json   TEXT NOT NULL,
  last_error       TEXT,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);

INSERT INTO orders_migrated
  (id, shopify_order_id, status, prodigi_order_id, tracking_url, carrier,
   price_cents, currency, recipient_json, last_error, created_at, updated_at)
SELECT
   id, shopify_order_id, status, prodigi_order_id, tracking_url, carrier,
   price_cents, currency, recipient_json, last_error, created_at, updated_at
FROM orders;

DROP TABLE orders;
ALTER TABLE orders_migrated RENAME TO orders;

-- 3 · Indexes went with the dropped table.
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_prodigi ON orders(prodigi_order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
