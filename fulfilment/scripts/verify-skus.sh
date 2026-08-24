#!/usr/bin/env bash
#
# Etch Studio — Phase 1 SKU verification (the gate before any order can exist).
#
# Checks every SKU the app offers against the live Prodigi catalog, and pulls a
# real quote for each (production + shipping cost) so retail pricing can be set
# from actual numbers instead of the placeholders currently in PrintCatalog.swift.
#
# Usage:
#   export PRODIGI_API_KEY=your-key-here
#   ./verify-skus.sh            # sandbox (default)
#   ./verify-skus.sh --live     # production API
#
# Paste the full output back into the working session; it contains no secrets.

set -euo pipefail

if [[ -z "${PRODIGI_API_KEY:-}" ]]; then
  echo "error: set PRODIGI_API_KEY first (export PRODIGI_API_KEY=...)" >&2
  exit 1
fi

BASE="https://api.sandbox.prodigi.com"
[[ "${1:-}" == "--live" ]] && BASE="https://api.prodigi.com"
echo "── Prodigi SKU verification · $BASE"

# The catalog as currently shipped in Etch/Studio/PrintCatalog.swift (UNVERIFIED).
# Framed SKUs quote with a frame colour attribute; prints don't.
SKUS=(
  "GLOBAL-FAP-12X18:"
  "GLOBAL-FAP-16X24:"
  "GLOBAL-FAP-24X36:"
  # CFPM (mounted/matted) verified but its mat crops the print area to ~1:1.74 —
  # a 2:3 artwork would lose its sides. CFP (unmounted classic frame) should be
  # the full-bleed 2:3 framed product; verifying both to compare.
  "GLOBAL-CFPM-12X18:black"
  "GLOBAL-CFPM-16X24:black"
  "GLOBAL-CFP-12X18:black"
  "GLOBAL-CFP-16X24:black"
  "GLOBAL-CFP-24X36:black"
  # Hahnemühle German Etching (310gsm mould-made) — candidate premium paper for the
  # unframed line. Verifying existence + landed cost before any catalog decision.
  "GLOBAL-HGE-12X18:"
  "GLOBAL-HGE-16X24:"
  "GLOBAL-HGE-24X36:"
)

for entry in "${SKUS[@]}"; do
  sku="${entry%%:*}"
  frame="${entry#*:}"
  echo
  echo "━━ $sku"

  # 1) Does the SKU exist at all? (Retries: the live API drops the odd connection —
  # a transient curl failure must never abort the whole verification.)
  code=$(curl -sS -o /tmp/prodigi-product.json -w "%{http_code}" \
    --retry 3 --retry-all-errors --max-time 30 \
    -H "X-API-Key: $PRODIGI_API_KEY" \
    "$BASE/v4.0/products/$sku" || echo "000")
  if [[ "$code" == "000" ]]; then
    echo "   product: NETWORK ERROR (retried; re-run to confirm)"
    continue
  fi
  if [[ "$code" != "200" ]]; then
    echo "   product: MISSING (HTTP $code)"
    cat /tmp/prodigi-product.json 2>/dev/null | head -c 400; echo
    continue
  fi
  echo "   product: OK"
  # Description + print area pixel guidance, when present.
  python3 - <<'PY' 2>/dev/null || true
import json
p = json.load(open("/tmp/prodigi-product.json")).get("product", {})
print(f"   name: {p.get('description','?')}")
for v in (p.get("variants") or [])[:1]:
    print(f"   printAreaSizes: {json.dumps(v.get('printAreaSizes'))}")
attrs = p.get("attributes") or {}
if attrs: print(f"   attributes: {json.dumps(attrs)}")
PY

  # 2) What does one actually cost, shipped to the US?
  if [[ -n "$frame" ]]; then
    attributes="{\"color\":\"$frame\"}"
  else
    attributes="{}"
  fi
  quote=$(curl -sS --retry 3 --retry-all-errors --max-time 30 \
    -H "X-API-Key: $PRODIGI_API_KEY" -H "Content-Type: application/json" \
    -X POST "$BASE/v4.0/quotes" -d @- <<JSON
{
  "shippingMethod": "Standard",
  "destinationCountryCode": "US",
  "items": [
    { "sku": "$sku", "copies": 1, "attributes": $attributes,
      "assets": [{ "printArea": "default" }] }
  ]
}
JSON
  ) || quote='{"curl_error":"network failure after retries"}'
  echo "$quote" | python3 - <<'PY' 2>/dev/null || echo "   quote: $quote" | head -c 500
import json, sys
data = json.load(sys.stdin)
quotes = data.get("quotes") or []
if not quotes:
    print(f"   quote: FAILED — {json.dumps(data)[:400]}")
else:
    q = quotes[0]
    cost = q.get("costSummary", {})
    items = cost.get("items", {})
    ship = cost.get("shipping", {})
    print(f"   items cost: {items.get('amount')} {items.get('currency','')}")
    print(f"   shipping:   {ship.get('amount')} {ship.get('currency','')}")
PY
done

echo
echo "── Done. Paste everything above back into the session."
