// Drawing a scene on a 2D canvas, as the host's map canvas draws it
// (hexmap/render/map_canvas.gd), in its order: background, backdrop,
// terrain, props, darkness, lights, grid, regions, fog, walls, tokens,
// notes. (The tokens over the fog: a player sees the party wherever it
// is.) The world is in hex units; the camera maps them to the screen. The
// backdrop and terrain are drawn once into a cached canvas, and what a
// snapshot decides (the props in order, the fog, the walls, the grid) is
// worked out once per snapshot (`prepare`); the rest is drawn every frame.
import { Grid, INSCRIBED_SQUARE, R, cellKey, keyCell, type Cell, type Vec } from '../grid';
import { asset, assetArt, image, raster, terrainImage } from '../art';
import type { Dict } from '../game.svelte';
import { drawDarkSight, drawFog, drawGhosts, fogPaths, type FogPaths } from './sight';
import { drawWalls, wallsFor } from './walls';

export interface Camera {
  x: number; // the world point at the centre of the view
  y: number;
  scale: number; // css pixels per hex unit
}

export interface Look {
  gm: boolean;
  selected: string;
  /** a token being dragged: drawn where the pointer is */
  dragging: { id: string; pos: Vec } | null;
  /** a pick in progress: the cell under the pointer is lit */
  picking: boolean;
  hoverCell: Cell | null;
  playerColors: Record<string, string>;
  /** the token whose turn it is */
  activeToken: string;
  showGrid: boolean;
  /** the walls drawn (the DM's toggle; on unless said) */
  showWalls?: boolean;
  /** the DM seeing as a player: their snapshot, with what's too dark hatched */
  seeAs?: boolean;
  /** the creatures a player seen as can't see, each with `why` */
  ghosts?: Dict[];
}

/** A creature's outer ring: the side it is on, beside its shape. */
const FOE = '#dc143c';
const FOG_UNSEEN = 'rgb(8, 8, 13)';
const PROP_LAYERS: Record<string, number> = { ground: 0, objects: 1, overhead: 2 };

/** The scene's level with its overrides merged (a door opened, a light put out). */
export function effectiveLevel(map: Dict, scene: Dict): Dict {
  const levels: Dict[] = map.levels ?? [];
  const lvl = levels.find((l) => String(l.id) === String(scene.level ?? '')) ?? levels[0] ?? {};
  const ov: Dict = scene.overrides ?? {};
  const out: Dict = { ...lvl };
  for (const c of ['props', 'walls', 'lights', 'notes']) {
    out[c] = ((lvl[c] as Dict[]) ?? []).map((o) => {
      const o2 = ov[`${c}:${o.id}`];
      return o2 ? { ...o, ...o2 } : o;
    });
  }
  return out;
}

export function tokenPos(t: Dict): Vec {
  const p = (t.pos as number[]) ?? [0, 0];
  return { x: Number(p[0]), y: Number(p[1]) };
}

export function tokenRadius(t: Dict): number {
  return 0.5 * Number(t.size ?? 1) * 0.92;
}

export function pointInPolygon(p: Vec, poly: number[][]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > p.y !== yj > p.y && p.x < ((xj - xi) * (p.y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/** Where a token is drawn, and at what share of its size. */
export interface Placed {
  pos: Vec;
  k: number;
}

/** How far apart two tokens on one cell sit, and how big each is drawn. */
export const FAN_APART = 0.22;
export const FAN_SIZE = 0.62;

/** Where each token is drawn: tokens of size 1 or less on the same cell fan
 *  out — two side by side, three or four round a circle — each smaller
 *  (in a playtest two tokens drawn one on the other were one to see, and a
 *  tap went to the one underneath). `skip` (a token being dragged) stays
 *  where it is. By token id; a token alone is drawn where it stands. */
export function layout(tokens: Dict[], grid: Grid, skip = ''): Map<string, Placed> {
  const out = new Map<string, Placed>();
  const cells = new Map<string, Dict[]>();
  for (const t of tokens) {
    const id = String(t.id);
    if (Number(t.size ?? 1) > 1 || id === skip) {
      out.set(id, { pos: tokenPos(t), k: 1 });
      continue;
    }
    const key = cellKey(grid.cellAt(tokenPos(t)));
    const here = cells.get(key);
    if (here) here.push(t);
    else cells.set(key, [t]);
  }
  for (const here of cells.values()) {
    if (here.length === 1) {
      out.set(String(here[0].id), { pos: tokenPos(here[0]), k: 1 });
      continue;
    }
    // round where they stand (a cell's centre, on a map with a grid)
    const mid = here.reduce((m, t) => ({ x: m.x + tokenPos(t).x / here.length, y: m.y + tokenPos(t).y / here.length }), { x: 0, y: 0 });
    here.forEach((t, i) => {
      let off: Vec;
      if (here.length === 2) off = { x: i === 0 ? -FAN_APART : FAN_APART, y: 0 };
      else {
        const a = -Math.PI / 2 + (here.length === 4 ? Math.PI / 4 : 0) + (i * 2 * Math.PI) / here.length;
        off = { x: Math.cos(a) * FAN_APART * 1.1, y: Math.sin(a) * FAN_APART * 1.1 };
      }
      out.set(String(t.id), { pos: { x: mid.x + off.x, y: mid.y + off.y }, k: FAN_SIZE });
    });
  }
  return out;
}

/** The token under a point: within its own radius or `least` (a reach on
 *  screen, in map units: a small map's tokens are a few pixels across, and a
 *  playtest's DM panned the map trying to drag the party), the nearest first;
 *  where `placed` (layout) draws it. */
export function tokenAt(tokens: Dict[], p: Vec, least = 0, placed?: Map<string, Placed>): Dict | null {
  let best: Dict | null = null;
  let bestD = Infinity;
  for (let i = tokens.length - 1; i >= 0; i--) {
    const t = tokens[i];
    const at = placed?.get(String(t.id));
    const c = at?.pos ?? tokenPos(t);
    const d = Math.hypot(c.x - p.x, c.y - p.y);
    if (d <= Math.max(tokenRadius(t) * (at?.k ?? 1), least) && d < bestD) {
      best = t;
      bestD = d;
    }
  }
  return best;
}

/** The layer tree's order and visibility: {ref: [index, visible]} (LayerTree.order / effective). */
function layerTree(lvl: Dict): Map<string, [number, boolean]> {
  const out = new Map<string, [number, boolean]>();
  let i = 0;
  const walk = (nodes: Dict[], visible: boolean) => {
    for (const n of nodes ?? []) {
      const v = visible && n.visible !== false;
      if (Array.isArray(n.children)) walk(n.children, v);
      else out.set(String(n.ref), [i++, v]);
    }
  };
  if (Array.isArray(lvl.tree)) walk(lvl.tree, true);
  return out;
}

// --------------------------------------------------------------- prepare --

/** What a snapshot decides, worked out once: the grid, the level, the props
 *  in order, the fog and the grid's outline as paths, the walls to draw. */
export interface Prepared {
  grid: Grid;
  lvl: Dict;
  props: Dict[];
  gridPath: Path2D;
  fog: FogPaths | null;
  walls: Dict[];
}

function cellPath(path: Path2D, grid: Grid, cell: Cell, grow = 1): void {
  const c = grid.center(cell);
  grid.cornersAt(c).forEach((p, i) => {
    const x = c.x + (p.x - c.x) * grow;
    const y = c.y + (p.y - c.y) * grow;
    if (i) path.lineTo(x, y);
    else path.moveTo(x, y);
  });
  path.closePath();
}

/** `allWalls`: every wall drawn (the DM's, and the DM seeing as a player);
 *  otherwise a player's, the ones they have seen. */
export function prepare(map: Dict, scene: Dict, gm: boolean, allWalls = gm): Prepared {
  const grid = new Grid(map.grid ?? {});
  const lvl = effectiveLevel(map, scene);
  const tree = layerTree(lvl);
  const props = ((lvl.props as Dict[]) ?? [])
    .map((p, i) => ({ p, i, t: tree.get(`props:${p.id}`) }))
    .filter(({ p, t }) => (t ? t[1] : true) && (gm || !p.hidden))
    .sort((a, b) => {
      if (a.t && b.t) return a.t[0] - b.t[0];
      const la = PROP_LAYERS[String(asset('props', String(a.p.asset ?? ''))?.layer ?? 'objects')] ?? 1;
      const lb = PROP_LAYERS[String(asset('props', String(b.p.asset ?? ''))?.layer ?? 'objects')] ?? 1;
      return la - lb || a.i - b.i;
    })
    .map(({ p }) => p);
  const gridPath = new Path2D();
  for (const cell of grid.allCells()) cellPath(gridPath, grid, cell);
  // (Vision.cells_in: a cell is seen when its centre is in sight)
  const fog = fogPaths(grid, scene, gm, (path, cell) => cellPath(path, grid, cell, 1.02));
  return { grid, lvl, props, gridPath, fog, walls: wallsFor(lvl, grid, scene, allWalls) };
}

// ------------------------------------------------------------- terrain --

export interface TerrainCache {
  canvas: HTMLCanvasElement;
  res: number; // canvas pixels per hex unit
  pad: number; // hex units around the map
  pending: boolean; // images still loading: draw again when they come
}

/** Pixels per hex unit for a map's cached terrain: sharp, but within what a phone's canvas allows. */
export function terrainRes(size: Vec, pad: number): number {
  const area = (size.x + pad * 2) * (size.y + pad * 2);
  return Math.max(16, Math.min(128, Math.floor(Math.sqrt(8e6 / Math.max(1, area)))));
}

/** The backdrop and terrain of a level, drawn once. */
export function drawTerrain(map: Dict, lvl: Dict, grid: Grid, mapFileUrl: (file: string) => string): TerrainCache {
  const size = grid.size();
  const pad = 0.5;
  const res = terrainRes(size, pad);
  const cv = document.createElement('canvas');
  cv.width = Math.max(1, Math.ceil((size.x + pad * 2) * res));
  cv.height = Math.max(1, Math.ceil((size.y + pad * 2) * res));
  const ctx = cv.getContext('2d')!;
  let pending = false;
  ctx.setTransform(res, 0, 0, res, pad * res, pad * res);
  // the level's backdrop: an image the map brought with it
  const b = lvl.backdrop as Dict | undefined;
  if (b && !b.hidden && String(b.image ?? '').startsWith('local:')) {
    const img = image(mapFileUrl(String(b.image).slice(6)));
    if (img) {
      const pos = (b.pos as number[]) ?? [0, 0];
      const bs = (b.size as number[]) ?? [size.x, size.y];
      ctx.globalAlpha = Number(b.opacity ?? 1);
      ctx.drawImage(img, pos[0], pos[1], bs[0], bs[1]);
      ctx.globalAlpha = 1;
    } else pending = true;
  }
  const shape = grid.square ? 'square' : 'hex';
  // `rot` is in sixths of a turn on hexes, quarters on squares
  const rotStep = grid.square ? Math.PI / 2 : Math.PI / 3;
  const terrain: Dict = lvl.terrain ?? {};
  for (const key of Object.keys(terrain)) {
    const t = terrain[key] as Dict;
    const c = grid.center(keyCell(key));
    const ref = String(t.t ?? '');
    const known = asset('terrains', ref) != null;
    const art = terrainImage(ref, Number(t.v ?? 0), shape);
    ctx.save();
    ctx.beginPath();
    // (a hair wider, so neighbours leave no seam)
    grid.cornersAt(c).forEach((p, i) => {
      const x = c.x + (p.x - c.x) * 1.015;
      const y = c.y + (p.y - c.y) * 1.015;
      if (i) ctx.lineTo(x, y);
      else ctx.moveTo(x, y);
    });
    ctx.closePath();
    const img = raster(art.img, art.url, res * 1.25 * (art.lay === 'hex_crop' ? 1 / INSCRIBED_SQUARE : art.lay === 'tile' ? 2 : 1));
    if (!img) {
      ctx.fillStyle = known ? art.color : '#7a2a4a';
      ctx.fill();
      if (known && art.url) pending = true;
      ctx.restore();
      continue;
    }
    ctx.clip();
    // The same image placement as the host's UVs: the image is laid in a
    // frame turned by the cell's rotation.
    let ang = Number(t.rot ?? 0) * rotStep;
    ctx.translate(c.x, c.y);
    if (art.lay === 'tile') {
      // cut out of a texture that repeats every two cells, in place
      ctx.rotate(-ang);
      ctx.translate(-c.x, -c.y);
      const pat = ctx.createPattern(img, 'repeat');
      if (pat) {
        pat.setTransform(new DOMMatrix().scale(2 / img.width, 2 / img.height));
        ctx.fillStyle = pat;
        ctx.fillRect(c.x - 1, c.y - 1, 2, 2);
      }
    } else if (art.lay === 'square_box') {
      ctx.rotate(-ang);
      ctx.drawImage(img, -0.5, -0.5, 1, 1);
    } else if (art.lay === 'hex_crop') {
      // hex art on a square cell: the square inside the hexagon
      const k = INSCRIBED_SQUARE;
      ctx.rotate(-ang);
      ctx.drawImage(img, -0.5 / k, -R / k, 1 / k, (2 * R) / k);
    } else {
      // the hex's bounding box (in pointy-top space) is the image
      if (!grid.pointy) ang -= Math.PI / 6;
      ctx.rotate(-ang);
      ctx.drawImage(img, -0.5, -R, 1, 2 * R);
    }
    ctx.restore();
  }
  return { canvas: cv, res, pad, pending };
}

// ----------------------------------------------------------------- frame --

export interface Frame {
  ctx: CanvasRenderingContext2D;
  width: number; // css pixels
  height: number;
  dpr: number;
  cam: Camera;
  map: Dict;
  scene: Dict;
  prep: Prepared;
  terrain: TerrainCache | null;
  look: Look;
}

export function drawFrame(f: Frame): void {
  const { ctx, width, height, dpr, cam, map, scene, prep, look } = f;
  const { grid, lvl } = prep;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = '#101216';
  ctx.fillRect(0, 0, width, height);
  // world → screen
  const s = cam.scale * dpr;
  ctx.setTransform(s, 0, 0, s, (width / 2 - cam.x * cam.scale) * dpr, (height / 2 - cam.y * cam.scale) * dpr);
  const size = grid.size();
  const fog = Boolean(scene.fog);
  // background: under a player's fog, even the gaps between the edge cells are unseen
  ctx.save();
  if (!(fog && !look.gm)) {
    ctx.shadowColor = 'rgba(0,0,0,0.5)';
    ctx.shadowBlur = 28 * dpr;
    ctx.shadowOffsetY = 6 * dpr;
  }
  ctx.fillStyle = fog && !look.gm ? FOG_UNSEEN : String(map.style?.background ?? '#1c1a17');
  ctx.fillRect(0, 0, size.x, size.y);
  ctx.restore();
  if (f.terrain) {
    const t = f.terrain;
    ctx.drawImage(t.canvas, -t.pad, -t.pad, t.canvas.width / t.res, t.canvas.height / t.res);
  }
  drawProps(ctx, prep.props, cam.scale * dpr);
  const darkness = Number(scene.darkness ?? lvl.darkness ?? 0);
  if (darkness > 0) {
    ctx.fillStyle = `rgba(5, 5, 15, ${darkness * 0.85})`;
    ctx.fillRect(-3, -3, size.x + 6, size.y + 6);
  }
  drawLights(ctx, (scene.lights as Dict[]) ?? []);
  drawDarkSight(ctx, scene, size);
  // (a map painted as a picture — a region — may draw no grid at all)
  if (look.showGrid && map.style?.show_grid !== false) {
    ctx.strokeStyle = String(map.style?.grid_color ?? '#00000066');
    ctx.lineWidth = Math.max(1 / cam.scale, Number(map.style?.grid_width ?? 0.012));
    ctx.stroke(prep.gridPath);
  }
  drawRegions(ctx, grid, scene, look.gm, cam.scale);
  drawSeen(ctx, prep, look, size, cam.scale);
  const tokens = (scene.tokens as Dict[]) ?? [];
  // (labels come as the host works them out over every token: GW1, GW2)
  const placed = layout(tokens, grid, look.dragging?.id ?? '');
  for (const t of tokens) {
    const drag = look.dragging && look.dragging.id === t.id ? look.dragging.pos : null;
    const at = placed.get(String(t.id));
    drawToken(ctx, t, drag ?? at?.pos ?? tokenPos(t), look, cam.scale, dpr, drag ? 1 : (at?.k ?? 1));
  }
  drawNameTags(ctx, tokens, look, cam.scale, placed);
  if (look.gm) drawNotes(ctx, lvl, cam.scale);
  if (look.hoverCell && look.picking) {
    const path = new Path2D();
    cellPath(path, grid, look.hoverCell);
    ctx.fillStyle = 'rgba(255, 215, 90, 0.25)';
    ctx.fill(path);
    ctx.lineWidth = 2 / cam.scale;
    ctx.strokeStyle = 'rgba(255, 215, 90, 0.95)';
    ctx.stroke(path);
  }
}

function drawProps(ctx: CanvasRenderingContext2D, props: Dict[], pxPerUnit: number): void {
  for (const p of props) {
    const def = asset('props', String(p.asset ?? ''));
    if (!def) continue;
    const sc = Number(p.scale ?? 1);
    const sz = (def.size as number[]) ?? [1, 1];
    const w = Number(sz[0]) * sc;
    const h = Number(sz[1]) * sc;
    const art = assetArt('props', String(p.asset ?? ''));
    const img = raster(art.img, art.url, w * pxPerUnit);
    if (!img) continue;
    const pos = (p.pos as number[]) ?? [0, 0];
    const anchor = (def.anchor as number[]) ?? [0.5, 0.5];
    ctx.save();
    ctx.globalAlpha = p.hidden ? 0.55 : 1;
    ctx.translate(Number(pos[0]), Number(pos[1]));
    ctx.rotate((Number(p.rot ?? 0) * Math.PI) / 180);
    if (p.flip) ctx.scale(-1, 1);
    ctx.drawImage(img, -anchor[0] * w, -anchor[1] * h, w, h);
    ctx.restore();
  }
}

/** Lights: the host's radial fall-off inside the polygon each light reaches, added together. */
function drawLights(ctx: CanvasRenderingContext2D, lights: Dict[]): void {
  ctx.save();
  ctx.globalCompositeOperation = 'lighter';
  for (const l of lights) {
    const poly = l.polygon as number[][];
    if (!poly || poly.length < 3) continue;
    const [x, y] = (l.pos as number[]).map(Number);
    const bright = Number(l.bright ?? 0);
    const outer = Math.max(bright, Number(l.dim ?? 0));
    if (outer <= 0) continue;
    const color = String(l.color ?? '#ffb060');
    const intensity = Number(l.intensity ?? 1);
    ctx.save();
    ctx.beginPath();
    poly.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
    ctx.closePath();
    ctx.clip();
    fan(ctx, x, y, outer, color, 0.3 * intensity);
    if (bright > 0) fan(ctx, x, y, Math.min(bright, outer), color, 0.45 * intensity);
    ctx.restore();
  }
  ctx.restore();
}

function fan(ctx: CanvasRenderingContext2D, x: number, y: number, r: number, color: string, a: number): void {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, hexA(color, a));
  g.addColorStop(0.35, hexA(color, a * 0.55));
  g.addColorStop(1, hexA(color, 0));
  ctx.fillStyle = g;
  ctx.fillRect(x - r, y - r, r * 2, r * 2);
}

/** Zones and tagged cells, and a template being shown; players do not see the DM's own. */
function drawRegions(ctx: CanvasRenderingContext2D, grid: Grid, scene: Dict, gm: boolean, scale: number): void {
  const regions: Dict = scene.regions ?? {};
  const list: Dict[] = Object.keys(regions)
    .sort()
    .map((id) => regions[id] as Dict)
    .filter((r) => gm || r.audience !== 'gm');
  const hl = scene.highlight as Dict | undefined;
  if (hl && Array.isArray(hl.cells)) list.push({ ...hl, color: hl.color ?? '#ffffff', alpha: 0.35 });
  for (const r of list) {
    const color = String(r.color ?? '#ffb060');
    const alpha = Number(r.alpha ?? 0.22);
    const path = new Path2D();
    const cells = ((r.cells as string[]) ?? []).filter((k) => typeof k === 'string');
    for (const key of cells) cellPath(path, grid, keyCell(key));
    ctx.fillStyle = hexA(color, alpha);
    ctx.fill(path);
    ctx.lineWidth = Math.max(1 / scale, 0.02);
    ctx.strokeStyle = hexA(color, alpha * 2);
    ctx.stroke(path);
    if (r.label && cells.length) {
      const c = grid.center(keyCell(cells[0]));
      const fs = Math.max(10 / scale, 0.22);
      ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillStyle = 'rgba(255,255,255,0.9)';
      ctx.fillText(String(r.label), c.x, c.y);
    }
  }
}

/** What the viewer sees, and why not: the fog (navy where it is too dark,
 *  black where walls are in the way; hatched when the DM sees as a player),
 *  the walls (every kind for the DM, the ones a player has seen), and for the
 *  DM seeing as a player the creatures that player can't see. Under the
 *  tokens: the party shows wherever it is. The DM's Walls off leaves the
 *  doors, as the map had them before (a door is something to open). */
function drawSeen(ctx: CanvasRenderingContext2D, prep: Prepared, look: Look, size: Vec, scale: number): void {
  drawFog(ctx, prep.fog, size, look.gm, scale, look.seeAs === true);
  const walls = look.showWalls === false ? prep.walls.filter((w) => String(w.door ?? 'none') === 'door' && !w.hidden) : prep.walls;
  drawWalls(ctx, walls, look.gm || look.seeAs === true, scale);
  if (look.ghosts?.length) drawGhosts(ctx, look.ghosts, scale);
}

/** The DM's notes on the map: a yellow pin and its title. */
function drawNotes(ctx: CanvasRenderingContext2D, lvl: Dict, scale: number): void {
  for (const n of (lvl.notes as Dict[]) ?? []) {
    const [x, y] = ((n.pos as number[]) ?? [0, 0]).map(Number);
    const r = Math.max(5 / scale, 0.12);
    ctx.beginPath();
    ctx.arc(x, y, r + 2 / scale, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(0,0,0,0.7)';
    ctx.fill();
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = '#f0d060';
    ctx.fill();
    const title = String(n.title ?? '');
    if (title) {
      const fs = 12 / scale;
      ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.lineWidth = fs * 0.25;
      ctx.strokeStyle = 'rgba(0,0,0,0.8)';
      ctx.strokeText(title, x + r * 1.5, y);
      ctx.fillStyle = '#fff';
      ctx.fillText(title, x + r * 1.5, y);
    }
  }
}

/** A token: a disc in its colour (or its art, clipped round), a ring in its
 *  owner's colour, its label; `k` of its size (layout). Its side is marked,
 *  not by colour alone: a creature has a crimson ring outside, notched at
 *  the top, the party a white halo round their own colour (in a playtest a
 *  player's red ring read as a goblin's). */
export function drawToken(ctx: CanvasRenderingContext2D, t: Dict, pos: Vec, look: Look, scale: number, dpr = 1, k = 1): void {
  const r = tokenRadius(t) * k;
  const hidden = Boolean(t.hidden);
  const alpha = hidden ? 0.5 : 1;
  const tags: string[] = Array.isArray(t.tags) ? (t.tags as string[]) : [];
  const ring = t.owner ? look.playerColors[String(t.owner)] ?? '#ffffff' : '#ffffff';
  const rot = (Number(t.rot ?? 0) * Math.PI) / 180;
  const ringW = Math.max(r * 0.09, 1.5 / scale);
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.beginPath();
  ctx.arc(pos.x + r * 0.06, pos.y + r * 0.08, r, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.fill();
  const art = t.art ? assetArt('tokens', String(t.art)) : null;
  const img = art ? raster(art.img, art.url, r * 2 * scale * dpr) : null;
  ctx.beginPath();
  ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2);
  if (img) {
    ctx.save();
    ctx.clip();
    ctx.translate(pos.x, pos.y);
    ctx.rotate(rot);
    ctx.drawImage(img, -r, -r, r * 2, r * 2);
    ctx.restore();
  } else {
    ctx.fillStyle = String(t.color ?? '#c0392b');
    ctx.fill();
    const label = String(t.label ?? '');
    if (label) {
      const fs = label.length <= 2 ? r * 0.9 : r * 0.6;
      ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.lineWidth = Math.max(fs * 0.12, 2 / scale);
      ctx.strokeStyle = 'rgba(0,0,0,0.8)';
      ctx.strokeText(label, pos.x, pos.y + fs * 0.05);
      ctx.fillStyle = '#fff';
      ctx.fillText(label, pos.x, pos.y + fs * 0.05);
    }
  }
  ctx.beginPath();
  ctx.arc(pos.x, pos.y, r - ringW / 2, 0, Math.PI * 2);
  ctx.lineWidth = ringW + 1.5 / scale;
  ctx.strokeStyle = 'rgba(0,0,0,0.6)';
  ctx.stroke();
  ctx.lineWidth = ringW;
  ctx.strokeStyle = ring;
  ctx.stroke();
  if (t.actor && !t.owner) {
    // a creature: crimson outside, and a notch at the top
    const out = r + ringW * 0.75;
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, out, 0, Math.PI * 2);
    ctx.lineWidth = ringW * 1.2 + 1.5 / scale;
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.stroke();
    ctx.lineWidth = ringW * 1.2;
    ctx.strokeStyle = FOE;
    ctx.stroke();
    const w = ringW * 1.3;
    ctx.beginPath();
    ctx.moveTo(pos.x - w, pos.y - out);
    ctx.lineTo(pos.x, pos.y - out - ringW * 2.2);
    ctx.lineTo(pos.x + w, pos.y - out);
    ctx.closePath();
    ctx.fillStyle = FOE;
    ctx.fill();
    ctx.lineWidth = Math.max(ringW * 0.3, 1 / scale);
    ctx.strokeStyle = 'rgba(0,0,0,0.6)';
    ctx.stroke();
  } else if (t.owner) {
    // the party: its own colour, haloed in white
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r + ringW * 0.55, 0, Math.PI * 2);
    ctx.lineWidth = ringW * 0.6;
    ctx.strokeStyle = 'rgba(255,255,255,0.92)';
    ctx.stroke();
  }
  // what everyone can see of its state (the ruleset's tags): bloodied, down, dead
  if (tags.includes('dead') || tags.includes('down')) {
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2);
    ctx.fillStyle = tags.includes('dead') ? 'rgba(10,10,12,0.62)' : 'rgba(10,10,12,0.4)';
    ctx.fill();
    if (tags.includes('dead')) {
      const k = r * 0.5;
      ctx.beginPath();
      ctx.moveTo(pos.x - k, pos.y - k);
      ctx.lineTo(pos.x + k, pos.y + k);
      ctx.moveTo(pos.x + k, pos.y - k);
      ctx.lineTo(pos.x - k, pos.y + k);
      ctx.lineWidth = Math.max(r * 0.14, 2 / scale);
      ctx.strokeStyle = 'rgba(235,235,235,0.9)';
      ctx.stroke();
    }
  } else if (tags.includes('bloodied')) {
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r * 0.8, 0, Math.PI * 2);
    ctx.lineWidth = Math.max(r * 0.07, 1.5 / scale);
    ctx.strokeStyle = 'rgba(214,48,49,0.9)';
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(pos.x + r * 0.7, pos.y - r * 0.7, r * 0.22, 0, Math.PI * 2);
    ctx.fillStyle = '#d63031';
    ctx.fill();
    ctx.lineWidth = Math.max(r * 0.05, 1 / scale);
    ctx.strokeStyle = 'rgba(0,0,0,0.7)';
    ctx.stroke();
  }
  if (Math.abs(Number(t.rot ?? 0)) > 0.01) {
    // which way it faces
    const dx = Math.cos(rot - Math.PI / 2);
    const dy = Math.sin(rot - Math.PI / 2);
    ctx.beginPath();
    ctx.moveTo(pos.x + dx * r * 0.75, pos.y + dy * r * 0.75);
    ctx.lineTo(pos.x + dx * (r + ringW), pos.y + dy * (r + ringW));
    ctx.strokeStyle = '#fff';
    ctx.stroke();
  }
  ctx.restore();
  if (hidden && look.gm) {
    // the DM's reminder that players cannot see it
    ctx.save();
    ctx.setLineDash([ringW * 1.6, ringW * 1.6]);
    ctx.lineWidth = ringW;
    ctx.strokeStyle = 'rgba(255,255,255,0.7)';
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r + ringW * 1.2, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }
  if (look.activeToken && look.activeToken === t.id) {
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r + ringW * 2.2, 0, Math.PI * 2);
    ctx.lineWidth = ringW * 1.2;
    ctx.strokeStyle = '#ffd75a';
    ctx.stroke();
  }
  if (look.selected && look.selected === t.id) {
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r + ringW * 3.6, 0, Math.PI * 2);
    ctx.lineWidth = ringW;
    ctx.strokeStyle = 'rgba(255, 255, 77, 0.9)';
    ctx.stroke();
  }
}

/** The names under the places on a regional map and under the party, so the
 *  map reads without clicking every marker (about 13 px on screen), each
 *  moved down clear of any it would cover (a playtest's DM read "The
 *  partyuined chapel" where the party stood at the chapel). */
function drawNameTags(ctx: CanvasRenderingContext2D, tokens: Dict[], look: Look, scale: number, spots?: Map<string, Placed>): void {
  const fs = 13 / scale;
  ctx.save();
  ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.lineJoin = 'round';
  ctx.lineWidth = fs * 0.3;
  const placed: { x0: number; x1: number; y0: number; y1: number }[] = [];
  // places first: the party's name gives way to the place it stands at
  const named = tokens
    .filter((t) => {
      const tags: string[] = Array.isArray(t.tags) ? (t.tags as string[]) : [];
      return (tags.includes('place') || tags.includes('party')) && t.name && !(t.hidden && !look.gm);
    })
    .sort((a, b) => Number(((b.tags as string[]) ?? []).includes('place')) - Number(((a.tags as string[]) ?? []).includes('place')));
  for (const t of named) {
    const at = spots?.get(String(t.id));
    const dragged = look.dragging && look.dragging.id === t.id;
    const pos = dragged ? look.dragging!.pos : (at?.pos ?? tokenPos(t));
    const r = tokenRadius(t) * (dragged ? 1 : (at?.k ?? 1));
    const w = ctx.measureText(String(t.name)).width;
    let y = pos.y + r + Math.max(r * 0.09, 1.5 / scale) * 2;
    for (let tries = 0; tries < 4; tries++) {
      const box = { x0: pos.x - w / 2, x1: pos.x + w / 2, y0: y, y1: y + fs * 1.15 };
      if (!placed.some((o) => box.x0 < o.x1 && box.x1 > o.x0 && box.y0 < o.y1 && box.y1 > o.y0)) break;
      y += fs * 1.2;
    }
    placed.push({ x0: pos.x - w / 2, x1: pos.x + w / 2, y0: y, y1: y + fs * 1.15 });
    ctx.globalAlpha = t.hidden ? 0.5 : 1;
    ctx.strokeStyle = 'rgba(0,0,0,0.85)';
    ctx.strokeText(String(t.name), pos.x, y);
    ctx.fillStyle = '#fff';
    ctx.fillText(String(t.name), pos.x, y);
  }
  ctx.restore();
}

export function hexA(hex: string, a: number): string {
  let h = hex.replace('#', '');
  if (h.length === 3 || h.length === 4) h = h.split('').map((c) => c + c).join('');
  const n = parseInt(h.slice(0, 6), 16);
  const k = h.length === 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1;
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${Math.max(0, Math.min(1, a * k))})`;
}
