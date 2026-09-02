/**
 * Etch — terrain and imagery tiles, from sources the business may print.
 *
 * The basemap (src/tiles.ts) covers streets, water and buildings, but two editions need what
 * OpenStreetMap doesn't carry: relief and photography. Both exist as US-government open data,
 * which is the whole reason these two routes are proxies rather than purchases:
 *
 *   /terrain/{z}/{x}/{y}.png   Terrarium-encoded elevation tiles from the AWS Open Data
 *                              programme (NASA SRTM + USGS 3DEP and friends). MapLibre reads
 *                              them as a raster-dem source and draws hillshade — real relief
 *                              under the Terrain edition. Free to use; credit the agencies.
 *
 *   /imagery/{z}/{x}/{y}      USGS "USGSImageryOnly" — aerial photography of the United
 *                              States, dominated by USDA NAIP. Public domain as US federal
 *                              work, which makes the Satellite edition *sellable* — the one
 *                              thing Apple's (and Mapbox's, and Google's) imagery never is.
 *
 * Both are proxied instead of hit directly from the app for the same three reasons: the app
 * keeps a single origin to trust; Cloudflare's edge caches each tile so the public services see
 * us once per tile rather than once per customer; and if a source ever moves, the app doesn't.
 */

/** Elevation, Terrarium encoding. z15 is the source's ceiling. */
const TERRAIN_UPSTREAM = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium";
const TERRAIN_MAX_ZOOM = 15;

/** USGS imagery. NAIP resolves well past z16, but z16 is plenty for a street-level poster. */
const IMAGERY_UPSTREAM = "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile";
const IMAGERY_MAX_ZOOM = 16;

/** `/terrain/{z}/{x}/{y}.png` → the three numbers, or null when the path isn't ours. */
export function parseTerrainPath(path: string): { z: number; x: number; y: number } | null {
  return parseZXY(path, /^\/terrain\/(\d+)\/(\d+)\/(\d+)\.png$/, TERRAIN_MAX_ZOOM);
}

/** `/imagery/{z}/{x}/{y}` (optionally `.jpg`) → the three numbers, or null. */
export function parseImageryPath(path: string): { z: number; x: number; y: number } | null {
  return parseZXY(path, /^\/imagery\/(\d+)\/(\d+)\/(\d+)(?:\.jpg)?$/, IMAGERY_MAX_ZOOM);
}

function parseZXY(path: string, pattern: RegExp, maxZoom: number):
    { z: number; x: number; y: number } | null {
  const match = pattern.exec(path);
  if (!match) return null;
  const z = Number(match[1]);
  const x = Number(match[2]);
  const y = Number(match[3]);
  const side = Math.pow(2, z);
  if (z > maxZoom || x >= side || y >= side) return null;
  return { z, x, y };
}

export async function serveTerrain(z: number, x: number, y: number): Promise<Response> {
  return proxied(`${TERRAIN_UPSTREAM}/${z}/${x}/${y}.png`, "image/png");
}

export async function serveImagery(z: number, x: number, y: number): Promise<Response> {
  // ArcGIS tile services order the path z/y/x — row before column.
  return proxied(`${IMAGERY_UPSTREAM}/${z}/${y}/${x}`, "image/jpeg");
}

/**
 * Fetches one upstream tile through Cloudflare's edge cache.
 *
 * `cacheEverything` is what turns a public government tile service into something that can sit
 * behind a storefront: the first request for a tile goes upstream, every later one is served
 * from the edge. A year of TTL is honest — elevation doesn't move, and a poster rendered twice
 * should look the same twice.
 *
 * A miss upstream (ocean, outside US coverage) comes back as 204, which MapLibre reads as
 * "nothing here" rather than an error worth retrying — same contract as the basemap's tiles.
 */
async function proxied(upstream: string, contentType: string): Promise<Response> {
  const response = await fetch(upstream, {
    cf: { cacheEverything: true, cacheTtl: 31536000 },
  } as RequestInit);
  if (!response.ok) return new Response(null, { status: 204 });
  return new Response(response.body, {
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=31536000, immutable",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
