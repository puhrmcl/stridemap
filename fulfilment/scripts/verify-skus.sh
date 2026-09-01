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
  # The decided unframed line: Hahnemühle German Etching (310gsm mould-made).
  "GLOBAL-HGE-12X18:"
  "GLOBAL-HGE-16X24:"
  "GLOBAL-HGE-24X36:"
  # Candidate entry size for both lines (sub-$100 framed gift rung).
  "GLOBAL-HGE-8X12:"
  "GLOBAL-CFP-8X12:black"
  # The framed line (Classic Frame, no mount, full-bleed 2:3). The product-detail
  # attributes dump is the authority on valid frame colour values; the white /
  # dark grey quotes below probe the exact attribute strings for the two new
  # finishes before they enter FrameFinish.
  "GLOBAL-CFP-12X18:black"
  "GLOBAL-CFP-16X24:black"
  "GLOBAL-CFP-16X24:white"
  "GLOBAL-CFP-16X24:dark grey"
  "GLOBAL-CFP-24X36:black"
  # Gallery squares (multi-tile compositions on square classic frames, Q1).
  "GLOBAL-CFP-12X12:black"
  "GLOBAL-CFP-20X20:black"
  "GLOBAL-CFP-24X24:black"
  # Year Book candidates — layflat photo book, SKU prefix BOOK-FE per the product
  # page (sizes: A4 landscape 297x210, squares 210x210 and 297x297; 18-122 pages).
  # Exact SKU naming unknown, so several candidates; the product-details dump of
  # whichever resolves is the authority on the page-count attribute for quotes.
  # The Year Book's confirmed variant, straight from the product page's dashboard
  # link: BOOK-FE-A4-L-LF-G (A4 · Landscape · LayFlat · Gloss). The pages=NN entry
  # probes the page-count attribute for a real quote; the rest probe the square
  # sizes on the same naming pattern.
  "BOOK-FE-A4-L-LF-G:"
  "BOOK-FE-A4-L-LF-G:pages=26"
  "BOOK-FE-8X8-S-LF-G:"
  "BOOK-FE-12X12-S-LF-G:"
  "BOOK-FE-210X210-S-LF-G:"
  "BOOK-FE-297X297-S-LF-G:"
  "BOOK-FE-21X21-S-LF-G:"
  "BOOK-FE-30X30-S-LF-G:"
  # Medal frame — the code the product page carries verbatim. Note MOUNT sits in the
  # middle, which is why 24 suffix guesses off the MEDAL-FRA-CLA prefix all 404'd.
  # The attribute dump is the authority on how frame colour and bottom-mount colour
  # are expressed; the bare quote gives the landed cost the retail rung needs.
  "MEDAL-FRA-CLA-MOUNT-30X40:"
  "MEDAL-FRA-CLA-MOUNT-30X40:color=black,mountColor=Black"
  "MEDAL-FRA-CLA-MOUNT-30X40:color=natural,mountColor=Navy"
  # Photo Wall — the multi-photo frame the wall prints into. 20X30 is the L
  # template (8x5 = 40 windows), which is what the wall now defaults to, so this
  # quote is the one that sets prices.photoWallCents. Mounted (MPFM) is the
  # version whose windows are physically cut; unmounted (MPF) is quoted beside it
  # so the difference the mount costs is a number rather than an assumption.
  "GLOBAL-MPFM-20X30:color=black,mountColor=Snow white"
  "GLOBAL-MPF-20X30:color=black"
  "GLOBAL-MPFM-16X24:color=black,mountColor=Snow white"
  "GLOBAL-MPFM-24X36:color=black,mountColor=Snow white"

  # Metal prints (aluminium, ChromaLuxe, ships US). The product page's example table shows only
  # 4x6 / 12x12 / 16x20 / 8x24 / 24x24 — no 2:3 size — and prefix-guessing has failed 4/4 in
  # this project, so these are candidates to CONFIRM OR BURY, not sizes to ship. A miss here is
  # the answer working, not the rig failing.
  # All four resolved — the example table was just incomplete, and every size is ~300 DPI 2:3
  # (12x18 = 3636x5436, 24x36 = 7275x10875). `finish` is the one required attribute; quoted
  # with the middle of its five values to get real prices this pass.
  "GLOBAL-MET-12X18:finish=satin"
  "GLOBAL-MET-16X24:finish=satin"
  "GLOBAL-MET-24X36:finish=satin"

  # Wall stickers — the global product, fulfilled from the nearest lab. Table read live off the
  # product page, so these should all resolve; the quotes are what's actually unknown.
  "WALL-STKR-A4:"
  "WALL-STKR-400X500:"
  "WALL-STKR-600X600:"
  "WALL-STKR-800X800:"
  # Poster hanger — the confirmed 24x36 portrait, plus the two sizes the finish
  # needs before it can be offered at all. 12X18 and 16X24 were not on the product
  # page; these probe the naming pattern the confirmed codes establish
  # (POSTER-HANGER-<hanger cm>-<print size>-<orientation>), and either would open
  # the finish on a size the device can already render.
  "POSTER-HANGER-60-24X36-PORT:color=natural"
  "POSTER-HANGER-30-12X18-PORT:color=natural"
  "POSTER-HANGER-40-12X18-PORT:color=natural"
  "POSTER-HANGER-40-16X24-PORT:color=natural"
  "POSTER-HANGER-50-16X24-PORT:color=natural"
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

  # 2) What does one actually cost, shipped to the US? The suffix after ':' is a
  # frame colour by default; a "key=value" form passes any attribute (books need
  # a page count, for instance).
  if [[ -n "$frame" ]]; then
    if [[ "$frame" == *"="* ]]; then
      # Comma-separated key=value pairs. One attribute isn't always enough: the medal
      # frame rejects a quote without *both* a frame colour and a mount colour.
      attributes="{"
      first=1
      while IFS= read -r pair; do
        [[ -z "$pair" ]] && continue
        attr_key="${pair%%=*}"
        attr_value="${pair#*=}"
        [[ $first -eq 0 ]] && attributes+=","
        attributes+="\"$attr_key\":\"$attr_value\""
        first=0
      done < <(tr ',' '\n' <<< "$frame")
      attributes+="}"
    else
      attributes="{\"color\":\"$frame\"}"
    fi
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
