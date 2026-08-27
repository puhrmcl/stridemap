# The Etch basemap

Etch's map editions were drawn from Apple Maps snapshots. Apple licenses that data for display
inside an app, not for merchandise, so **five of the thirteen editions render on screen and cannot
be sold** — `StudioEdition.printReady` returns `false` for every `.map` surface. That is the
largest single gate on the catalogue, and no amount of work on the print engine moves it.

The way through is cartography Etch owns: OpenStreetMap data, packaged as a Protomaps basemap,
stored in R2, served by the fulfilment worker, and styled from each edition's own palette.

```
basemap.pmtiles  (R2, one object)
  └─ GET /tiles/{z}/{x}/{y}.mvt        fulfilment/src/tiles.ts — ranged reads, no decoding
       └─ MapLibre + EtchCartography.styleJSON(for: edition)
            └─ the art panel behind a route
```

## Why one file

PMTiles is a single archive with an embedded directory: given z/x/y you compute a byte range and
read just that tile. R2 serves ranged reads natively and egress to a Worker is free, so a
whole-planet basemap costs storage and nothing else — **about $1.80/month for ~120 GB**, which is
less than one framed print. There is no tile server to run, patch or pay for.

The alternative — a regional extract — is cheaper still (~$0.25/month) but puts a coverage cliff
in the product: a race in Tokyo or a hike in Patagonia silently has no map. The planet was chosen
so that never happens.

## Getting the archive into R2

The build is published by Protomaps; you do not generate it.

1. **Download a planet build.** `https://build.protomaps.com/` lists dated builds. Take the most
   recent `.pmtiles`. It is ~120 GB — do this somewhere with room and a real connection.

2. **Upload to the bucket the worker already uses.** R2 needs a multipart upload at this size;
   `rclone` handles it and resumes:

   ```
   rclone copyto ./20260801.pmtiles etch-r2:etch-production-assets/basemap.pmtiles \
     --s3-upload-cutoff=200M --s3-chunk-size=200M --s3-upload-concurrency=4 --progress
   ```

   Configure the `etch-r2` remote as S3-compatible with the R2 endpoint and an API token that has
   Object Read & Write on `etch-production-assets`.

3. **Verify.** Two calls, no app needed:

   ```
   curl -s https://etch-fulfilment.<subdomain>.workers.dev/tiles/tiles.json
   curl -sI https://etch-fulfilment.<subdomain>.workers.dev/tiles/12/655/1583.mvt
   ```

   The first returns TileJSON with the archive's real min/max zoom. The second returns `200` with
   `Content-Type: application/vnd.mapbox-vector-tile`. A `204` means that tile is genuinely empty;
   a `500` means the object is missing or is not a PMTiles v3 archive.

## Staging a new planet build

Never overwrite `basemap.pmtiles` in place. Tiles are served with a one-year immutable cache
precisely because an archive never changes — a build is a new object:

1. Upload as `basemap-2026-09.pmtiles`.
2. Set `BASEMAP_KEY = "basemap-2026-09.pmtiles"` in `wrangler.toml` and deploy.
3. Delete the old object once the new one is verified.

## Attribution

OpenStreetMap is ODbL. **"© OpenStreetMap contributors" has to appear anywhere the map is
published, printed posters included.** It travels in the TileJSON (`EtchCartography.attribution`),
and the poster composition is responsible for putting it on the sheet. This is a licence
condition, not a courtesy — it is the reason this basemap can be sold at all where Apple's cannot.

## What the style does *not* draw

`EtchCartography` builds six layers: land, water, buildings, two weights of road, and optionally
place names. A navigation basemap carries thirty-odd layers because it answers "which turn"; a
poster carries six because it answers "where was this". Transit, POIs, boundaries and landuse
tints are all detail the route would have to compete with.

Labels default to **off**. The composition already states the location in type it controls, and a
second set of names in a font nobody chose is the fastest way to make a print look like a
screenshot.
