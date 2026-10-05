// A template's shape on the map, as the host's MapQuery.template lays one
// (hexmap/rules/map_query.gd), so a spell's preview covers the cells its cast
// would: a circle round a point (or round a creature, its size added), a cone
// or a line out from a point or from a creature's edge, a square — a cell is
// in it when its middle is. And who it would catch, of the creatures a
// screen shows: a screen is never sent one it may not see, so a preview
// never tells of a hidden creature.
import { Grid, cellKey, type Cell, type Vec } from '../grid';
import type { Dict } from '../game.svelte';
import { isDead, isObject, tokenPos } from './render';

export type ShapeType = 'circle' | 'cone' | 'line' | 'square';

/** A template's shape, in hex units (a mark's `shape`). */
export interface Shape {
  type: ShapeType;
  /** a circle's radius, a cone's or a line's length, a square's side */
  size: number;
  /** a line's width */
  width?: number;
  /** a cone's angle, in degrees (53 by default: as wide at its end as it is long) */
  angle?: number;
  /** from a creature: "edge" starts a cone, a line or a square at its edge */
  origin?: 'edge' | 'center';
  /** round a creature: whether the creature is in it (an emanation leaves it out) */
  include_self?: boolean;
}

/** Where a template is: its place (a point, hex units), which way it goes
 *  (degrees, 0 east, clockwise on the screen), and the creature it goes out
 *  from or round (its size: 0 at a point). */
export interface Placement {
  at: Vec;
  direction: number;
  fromSize: number;
}

/** GDScript's angle_difference: from `a` to `b`, in [-π, π]. */
function angleDifference(a: number, b: number): number {
  const d = (b - a) % (2 * Math.PI);
  return ((2 * d) % (2 * Math.PI)) - d;
}

/** The host's HexGrid.spiral: cells within `radius` steps (a block of squares, a hex of hexes). */
export function spiral(grid: Grid, center: Cell, radius: number): Cell[] {
  const out: Cell[] = [];
  if (grid.square) {
    for (let dy = -radius; dy <= radius; dy++) for (let dx = -radius; dx <= radius; dx++) out.push({ q: center.q + dx, r: center.r + dy });
    return out;
  }
  for (let dq = -radius; dq <= radius; dq++) {
    for (let dr = Math.max(-radius, -dq - radius); dr <= Math.min(radius, -dq + radius); dr++) out.push({ q: center.q + dq, r: center.r + dr });
  }
  return out;
}

/** The host's spec for a shape where it is: a square is a line as wide as it
 *  is long, centred on its place (or, from a creature, its near side at the
 *  creature's edge). */
function asLine(shape: Shape, p: Placement): { shape: 'circle' | 'cone' | 'line'; origin: Vec; reach: number; width: number; angle: number; dir: number } {
  const dir = (p.direction * Math.PI) / 180;
  const d = { x: Math.cos(dir), y: Math.sin(dir) };
  let origin = { ...p.at };
  const edge = (shape.origin ?? 'center') === 'edge' && p.fromSize > 0;
  if (shape.type === 'circle') return { shape: 'circle', origin, reach: shape.size + p.fromSize * 0.5, width: 0, angle: 0, dir };
  if (shape.type === 'square' && p.fromSize <= 0) {
    origin = { x: origin.x - d.x * shape.size * 0.5, y: origin.y - d.y * shape.size * 0.5 };
    return { shape: 'line', origin, reach: shape.size, width: shape.size, angle: 0, dir };
  }
  if (edge) origin = { x: origin.x + d.x * p.fromSize * 0.5, y: origin.y + d.y * p.fromSize * 0.5 };
  if (shape.type === 'cone') return { shape: 'cone', origin, reach: shape.size, width: 0, angle: shape.angle ?? 53, dir };
  return { shape: 'line', origin, reach: shape.size, width: shape.type === 'square' ? shape.size : (shape.width ?? 1), angle: 0, dir };
}

/** Whether a point (a cell's middle) is in a template where it is. */
export function inShape(shape: Shape, p: Placement, pt: Vec): boolean {
  const s = asLine(shape, p);
  const v = { x: pt.x - s.origin.x, y: pt.y - s.origin.y };
  const len = Math.hypot(v.x, v.y);
  if (s.shape === 'circle') return len <= s.reach + 1e-6;
  if (s.shape === 'cone') {
    const half = ((s.angle * Math.PI) / 180) * 0.5;
    return len <= s.reach + 1e-6 && (len < 1e-6 || Math.abs(angleDifference(Math.atan2(v.y, v.x), s.dir)) <= half + 1e-6);
  }
  const d = { x: Math.cos(s.dir), y: Math.sin(s.dir) };
  const along = v.x * d.x + v.y * d.y;
  const across = Math.abs(v.x * d.y - v.y * d.x);
  return along >= -1e-6 && along <= s.reach + 1e-6 && across <= s.width * 0.5 + 1e-6;
}

/** The cells a template covers where it is, on the map ("q,r" keys). */
export function templateCells(grid: Grid, shape: Shape, p: Placement): string[] {
  const s = asLine(shape, p);
  const center = grid.cellAt(s.origin);
  const out: string[] = [];
  for (const c of spiral(grid, center, Math.ceil(s.reach) + 1)) {
    if (!grid.inBounds(c)) continue;
    if (inShape(shape, p, grid.center(c))) out.push(cellKey(c));
  }
  return out;
}

/** The outline of a template where it is, for drawing: a circle as its
 *  centre and radius, the rest as polygons (hex units). */
export function outline(shape: Shape, p: Placement): { circle?: { at: Vec; r: number }; poly?: Vec[] } {
  const s = asLine(shape, p);
  if (s.shape === 'circle') return { circle: { at: s.origin, r: s.reach } };
  const d = { x: Math.cos(s.dir), y: Math.sin(s.dir) };
  const n = { x: -d.y, y: d.x };
  if (s.shape === 'line') {
    const w = s.width / 2;
    const end = { x: s.origin.x + d.x * s.reach, y: s.origin.y + d.y * s.reach };
    return {
      poly: [
        { x: s.origin.x + n.x * w, y: s.origin.y + n.y * w },
        { x: end.x + n.x * w, y: end.y + n.y * w },
        { x: end.x - n.x * w, y: end.y - n.y * w },
        { x: s.origin.x - n.x * w, y: s.origin.y - n.y * w },
      ],
    };
  }
  const half = ((s.angle * Math.PI) / 180) / 2;
  const poly: Vec[] = [{ ...s.origin }];
  const steps = 16;
  for (let i = 0; i <= steps; i++) {
    const a = s.dir - half + (2 * half * i) / steps;
    poly.push({ x: s.origin.x + Math.cos(a) * s.reach, y: s.origin.y + Math.sin(a) * s.reach });
  }
  return { poly };
}

/** Where a template's knob is (the far end, which turns it), or null for a circle. */
export function knob(shape: Shape, p: Placement): Vec | null {
  if (shape.type === 'circle') return null;
  const s = asLine(shape, p);
  return { x: s.origin.x + Math.cos(s.dir) * s.reach, y: s.origin.y + Math.sin(s.dir) * s.reach };
}

/** Whether a token is a creature a template can catch: not a thing (an
 *  object, one with no stat block), not a marker (a place, the party on a
 *  region), not the dead. */
function catchable(t: Dict): boolean {
  const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
  return !isObject(t) && !isDead(t) && !tags.includes('thing') && !tags.includes('place') && !tags.includes('party');
}

/** The creatures of `tokens` (what this screen shows) a template where it is
 *  would catch: those whose middle's cell it covers — not the creature it
 *  goes out from, unless it is round it and takes it in. */
export function caught(grid: Grid, shape: Shape, p: Placement, tokens: Dict[], fromToken = ''): Dict[] {
  const cells = new Set(templateCells(grid, shape, p));
  return tokens.filter((t) => {
    if (!catchable(t)) return false;
    if (fromToken && String(t.id) === fromToken && !(shape.type === 'circle' && shape.include_self !== false)) return false;
    return cells.has(cellKey(grid.cellAt(tokenPos(t))));
  });
}

/** A square put at a point whose side is an even number of cells stands on
 *  the corner between four of them (a 20-foot cube covers sixteen squares). */
export function evenSquare(shape: Shape): boolean {
  return shape.type === 'square' && Math.round(shape.size) % 2 === 0;
}

/** Where a template put at a tap stands: the middle of the cell (or its corner,
 *  for an even square), or the point itself on a map with no grid drawn. */
export function placeAt(grid: Grid, shape: Shape, tap: Vec, noGrid: boolean): Vec {
  if (noGrid) return { ...tap };
  const c = grid.center(grid.cellAt(tap));
  return evenSquare(shape) ? { x: c.x + 0.5, y: c.y + 0.5 } : c;
}

/** The cell a point template's cast goes at (the one placeAt stood it on). */
export function castCell(grid: Grid, shape: Shape, at: Vec): string {
  const p = evenSquare(shape) ? { x: at.x - 0.5, y: at.y - 0.5 } : at;
  return cellKey(grid.cellAt(p));
}

/** A shape's size in words: "20-ft circle", "15-ft cone", "60-ft line". */
export function shapeWords(type: ShapeType, feet: number): string {
  const name = type === 'square' ? 'cube' : type;
  return `${Math.round(feet * 10) / 10}-ft ${name}`;
}
