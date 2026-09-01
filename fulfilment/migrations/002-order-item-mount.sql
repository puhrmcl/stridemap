-- 002 · Order items carry a mount colour.
--
-- The medal frame is the only product in the range that needs two Prodigi attributes: `color`
-- for the moulding and `mountColor` for the board the medal sits against. A quote is rejected
-- with either missing, so the second one needs a column of its own rather than being folded into
-- `frame` — support reading a row should see the two choices the customer actually made.
--
-- Applied automatically by the Deploy fulfilment worker workflow, which records it in
-- schema_migrations. `ALTER TABLE ... ADD COLUMN` is safe on a populated table: existing rows get
-- NULL, which is exactly right — nothing ordered before this had a mount.

ALTER TABLE order_items ADD COLUMN mount TEXT;
