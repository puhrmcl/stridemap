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

# The PDF gives the SKU *prefix* (MEDAL-FRA-CLA) but not the full code, and the bare prefix
# 404s — the same shape of gap the layflat book had before the raw payload gave up
# BOOK-FE-A4-L-LF-G. Build the plausible codes from what the PDF does state: one size,
# 30x40cm / 12x16", with an 8x10" print area. Manufacturing is UK-only, so a region prefix is
# as likely as GLOBAL. A 404 here is information, not a failure.
EXTRA=()
for region in "" "GLOBAL-" "UK-" "EU-"; do
  for size in "-30X40" "-12X16" "-8X10" ""; do
    EXTRA+=("${region}MEDAL-FRA-CLA${size}")
  done
done
# Mount colour may be part of the code rather than an attribute.
for mount in "-BLACK" "-NAVY" "-BLK" "-NVY"; do
  EXTRA+=("MEDAL-FRA-CLA-30X40${mount}" "UK-MEDAL-FRA-CLA-30X40${mount}")
done

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

# Guessing suffixes from a prefix has now failed twice — the layflat book only resolved when we
# read the product page's own HTML, which carried the code verbatim. The PDF links to that page;
# pdftotext drops link annotations, so pull the URIs out of the raw PDF and follow them.
echo ""
echo "── Product page links in the PDF"
LINKS=$(python3 - <<'PY'
import re
data = open("medal.pdf", "rb").read()
urls = set()
for m in re.finditer(rb'/URI\s*\((.*?)\)', data, re.S):
    try:
        urls.add(m.group(1).decode("latin-1").strip())
    except Exception:
        pass
for u in sorted(urls):
    if "prodigi" in u.lower():
        print(u)
PY
)
echo "$LINKS"

echo ""
echo "── SKU-shaped strings on those pages"
for url in $LINKS; do
  echo "── $url"
  # Follow redirects; the range sheet links tend to bounce through a short URL.
  if curl -sSL --max-time 30 -o page.html "$url"; then
    grep -oE 'MEDAL[A-Z0-9-]{2,40}' page.html | sort -u | head -40 || echo "   (no MEDAL-shaped strings)"
  else
    echo "   (fetch failed)"
  fi
done

echo ""
echo "── Done. Paste this log back into the session."
