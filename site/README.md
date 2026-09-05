# Northwest Ag Technologies — website

Two pages, one project:

| Route | Site |
|---|---|
| `/` | Northwest Ag Technologies |
| `/verde-house` | Verde House |

## Running it

    npm install
    npm run dev       # http://localhost:4321 — edits show up instantly
    npm run build     # writes dist/ and refreshes the preview copies in ../web/

## Why Astro and not Next.js

`PLATFORM.md` §2B puts web work on Next.js. That lane is for apps with sign-in and
a database — NestEgg's shape. This site has neither, so it ships as plain HTML and
CSS with no JavaScript sent to the browser at all. The handbook rule worth adding:
**marketing sites use Astro; anything with auth or a database uses Next.js.**

Hosting is unchanged — Vercel, same as NestEgg, so it stays one dashboard and one
billing relationship.

## Deploying

In Vercel, import this repository and set **Root Directory** to `site`. Everything
else is detected: framework Astro, build `npm run build`, output `dist`.

Then add the domains. `nwagtech.com` points at the project root. If Verde House
gets its own domain later, add it in Vercel and rewrite `/` to `/verde-house` —
no code change.

## Editing content

Prose lives in the page files. The two lists that actually change are data:

    src/data/companies.ts    the operating companies on the NWAT page
    src/data/products.ts     Verde House's portfolio

Add a third company and the grid takes it with no layout change. When Work grows
into real case studies, move `products.ts` to an Astro content collection.

## Brand assets

Logos are inlined as Astro components so they inherit the page's theme colours —
that is why the NWAT wordmark flips from charcoal to warm white on a dark
background. The source files live in `../brand/nwagtech/svg` and
`../brand/verde-house/svg`.

Type is Archivo and Newsreader from Google Fonts. NWAT's display face should be
**Norwester Bold Italic**, which is not on the Google Fonts CDN — Archivo
condensed italic stands in until the font file is self-hosted in `public/fonts/`.

## Known gaps

- NestEgg and Etch need one line each; they render with a visible marker until then.
- "100,000+ acres annually" and "9 states" came from the former full-service site
  and may overstate the contract-labor business.
