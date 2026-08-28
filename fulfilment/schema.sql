-- Etch fulfilment ledger (D1 / SQLite).
--
-- This is the JOIN between the three vendors: the one place an Etch order number
-- connects a Shopify order, a frozen production asset, and a Prodigi shipment.
-- Support and accounting read this; nothing else duplicates its truth.

-- Frozen production assets (§32–33 of the master brief: immutability).
-- The R2 object lives at key `assets/<id>`; a row here is the asset's identity.
-- `frozen` flips to 1 the moment an order references the asset — from then on the
-- object and this row are immutable (uploads to a frozen id are refused).
CREATE TABLE IF NOT EXISTS assets (
  id               TEXT PRIMARY KEY,            -- UUID minted by the app at upload
  creation_id      TEXT NOT NULL,               -- StudioCreation this was rendered from
  sha256           TEXT NOT NULL,               -- checksum of the uploaded bytes, verified server-side
  content_type     TEXT NOT NULL,
  pixel_size       TEXT NOT NULL,               -- "3600x5400"
  renderer_version TEXT NOT NULL,               -- so a reorder is reproduced, never re-imagined
  frozen           INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT NOT NULL
);

-- Orders. `id` doubles as the Etch order number: ETCH-<10000 + id>.
--
-- This is the order *header*. It once carried the piece as well — creation_id, asset_id, sku,
-- frame and quantity sat right here — which silently asserted that an order is one thing. The
-- marathon customer is the counter-example the product was designed for and the schema forbade:
-- a Year Book, a framed race print and a medal frame bought together are one payment, one
-- address, one Etch number, and one Prodigi order with three items in it. Lines now live in
-- `order_items`, and the header holds only what is true of the whole order.
CREATE TABLE IF NOT EXISTS orders (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  shopify_order_id TEXT NOT NULL UNIQUE,        -- idempotency: one Etch order per Shopify order
  -- Normalized customer-facing status; raw values match the iOS PrintOrderStatus enum.
  status           TEXT NOT NULL DEFAULT 'submitted',
  prodigi_order_id TEXT,
  tracking_url     TEXT,
  carrier          TEXT,
  price_cents      INTEGER,                     -- order total: sum of the items below
  currency         TEXT,
  recipient_json   TEXT NOT NULL,               -- shipping address as submitted, for support lookups
  last_error       TEXT,                        -- populated when status = 'failed'; cleared on retry
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);

-- One row per purchasable piece in an order: its own frozen asset, its own SKU, its own finish.
--
-- UNIQUE(order_id, asset_id) is the per-line idempotency key, the counterpart to the header's
-- UNIQUE(shopify_order_id). A redelivered webhook re-inserts nothing at either level.
CREATE TABLE IF NOT EXISTS order_items (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id    INTEGER NOT NULL REFERENCES orders(id),
  creation_id TEXT NOT NULL,                    -- StudioCreation this line was rendered from
  asset_id    TEXT NOT NULL REFERENCES assets(id),
  sku         TEXT NOT NULL,                    -- Prodigi SKU for product+size
  frame       TEXT,                             -- Prodigi frame/wood colour attribute, where it applies
  quantity    INTEGER NOT NULL DEFAULT 1,       -- copies of this piece; Prodigi's `copies`
  price_cents INTEGER,                          -- line total as Shopify charged it
  UNIQUE(order_id, asset_id)
);

-- Processed webhook deliveries (§39: assume every event can arrive more than once).
CREATE TABLE IF NOT EXISTS webhook_events (
  id          TEXT PRIMARY KEY,                 -- "<source>:<delivery id>"
  source      TEXT NOT NULL,                    -- 'shopify' | 'prodigi'
  received_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_prodigi ON orders(prodigi_order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
