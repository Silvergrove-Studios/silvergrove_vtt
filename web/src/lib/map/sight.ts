// What a viewer sees of a scene, from what the table worked out and sent
// (hexmap/net/web_scene.gd): the places in sight (`visible`), in the dark
// the line of sight (`los`: there only the dark hides things) and the
// darkvision's reach (`dark_sight`), and the cells explored. A cell is in
// sight when its centre is, as the host counts it (Vision.cells_in).
//
// The fog says why a place is hidden: navy is in the line of sight but too
// dark to see, black is out of it (walls, or the edge of sight); a place
// seen before and out of sight now is dimmed. (At a playtest every map was
// black beyond a few hexes, and nobody could say whether it was the dark,
// the walls or a broken map.)
import { cellKey, type Cell, type Grid, type Vec } from '../grid';
import type { Dict } from '../game.svelte';

export type Fog = 'seen' | 'dark' | 'explored' | 'unseen';

const FOG_UNSEEN = 'rgb(8, 8, 13)';
const FOG_GM = 'rgba(13, 13, 31, 0.55)';
const FOG_DIM = 'rgba(8, 8, 13, 0.62)';
const FOG_DARK = 'rgb(17, 24, 52)';
const FOG_DARK_DIM = 'rgba(17, 24, 52, 0.66)';

export function inPolygon(p: Vec, poly: number[][]): boolean {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > p.y !== yj > p.y && p.x < ((xj - xi) * (p.y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export function inAny(p: Vec, polys: number[][][]): boolean {
  return polys.some((poly) => Array.isArray(poly) && poly.length >= 3 && inPolygon(p, poly));
}

/** A test for "is this point in any of these polygons", with each one's
 *  box tried first: in the dark a scene sends many small polygons, and a
 *  phone asks this for every cell and along every wall. */
export function polygonTest(polys: number[][][]): (p: Vec) => boolean {
  const list = polys
    .filter((poly) => Array.isArray(poly) && poly.length >= 3)
    .map((poly) => {
      let x0 = Infinity;
      let y0 = Infinity;
      let x1 = -Infinity;
      let y1 = -Infinity;
      for (const [x, y] of poly) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
      return { poly, x0, y0, x1, y1 };
    });
  return (p) => list.some((b) => p.x >= b.x0 && p.x <= b.x1 && p.y >= b.y0 && p.y <= b.y1 && inPolygon(p, b.poly));
}

/** How the fog covers a cell for the viewer the snapshot was built for.
 *  (`tests`: the snapshot's sight and line of sight as polygonTest, when
 *  asked for many cells.) */
export function fogOf(grid: Grid, scene: Dict, cell: Cell, explored?: Set<string>, tests?: { seen: (p: Vec) => boolean; los: (p: Vec) => boolean }): Fog {
  if (!scene.fog) return 'seen';
  const c = grid.center(cell);
  const seen = tests?.seen ?? ((p: Vec) => inAny(p, (scene.visible as number[][][]) ?? []));
  const los = tests?.los ?? ((p: Vec) => inAny(p, (scene.los as number[][][]) ?? []));
  if (seen(c)) return 'seen';
  const known = (explored ?? new Set<string>((scene.explored as string[]) ?? [])).has(cellKey(cell));
  if (los(c)) return 'dark';
  return known ? 'explored' : 'unseen';
}

/** What a tap on a fogged place says (a player's: "tapping fog says which"). */
export function fogWords(fog: Fog, explored = false): string {
  if (fog === 'dark') return 'Too dark to see there: it is in your line of sight, but unlit. A light, or darkvision, would show it.';
  if (fog === 'explored') return 'Out of sight now: walls are in the way. The map shows it as you last saw it.';
  if (fog === 'unseen') return explored ? 'Out of sight now: walls are in the way.' : 'Out of your sight: walls, or the edge of what you can see, are in the way.';
  return '';
}

/** The fog as paths, worked out once a snapshot: unseen and dimmed as
 *  before, and in the dark what is in sight but unlit (navy; hatched when
 *  the DM sees as a player). The DM gets a light tint over what the
 *  players have not found. */
export interface FogPaths {
  unseen: Path2D;
  dim: Path2D;
  dark: Path2D;
  darkDim: Path2D;
}

export function fogPaths(grid: Grid, scene: Dict, gm: boolean, cellPath: (path: Path2D, cell: Cell) => void): FogPaths | null {
  if (!scene.fog) return null;
  const explored = new Set<string>((scene.explored as string[]) ?? []);
  const tests = { seen: polygonTest((scene.visible as number[][][]) ?? []), los: polygonTest((scene.los as number[][][]) ?? []) };
  const out: FogPaths = { unseen: new Path2D(), dim: new Path2D(), dark: new Path2D(), darkDim: new Path2D() };
  for (const cell of grid.allCells()) {
    const f = fogOf(grid, scene, cell, explored, tests);
    if (f === 'seen') continue;
    const known = explored.has(cellKey(cell));
    // the DM's own view: only what the players have never found
    if (gm) {
      if (!known) cellPath(out.unseen, cell);
      continue;
    }
    if (f === 'dark') cellPath(known ? out.darkDim : out.dark, cell);
    else cellPath(f === 'explored' ? out.dim : out.unseen, cell);
  }
  return out;
}

/** The fog, drawn over the map and under the walls and the tokens (so the
 *  party always shows). `hatch` marks what is in sight but too dark, for
 *  the DM seeing as a player. */
export function drawFog(ctx: CanvasRenderingContext2D, fog: FogPaths | null, size: Vec, gm: boolean, scale: number, hatch = false): void {
  if (!fog) return;
  if (!gm) {
    // the off-map surround is never seen either
    ctx.fillStyle = FOG_UNSEEN;
    const pad = 40;
    ctx.fillRect(-pad, -pad, size.x + pad * 2, pad);
    ctx.fillRect(-pad, size.y, size.x + pad * 2, pad);
    ctx.fillRect(-pad, 0, pad, size.y);
    ctx.fillRect(size.x, 0, pad, size.y);
  }
  ctx.fillStyle = gm ? FOG_GM : FOG_UNSEEN;
  ctx.fill(fog.unseen);
  if (gm) return;
  ctx.fillStyle = FOG_DIM;
  ctx.fill(fog.dim);
  if (!hatch) {
    ctx.fillStyle = FOG_DARK;
    ctx.fill(fog.dark);
    ctx.fillStyle = FOG_DARK_DIM;
    ctx.fill(fog.darkDim);
    return;
  }
  // seen as a player by the DM: the map shows through, hatched
  for (const p of [fog.dark, fog.darkDim]) {
    ctx.save();
    ctx.fillStyle = 'rgba(17, 24, 52, 0.5)';
    ctx.fill(p);
    ctx.clip(p);
    ctx.beginPath();
    const step = Math.max(0.16, 7 / scale);
    for (let d = -size.y; d < size.x + size.y; d += step) {
      ctx.moveTo(d, 0);
      ctx.lineTo(d + size.y, size.y);
    }
    ctx.lineWidth = Math.max(1.2 / scale, 0.015);
    ctx.strokeStyle = 'rgba(150, 170, 255, 0.55)';
    ctx.stroke();
    ctx.restore();
  }
}

/** Darkvision in the dark: what it reaches is seen, not lit — lifted in
 *  grey, as the host's canvas does (MapCanvas.draw_dark_sight), on the map
 *  only (a dwarf's 120 feet reach well past its edge). */
export function drawDarkSight(ctx: CanvasRenderingContext2D, scene: Dict, size: Vec): void {
  const polys = ((scene.dark_sight as number[][][]) ?? []).filter((p) => Array.isArray(p) && p.length >= 3);
  const darkness = Number(scene.darkness ?? 0);
  if (!polys.length || darkness <= 0) return;
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, size.x, size.y);
  ctx.clip();
  ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = `rgba(158, 168, 189, ${0.3 * darkness})`;
  for (const poly of polys) {
    ctx.beginPath();
    poly.forEach((p, i) => (i ? ctx.lineTo(p[0], p[1]) : ctx.moveTo(p[0], p[1])));
    ctx.closePath();
    ctx.fill();
  }
  ctx.restore();
}

/** Why a player doesn't see a creature (WebScene.unseen), in the words the
 *  DM's See as puts beside it. */
export const UNSEEN_WORDS: Record<string, string> = {
  hidden: 'hidden',
  dark: 'too dark',
  walls: 'walls',
  none: 'no eyes here',
};

const UNSEEN_COLORS: Record<string, string> = {
  hidden: 'rgba(255, 255, 255, 0.85)',
  dark: 'rgba(150, 170, 255, 0.95)',
  walls: 'rgba(240, 160, 90, 0.95)',
  none: 'rgba(200, 200, 200, 0.85)',
};

/** The creatures a player can't see, where they are, for the DM seeing as
 *  them: a faint disc, a dashed ring in the colour of the reason and the
 *  reason under it — once for neighbours that share it (three goblins in
 *  a row read "walls walls walls"). `ghosts` are the DM's tokens with `why`. */
export function drawGhosts(ctx: CanvasRenderingContext2D, ghosts: Dict[], scale: number): void {
  ctx.save();
  const said: { x0: number; x1: number; y0: number; y1: number; words: string }[] = [];
  for (const g of ghosts) {
    const p = (g.pos as number[]) ?? [0, 0];
    const x = Number(p[0]);
    const y = Number(p[1]);
    const r = 0.5 * Number(g.size ?? 1) * 0.92;
    const why = String(g.why ?? '');
    const color = UNSEEN_COLORS[why] ?? UNSEEN_COLORS.hidden;
    ctx.globalAlpha = 0.35;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fillStyle = String(g.color ?? '#c0392b');
    ctx.fill();
    ctx.globalAlpha = 1;
    const w = Math.max(r * 0.1, 1.6 / scale);
    ctx.setLineDash([w * 1.8, w * 1.4]);
    ctx.lineWidth = w;
    ctx.strokeStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, r + w, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
    const words = UNSEEN_WORDS[why] ?? why;
    if (words) {
      const fs = 12 / scale;
      ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`;
      const tw = ctx.measureText(words).width;
      const box = { x0: x - tw / 2, x1: x + tw / 2, y0: y + r + w * 2, y1: y + r + w * 2 + fs * 1.2, words };
      const near = said.find((o) => box.x0 < o.x1 + fs && box.x1 > o.x0 - fs && box.y0 < o.y1 && box.y1 > o.y0);
      if (near?.words === words) continue;
      if (near) {
        box.y0 = near.y1;
        box.y1 = box.y0 + fs * 1.2;
      }
      said.push(box);
      ctx.textAlign = 'center';
      ctx.textBaseline = 'top';
      ctx.lineJoin = 'round';
      ctx.lineWidth = fs * 0.3;
      ctx.strokeStyle = 'rgba(0,0,0,0.85)';
      ctx.strokeText(words, x, box.y0);
      ctx.fillStyle = color;
      ctx.fillText(words, x, box.y0);
    }
  }
  ctx.restore();
}

/** The DM's tokens a player can't see, with why (the snapshot's
 *  `preview_why`): what See as draws as ghosts. */
export function ghostsOf(tokens: Dict[], why: Record<string, string>): Dict[] {
  return tokens.filter((t) => why[String(t.id)]).map((t) => ({ ...t, why: why[String(t.id)] }));
}
