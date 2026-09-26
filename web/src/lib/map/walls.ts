// The walls on a map: what kind each is, in the colours the host's map
// canvas gives them (hexmap/render/map_canvas.gd, wall_color), which of
// them a player has seen, and drawing them. The DM sees every wall,
// colour-coded, with a key; a player the walls their characters have seen,
// a secret door as the wall it looks like and no hidden wall at all. (At a
// playtest the DM's map showed no walls, only doors, and the DM couldn't
// tell why a player's screen was black: the walls were the why.)
import { cellKey, type Grid, type Vec } from '../grid';
import type { Dict } from '../game.svelte';
import { polygonTest } from './sight';

export type WallKind = 'wall' | 'door' | 'secret' | 'window' | 'fence' | 'terrain' | 'ethereal' | 'other';

export const WALL_COLORS: Record<WallKind, string> = {
  wall: '#d8d8d8',
  door: '#e0a040',
  secret: '#b070e0',
  window: '#60c8e0',
  fence: '#c8a060',
  terrain: '#70c070',
  ethereal: '#7090ff',
  other: '#909090',
};
const OPEN_DOOR = '#e0d090';

/** The DM's key: each kind, and what it stops. */
export const WALL_KEY: [WallKind, string][] = [
  ['wall', 'wall'],
  ['door', 'door'],
  ['secret', 'secret door'],
  ['window', 'window: seen through'],
  ['fence', 'fence: seen over'],
  ['terrain', 'terrain: seen into, not past'],
  ['ethereal', 'blocks sight only'],
];

/** What a wall is, as the host's map canvas colours it (wall_color). */
export function wallKind(w: Dict): WallKind {
  const door = String(w.door ?? 'none');
  if (door === 'secret') return 'secret';
  if (door === 'door') return 'door';
  const b: Dict = w.blocks && typeof w.blocks === 'object' ? w.blocks : {};
  const move = b.move !== false;
  const sight = b.sight !== false;
  const light = b.light !== false;
  if (move && sight && light) return 'wall';
  if (move && !sight) return b.sound === true ? 'window' : 'fence';
  // (terrain before ethereal: a stream bank blocks sight and not movement too)
  if (String(w.sight_mode ?? 'normal') === 'limited') return 'terrain';
  if (!move && sight) return 'ethereal';
  return 'other';
}

/** The walls a player has seen: one with a point beside it, on either side
 *  and every half hex along it, in their sight now or in a cell they have
 *  explored. Hidden walls never (the chapel's pillars are drawn by their
 *  props). */
export function seenWalls(walls: Dict[], grid: Grid, visible: number[][][], explored: Set<string>): Dict[] {
  const inSight = polygonTest(visible);
  const near = (p: Vec) => inSight(p) || explored.has(cellKey(grid.cellAt(p)));
  return walls.filter((w) => {
    if (w.hidden) return false;
    const pts = ((w.points as number[][]) ?? []).map((p) => ({ x: Number(p[0]), y: Number(p[1]) }));
    for (let i = 0; i + 1 < pts.length; i++) {
      const a = pts[i];
      const b = pts[i + 1];
      const len = Math.hypot(b.x - a.x, b.y - a.y);
      if (len < 1e-9) continue;
      // a nudge off the wall, to either side
      const nx = (-(b.y - a.y) / len) * 0.12;
      const ny = ((b.x - a.x) / len) * 0.12;
      const n = Math.max(1, Math.ceil(len / 0.5));
      for (let k = 0; k <= n; k++) {
        const x = a.x + ((b.x - a.x) * k) / n;
        const y = a.y + ((b.y - a.y) * k) / n;
        if (near({ x: x + nx, y: y + ny }) || near({ x: x - nx, y: y - ny })) return true;
      }
    }
    return false;
  });
}

/** The walls to draw for a viewer: every one for the DM (and for the DM
 *  seeing as a player); for a player the ones they have seen. */
export function wallsFor(lvl: Dict, grid: Grid, scene: Dict, all: boolean): Dict[] {
  const walls = ((lvl.walls as Dict[]) ?? []).filter((w) => Array.isArray(w.points) && w.points.length >= 2);
  if (all) return walls;
  // with no fog every wall is in sight but the hidden ones
  if (!scene.fog) return walls.filter((w) => !w.hidden);
  return seenWalls(walls, grid, (scene.visible as number[][][]) ?? [], new Set<string>((scene.explored as string[]) ?? []));
}

/** Walls, drawn. `dm`: every kind in its colour, secret doors violet, the
 *  hidden and the see-over ones dashed. For a player a secret door is a
 *  plain wall until it is open. */
export function drawWalls(ctx: CanvasRenderingContext2D, walls: Dict[], dm: boolean, scale: number): void {
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (const w of walls) {
    const pts = (w.points as number[][]) ?? [];
    if (pts.length < 2) continue;
    let kind = wallKind(w);
    const open = String(w.state ?? 'closed') === 'open';
    if (!dm && kind === 'secret') kind = open ? 'door' : 'wall';
    if (kind === 'door' || kind === 'secret') {
      drawDoor(ctx, pts, open, kind === 'secret' ? WALL_COLORS.secret : open ? OPEN_DOOR : WALL_COLORS.door, scale);
      continue;
    }
    const dashed = String(w.sight_mode ?? 'normal') === 'limited' || (dm && Boolean(w.hidden));
    const width = Math.max(3 / scale, 0.05);
    ctx.beginPath();
    pts.forEach((p, i) => (i ? ctx.lineTo(Number(p[0]), Number(p[1])) : ctx.moveTo(Number(p[0]), Number(p[1]))));
    if (dashed) ctx.setLineDash([width * 2.2, width * 1.6]);
    ctx.lineWidth = width + 2 / scale;
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    ctx.stroke();
    ctx.lineWidth = width;
    ctx.strokeStyle = WALL_COLORS[kind];
    ctx.stroke();
    ctx.setLineDash([]);
  }
  ctx.restore();
}

/** A door: a thick bar, or its frame's two ends when open. */
function drawDoor(ctx: CanvasRenderingContext2D, pts: number[][], open: boolean, color: string, scale: number): void {
  const a = pts[0].map(Number);
  const b = pts[pts.length - 1].map(Number);
  ctx.lineWidth = Math.max(4 / scale, 0.09);
  ctx.strokeStyle = 'rgba(0,0,0,0.6)';
  ctx.beginPath();
  ctx.moveTo(a[0], a[1]);
  ctx.lineTo(b[0], b[1]);
  ctx.stroke();
  ctx.lineWidth = Math.max(2.5 / scale, 0.055);
  ctx.strokeStyle = color;
  ctx.beginPath();
  if (open) {
    ctx.moveTo(a[0], a[1]);
    ctx.lineTo(a[0] + (b[0] - a[0]) * 0.22, a[1] + (b[1] - a[1]) * 0.22);
    ctx.moveTo(b[0], b[1]);
    ctx.lineTo(b[0] + (a[0] - b[0]) * 0.22, b[1] + (a[1] - b[1]) * 0.22);
  } else {
    ctx.moveTo(a[0], a[1]);
    ctx.lineTo(b[0], b[1]);
  }
  ctx.stroke();
}
