// The art the table draws with: the packs' manifests (sent by the host)
// and their image files (fetched from its web side, /art/<pack>/<file>),
// loaded once and kept. Listeners hear when an image arrives, to redraw.
import { game, type Dict } from './game.svelte';

const images = new Map<string, HTMLImageElement>();
const listeners = new Set<() => void>();

export function onArt(f: () => void): () => void {
  listeners.add(f);
  return () => listeners.delete(f);
}

export function artUrl(pack: string, file: string): string {
  return `/art/${encodeURIComponent(pack)}/${file.split('/').map(encodeURIComponent).join('/')}`;
}

/** An image, once it has loaded (null until then; listeners hear when it does). */
export function image(url: string): HTMLImageElement | null {
  if (!url) return null;
  let img = images.get(url);
  if (!img) {
    img = new Image();
    img.decoding = 'async';
    img.onload = () => listeners.forEach((f) => f());
    img.src = url;
    images.set(url, img);
  }
  return img.complete && img.naturalWidth > 0 ? img : null;
}

export function splitRef(ref: string): [string, string] | null {
  const i = ref.indexOf(':');
  return i > 0 ? [ref.slice(0, i), ref.slice(i + 1)] : null;
}

/** A pack asset's manifest entry ("terrains", "props", "tokens", "pictures", "walls", "lights"). */
export function asset(collection: string, ref: string): Dict | null {
  const parts = splitRef(ref);
  if (!parts) return null;
  const list = (game.packs[parts[0]]?.[collection] as Dict[]) ?? [];
  return list.find((a) => String(a.id) === parts[1]) ?? null;
}

/** Which of a terrain's images a cell of `shape` gets and how it lies (PackLibrary.terrain_art). */
export function terrainArt(ref: string, shape: 'hex' | 'square'): { files: string[]; lay: string } {
  const t = asset('terrains', ref) ?? {};
  let hexSet: string[] = t.textures_hex ?? [];
  const squareSet: string[] = t.textures_square ?? [];
  let raw: string[] = t.textures ?? [];
  let fit = String(t.fit ?? 'cell');
  if (fit === 'hex' && hexSet.length === 0) {
    hexSet = raw;
    raw = [];
  }
  if (fit === 'square') fit = 'tile';
  if (shape === 'square') {
    if (squareSet.length) return { files: squareSet, lay: 'square_box' };
    if (raw.length) return { files: raw, lay: fit === 'tile' ? 'tile' : 'square_box' };
    if (hexSet.length) return { files: hexSet, lay: 'hex_crop' };
  } else {
    if (hexSet.length) return { files: hexSet, lay: 'hex_box' };
    if (raw.length) return { files: raw, lay: fit === 'tile' ? 'tile' : 'hex_box' };
    if (squareSet.length) return { files: squareSet, lay: 'hex_box' };
  }
  return { files: [], lay: 'hex_box' };
}

export function terrainImage(ref: string, variant: number, shape: 'hex' | 'square'): { img: HTMLImageElement | null; url: string; lay: string; color: string } {
  const t = asset('terrains', ref);
  const art = terrainArt(ref, shape);
  const color = String(t?.color ?? '#6b6b6b');
  if (!art.files.length) return { img: null, url: '', lay: art.lay, color };
  const file = art.files[((variant % art.files.length) + art.files.length) % art.files.length];
  const pack = splitRef(ref)![0];
  const url = artUrl(pack, file);
  return { img: image(url), url, lay: art.lay, color };
}

/** A picture's address, for an <img>: the DM's showing, a place, a person. */
export function pictureUrl(ref: string): string {
  const a = asset('pictures', ref);
  const parts = splitRef(ref);
  return a && parts && a.texture ? artUrl(parts[0], String(a.texture)) : '';
}

// The packs' art is SVG: drawing a vector image every frame is slow, so
// each is rasterised once per size bucket (as the host does) and kept.
const BUCKETS = [32, 64, 128, 256, 512, 1024];
const rasters = new Map<string, HTMLCanvasElement>();

export function bucket(px: number): number {
  for (const b of BUCKETS) if (b >= px) return b;
  return BUCKETS[BUCKETS.length - 1];
}

/** An image drawn at about `px` pixels across its width (aspect kept), or null while it loads. */
export function raster(img: HTMLImageElement | null, url: string, px: number): HTMLCanvasElement | HTMLImageElement | null {
  if (!img) return null;
  if (!url.toLowerCase().endsWith('.svg')) return img;
  const b = bucket(px);
  const key = `${url}@${b}`;
  let cv = rasters.get(key);
  if (!cv) {
    const w = b;
    const h = Math.max(1, Math.round((b * img.naturalHeight) / Math.max(1, img.naturalWidth)));
    cv = document.createElement('canvas');
    cv.width = w;
    cv.height = h;
    cv.getContext('2d')!.drawImage(img, 0, 0, w, h);
    rasters.set(key, cv);
  }
  return cv;
}

/** A pack asset's image and its address ("props", "tokens"). */
export function assetArt(collection: string, ref: string): { img: HTMLImageElement | null; url: string } {
  const a = asset(collection, ref);
  const parts = splitRef(ref);
  if (!a || !parts || !a.texture) return { img: null, url: '' };
  const url = artUrl(parts[0], String(a.texture));
  return { img: image(url), url };
}
