#!/usr/bin/env bash
#
# Etch Studio — medal frame discovery.
#
# The working session's network can't reach prodigi.com, so the runner fetches the medal frame
# range PDF, dumps its text, and probes every SKU-shaped token in it against the live catalog.
# The output is what the app's medal frame product gets built from: real SKUs, real print areas,
# real quotes — the same gate every other product went through.
#
# Usage:
#   export PRODIGI_API_KEY=...
#   ./medal-frames.sh          # sandbox
#   ./medal-frames.sh --live   # production catalog

set -euo pipefail

BASE="https://api.sandbox.prodigi.com"
[[ "${1:-}" == "--live" ]] && BASE="https://api.prodigi.com"
PDF="https://www.prodigi.com/download/product-range/Prodigi%20Medal%20frames.pdf"

echo "── Prodigi medal frames · $BASE"

command -v pdftotext >/dev/null 2>&1 || sudo apt-get install -y -qq poppler-utils >/dev/null

curl -sSL --fail -o medal.pdf "$PDF"
pdftotext -layout medal.pdf medal.txt

echo ""
echo "── BEGIN-PDF-TEXT"
cat medal.txt
echo "── END-PDF-TEXT"
echo ""

# SKU-shaped tokens: uppercase segments joined by hyphens, e.g. GLOBAL-MEDAL-8X10.
CANDIDATES=$(grep -oE '[A-Z][A-Z0-9]{1,}(-[A-Z0-9]+){1,5}' medal.txt | sort -u || true)

echo "── SKU candidates found in the PDF"
echo "$CANDIDATES"
echo ""

if [[ -z "${PRODIGI_API_KEY:-}" ]]; then
  echo "note: PRODIGI_API_KEY unset — printed the PDF only, skipped catalog probes."
  exit 0
fi

# The PDF names products in prose as often as in SKUs, so also try the shapes Prodigi's
# catalog actually uses for framed goods. A 404 here is information, not a failure.
EXTRA=(
  "GLOBAL-MEDAL-FRAME" "GLOBAL-MEDALFRAME" "MEDAL-FRAME"
  "GLOBAL-MF-8X10" "GLOBAL-MF-A4" "GLOBAL-MF-A3"
)

probe() {
  local sku="$1"
  local code
  code=$(curl -s -o body.json -w "%{http_code}" \
    -H "X-API-Key: $PRODIGI_API_KEY" \
    "$BASE/v4.0/products/$sku" || echo "000")
  if [[ "$code" == "200" ]]; then
    echo "── $sku → FOUND"
    # Print the whole payload: print areas, attributes and their valid values are
    # exactly what the app needs, and guessing them has cost us a round trip before.
    cat body.json
    echo ""
  else
    echo "── $sku → $code"
  fi
}

echo "── Catalog probes"
for sku in $CANDIDATES "${EXTRA[@]}"; do
  case "$sku" in
    *[0-9A-Z]*) probe "$sku" ;;
  esac
done

echo ""
echo "── Done. Paste this log back into the session."
