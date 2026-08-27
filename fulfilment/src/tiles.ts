/**
 * Etch — the basemap tile server.
 *
 * Etch's map editions were drawn from Apple Maps snapshots, and Apple licenses that imagery for
 * display inside an app, not for merchandise. So six of the thirteen editions render beautifully
 * on screen and cannot be sold — `StudioEdition.printReady` returns false for every one of them.
 * That is the single largest gate on the catalogue, and no amount of work on the print engine
 * moves it. The only way through is cartography Etch owns.
 *
 * The data is OpenStreetMap, packaged as a Protomaps basemap in a single `.pmtiles` archive in
 * R2. PMTiles is one file with an embedded directory: given z/x/y you can compute a byte range
 * and read just that tile. R2 serves ranged reads natively and egress from a Worker is free, so a
 * whole-world basemap costs storage and nothing else — about $1.80 a month for 120 GB, which is
 * less than one framed print.
 *
 * This module turns that archive into the `/tiles/{z}/{x}/{y}.mvt` endpoint MapLibre expects,
 * plus the `/tiles/tiles.json` TileJSON that describes it. Nothing here decodes a tile: the bytes
 * that come out of the archive are exactly the bytes that go to the client. That is what keeps
 * this cheap enough to sit in front of a print render.
 *
 * OpenStreetMap is ODbL. Attribution travels in the TileJSON and belongs on anything published.
 */

export interface TileEnv {
  /** The R2 bucket holding `basemap.pmtiles`. Same bucket as production assets. */
  ASSETS: R2Bucket;
  /** Object key of the archive. Overridable so a new planet build can be staged beside the old. */
  BASEMAP_KEY?: string;
}

const DEFAULT_KEY = "basemap.pmtiles";

/** PMTiles v3 header is a fixed 127 bytes at offset 0. */
const HEADER_BYTES = 127;

interface Header {
  rootDirectoryOffset: number;
  rootDirectoryLength: number;
  /** Where tile bodies begin; entry offsets are relative to this. */
  tileDataOffset: number;
  /** Directory + metadata compression, and tile compression. 1 = none, 2 = gzip. */
  internalCompression: number;
  tileCompression: number;
  minZoom: number;
  maxZoom: number;
}

interface Entry {
  tileID: number;
  offset: number;
  length: number;
  /** 0 means this entry points at a *leaf directory* rather than a tile. */
  runLength: number;
}

/**
 * Reads a byte range out of the archive.
 *
 * These are the whole cost of serving a tile. R2 bills reads per operation, so how many of them a
 * single tile costs is the difference between this basemap costing a couple of dollars a month and
 * costing thirty — see the cache below.
 */
async function readRange(env: TileEnv, offset: number, length: number): Promise<ArrayBuffer> {
  const object = await env.ASSETS.get(archiveKey(env), { range: { offset, length } });
  if (!object) throw new Error(`basemap ${archiveKey(env)} is not in the bucket`);
  return await object.arrayBuffer();
}

function archiveKey(env: TileEnv): string {
  return env.BASEMAP_KEY ?? DEFAULT_KEY;
}

/** Little-endian unsigned 64-bit read. Offsets in a planet-scale archive exceed 32 bits. */
function readUint64(view: DataView, offset: number): number {
  return Number(view.getBigUint64(offset, true));
}

/**
 * What a warm isolate remembers between requests.
 *
 * A PMTiles archive is immutable for its whole life — a new planet build is a new object under a
 * new key, never an edit of this one — so the header and the root directory are constants once
 * read. Fetching them again for every tile was costing three or four R2 reads per tile where one
 * or two would do, which at a hundred thousand sessions a month is the difference between about
 * $8 and about $30.
 *
 * Everything is keyed by the object key, so pointing `BASEMAP_KEY` at a new build invalidates the
 * lot without a deploy dance. A cold isolate simply refills it; nothing here has to survive.
 */
interface ArchiveCache {
  key: string;
  header: Header;
  root: Entry[];
  /** Leaf directories, most recently used last. */
  leaves: Map<string, Entry[]>;
}
let cache: ArchiveCache | null = null;

/**
 * Leaf directories are a few kilobytes each and a planet has thousands, so this is bounded. Runs
 * cluster — the same person's routes, and everyone's races, sit in a handful of metros — so even
 * a small cache catches most of the repeats within a render.
 */
const MAX_LEAVES = 64;

async function archive(env: TileEnv): Promise<ArchiveCache> {
  const key = archiveKey(env);
  if (cache && cache.key === key) return cache;

  const view = new DataView(await readRange(env, 0, HEADER_BYTES));
  // "PMTiles" + version 3.
  const magic = String.fromCharCode(...new Uint8Array(view.buffer, 0, 7));
  if (magic !== "PMTiles") throw new Error("not a PMTiles archive");
  if (view.getUint8(7) !== 3) throw new Error("only PMTiles v3 is supported");
  const header: Header = {
    rootDirectoryOffset: readUint64(view, 8),
    rootDirectoryLength: readUint64(view, 16),
    tileDataOffset: readUint64(view, 40),
    internalCompression: view.getUint8(97),
    tileCompression: view.getUint8(98),
    minZoom: view.getUint8(100),
    maxZoom: view.getUint8(101),
  };

  const rootRaw = await readRange(env, header.rootDirectoryOffset, header.rootDirectoryLength);
  const root = decodeDirectory(await decompress(rootRaw, header.internalCompression));

  cache = { key, header, root, leaves: new Map() };
  return cache;
}

/** A leaf directory, from the cache or from R2. */
async function leafDirectory(
  env: TileEnv, entry: ArchiveCache, offset: number, length: number
): Promise<Entry[]> {
  const id = `${offset}:${length}`;
  const hit = entry.leaves.get(id);
  if (hit) {
    // Re-inserting moves it to the end, which is what makes the eviction below least-recently-used.
    entry.leaves.delete(id);
    entry.leaves.set(id, hit);
    return hit;
  }
  const raw = await readRange(env, offset, length);
  const entries = decodeDirectory(await decompress(raw, entry.header.internalCompression));
  entry.leaves.set(id, entries);
  if (entry.leaves.size > MAX_LEAVES) {
    const oldest = entry.leaves.keys().next();
    if (!oldest.done) entry.leaves.delete(oldest.value);
  }
  return entries;
}

/** Gunzip, when the archive says its directories are compressed. */
async function decompress(buffer: ArrayBuffer, compression: number): Promise<ArrayBuffer> {
  if (compression === 1) return buffer;          // none
  if (compression !== 2) throw new Error(`unsupported compression ${compression}`);
  const stream = new Response(buffer).body!.pipeThrough(new DecompressionStream("gzip"));
  return await new Response(stream).arrayBuffer();
}

/** A varint reader over a byte array, as PMTiles directories are encoded. */
class Varints {
  private position = 0;
  constructor(private readonly bytes: Uint8Array) {}

  next(): number {
    let result = 0;
    let shift = 0;
    for (;;) {
      const byte = this.bytes[this.position++];
      result += (byte & 0x7f) * Math.pow(2, shift);
      if ((byte & 0x80) === 0) return result;
      shift += 7;
    }
  }
}

/**
 * Decodes a directory.
 *
 * The format is four delta-encoded columns — ids, run lengths, lengths, then offsets — which is
 * why this reads the whole directory rather than seeking within it. An offset of 0 means "follows
 * the previous entry", which is how a run of adjacent tiles costs almost nothing to describe.
 */
function decodeDirectory(buffer: ArrayBuffer): Entry[] {
  const varints = new Varints(new Uint8Array(buffer));
  const count = varints.next();
  const entries: Entry[] = new Array(count);

  let id = 0;
  for (let index = 0; index < count; index++) {
    id += varints.next();
    entries[index] = { tileID: id, offset: 0, length: 0, runLength: 0 };
  }
  for (let index = 0; index < count; index++) entries[index].runLength = varints.next();
  for (let index = 0; index < count; index++) entries[index].length = varints.next();
  for (let index = 0; index < count; index++) {
    const value = varints.next();
    if (value === 0 && index > 0) {
      const previous = entries[index - 1];
      entries[index].offset = previous.offset + previous.length;
    } else {
      entries[index].offset = value - 1;
    }
  }
  return entries;
}

/** The last entry whose id is <= the wanted id — directories are sorted, so binary search. */
function findEntry(entries: Entry[], tileID: number): Entry | null {
  let low = 0;
  let high = entries.length - 1;
  while (low <= high) {
    const middle = (low + high) >> 1;
    const entry = entries[middle];
    if (tileID < entry.tileID) high = middle - 1;
    else if (tileID > entry.tileID) low = middle + 1;
    else return entry;
  }
  // Not an exact hit: a run may still cover it.
  if (high >= 0) {
    const candidate = entries[high];
    if (candidate.runLength > 0 && tileID - candidate.tileID < candidate.runLength) return candidate;
    if (candidate.runLength === 0) return candidate;   // a leaf directory to descend into
  }
  return null;
}

/**
 * z/x/y to a Hilbert-curve tile id.
 *
 * PMTiles orders tiles along a Hilbert curve rather than row by row, because neighbours on that
 * curve are neighbours on the map — so panning reads bytes that are already adjacent in the file,
 * and a directory run can describe a whole region. This is the standard conversion.
 */
export function tileID(z: number, x: number, y: number): number {
  if (z === 0) return 0;
  // Every tile in the levels above this one comes first.
  let accumulated = 0;
  for (let level = 0; level < z; level++) accumulated += Math.pow(4, level);

  let rx = 0;
  let ry = 0;
  let position = 0;
  let tx = x;
  let ty = y;
  for (let side = Math.pow(2, z) / 2; side > 0; side = side / 2) {
    rx = (tx & side) > 0 ? 1 : 0;
    ry = (ty & side) > 0 ? 1 : 0;
    position += side * side * ((3 * rx) ^ ry);
    // Rotate the quadrant so the curve stays continuous.
    if (ry === 0) {
      if (rx === 1) {
        tx = side - 1 - tx;
        ty = side - 1 - ty;
      }
      const swap = tx;
      tx = ty;
      ty = swap;
    }
  }
  return accumulated + position;
}

/**
 * Serves one vector tile.
 *
 * A miss is a 204 rather than a 404: an empty tile is a perfectly normal answer over ocean or
 * outside the archive's zoom range, and MapLibre treats it as "nothing here" instead of an error
 * it retries.
 */
export async function serveTile(
  env: TileEnv, z: number, x: number, y: number
): Promise<Response> {
  const archived = await archive(env);
  const header = archived.header;
  if (z < header.minZoom || z > header.maxZoom) return new Response(null, { status: 204 });

  const wanted = tileID(z, x, y);
  // The root is already in memory; only a leaf miss and the tile itself reach R2.
  let entries = archived.root;

  // Root, then at most three levels of leaf directories — deeper than any planet build needs, and
  // bounded so a malformed archive can't spin here.
  for (let depth = 0; depth < 4; depth++) {
    const entry = findEntry(entries, wanted);
    if (!entry) return new Response(null, { status: 204 });

    if (entry.runLength === 0) {
      // A leaf directory: its offset is relative to the root directory's own region.
      entries = await leafDirectory(
        env, archived,
        header.rootDirectoryOffset + header.rootDirectoryLength + entry.offset,
        entry.length
      );
      continue;
    }

    const body = await readRange(env, header.tileDataOffset + entry.offset, entry.length);
    return new Response(body, {
      headers: {
        "Content-Type": "application/vnd.mapbox-vector-tile",
        // Tiles are immutable for the life of an archive: a new planet build is a new object,
        // never an edit of this one. A year is safe and keeps the edge doing the work.
        "Cache-Control": "public, max-age=31536000, immutable",
        // Protomaps archives store gzipped tiles; saying so lets the client inflate them.
        ...(header.tileCompression === 2 ? { "Content-Encoding": "gzip" } : {}),
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
  return new Response(null, { status: 204 });
}

/** TileJSON describing the archive, which is what a MapLibre style's source points at. */
export async function serveTileJSON(env: TileEnv, origin: string): Promise<Response> {
  const header = (await archive(env)).header;
  return new Response(JSON.stringify({
    tilejson: "3.0.0",
    name: "Etch Basemap",
    scheme: "xyz",
    tiles: [`${origin}/tiles/{z}/{x}/{y}.mvt`],
    minzoom: header.minZoom,
    maxzoom: header.maxZoom,
    // ODbL. This has to reach anywhere the map is published, print included.
    attribution: "© OpenStreetMap contributors",
  }), {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

/** `/tiles/{z}/{x}/{y}.mvt` → the three numbers, or null when the path isn't a tile. */
export function parseTilePath(path: string): { z: number; x: number; y: number } | null {
  const match = /^\/tiles\/(\d+)\/(\d+)\/(\d+)(?:\.(?:mvt|pbf))?$/.exec(path);
  if (!match) return null;
  const z = Number(match[1]);
  const x = Number(match[2]);
  const y = Number(match[3]);
  const side = Math.pow(2, z);
  if (z > 22 || x >= side || y >= side) return null;
  return { z, x, y };
}
