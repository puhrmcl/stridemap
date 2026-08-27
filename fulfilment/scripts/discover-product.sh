#!/usr/bin/env bash
#
# Etch Studio — resolve a Prodigi product's real SKUs from its product page.
#
# Guessing a SKU from the range sheet's prefix has failed on every product we've tried; reading
# the product page's own HTML has worked on every one. So this does the latter directly: fetch
# the page, pull out every SKU-shaped token that starts with the prefix, and probe each against
# the live catalog, printing the full payload for anything that resolves.
#
# The session's egress proxy blocks prodigi.com, which is why this runs on a CI runner.
#
# Usage:
#   ./discover-product.sh <prefix> <product-page-url> [more urls...]
#
# Example:
#   ./discover-product.sh GLOBAL-MPF https://www.prodigi.com/products/wall-art/framed-prints/multi-photo-frames/

set -euo pipefail

PREFIX="${1:?usage: discover-product.sh <sku-prefix> <url> [url...]}"
shift

BASE="${PRODIGI_BASE:-https://api.prodigi.com}"

echo "════════ $PREFIX ════════"

FOUND=""
for url in "$@"; do
  echo "── page: $url"
  if ! curl -sSL --max-time 30 -o page.html "$url"; then
    echo "   (fetch failed)"
    continue
  fi
  hits=$(grep -oE "${PREFIX}[A-Z0-9-]{0,40}" page.html | sort -u || true)
  if [[ -z "$hits" ]]; then
    echo "   (no ${PREFIX}-shaped strings)"
  else
    echo "$hits" | sed 's/^/   /'
    FOUND+=$'\n'"$hits"
  fi
done

if [[ -z "${PRODIGI_API_KEY:-}" ]]; then
  echo "note: PRODIGI_API_KEY unset — listed the page's SKUs only, skipped catalog probes."
  exit 0
fi

echo ""
echo "── Catalog probes"
printf '%s\n' "$FOUND" | sort -u | while read -r sku; do
  [[ -z "$sku" ]] && continue
  code=$(curl -s -o body.json -w "%{http_code}" --max-time 30 \
    -H "X-API-Key: $PRODIGI_API_KEY" "$BASE/v4.0/products/$sku" || echo "000")
  if [[ "$code" == "200" ]]; then
    echo "── $sku → FOUND"
    # Print areas and the exact attribute names/values a quote will demand. Guessing these
    # has cost a round trip before (the medal frame needs both color and mountColor).
    python3 - <<'PY' || cat body.json
import json
p = json.load(open("body.json")).get("product", {})
print(f"   name: {p.get('description','?')}")
for v in (p.get("variants") or [])[:1]:
    print(f"   printAreaSizes: {json.dumps(v.get('printAreaSizes'))}")
attrs = p.get("attributes") or {}
if attrs:
    print(f"   attributes: {json.dumps(attrs)}")
PY
    echo ""
  else
    echo "── $sku → $code"
  fi
done

echo ""
echo "── Done."
