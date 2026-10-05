// How far, as the map counts it — the host's Measure (hexmap/rules/measure.gd):
// in the map's own units by its scale, cell to cell on a map whose grid is
// drawn (hex steps, or on squares the diagonal rule the rules registered:
// every square one, every second diagonal two, or as the crow flies), point
// to point on a map drawn without one. A screen counts the straight distance
// itself as a ruler is dragged; the walk round the walls comes from the Table.
import { Grid, type Vec } from '../grid';
import type { Dict } from '../game.svelte';

export type Diagonals = '5-5-5' | '5-10-5' | 'euclid';
export const RULES: Diagonals[] = ['5-5-5', '5-10-5', 'euclid'];

/** The scene's diagonal rule (the Table says it with the scene), else every step a square. */
export function ruleOf(scene: Dict | null | undefined): Diagonals {
  const d = String((scene?.measure as Dict | undefined)?.diagonals ?? '');
  return (RULES as string[]).includes(d) ? (d as Diagonals) : '5-5-5';
}

/** Whether a map draws no grid (a painted region): its rulers go point to point. */
export function gridless(map: Dict | null | undefined): boolean {
  return map?.style?.show_grid === false;
}

/** The straight distance along `points` (hex units), in the map's units: each
 *  point's cell to the next's, or the points themselves with no grid drawn.
 *  Under 5-10-5 every second diagonal costs two, counted along the whole ruler. */
export function straight(grid: Grid, points: Vec[], rule: Diagonals = '5-5-5', noGrid = false): number {
  let total = 0;
  let parity = 0;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    if (noGrid) {
      total += Math.hypot(b.x - a.x, b.y - a.y);
      continue;
    }
    const ca = grid.cellAt(a);
    const cb = grid.cellAt(b);
    if (!grid.square) {
      total += grid.steps(ca, cb);
      continue;
    }
    const dx = Math.abs(cb.q - ca.q);
    const dy = Math.abs(cb.r - ca.r);
    const diag = Math.min(dx, dy);
    const orth = Math.max(dx, dy) - diag;
    if (rule === 'euclid') total += Math.sqrt(dx * dx + dy * dy);
    else if (rule === '5-10-5') {
      const dear = Math.floor((diag + parity) / 2);
      parity = (diag + parity) % 2;
      total += orth + diag + dear;
    } else total += orth + diag;
  }
  return total * (grid.distance > 0 ? grid.distance : 5);
}

/** A distance with its unit: whole numbers plainly ("25 ft"), others to one place ("7.5 m"). */
export function amount(v: number, units: string): string {
  const r = Math.round(v * 10) / 10;
  const n = Math.abs(r - Math.round(r)) < 0.05 ? String(Math.round(r)) : r.toFixed(1);
  return `${n} ${units || 'ft'}`;
}

/** A ruler's measure, as the Table sends it. */
export interface Measure {
  straight: number;
  walk?: number;
  no_way?: boolean;
  units?: string;
  words?: string;
}

/** A measure in words: "25 ft", "30 ft straight, 45 ft to walk round". */
export function words(m: Measure): string {
  const units = m.units || 'ft';
  const s = amount(m.straight, units);
  if (typeof m.walk === 'number') return `${s} straight, ${amount(m.walk, units)} to walk round`;
  if (m.no_way) return `${s} straight; no way to walk there`;
  return s;
}

/** One of each unit in metres (the host's Vision.METRES), to turn feet into a map's units. */
const METRES: Record<string, number> = { in: 0.0254, ft: 0.3048, feet: 0.3048, foot: 0.3048, yd: 0.9144, yard: 0.9144, yards: 0.9144, m: 1, metre: 1, metres: 1, meter: 1, meters: 1, km: 1000, mi: 1609.344, mile: 1609.344, miles: 1609.344 };

/** Feet as hex units on a map, by its scale: a 20-foot circle is four cells of
 *  five feet, or about four of 1.5 metres. */
export function feetToUnits(feet: number, grid: Grid): number {
  const per = grid.distance > 0 ? grid.distance : 5;
  const u = String(grid.units || 'ft').trim().toLowerCase();
  if (u === 'ft' || u === 'feet' || u === 'foot') return feet / per;
  const m = METRES[u];
  return m ? (feet * METRES.ft) / (m * per) : feet / 5;
}

/** Where a tap measures from: the middle of a creature there (one this screen
 *  shows: never one it doesn't), else of the cell — or the point itself on a
 *  map with no grid drawn. */
export function snapPoint(grid: Grid, p: Vec, noGrid: boolean, tokens: Dict[] = [], reach = 0): Vec {
  let best: Dict | null = null;
  let bestD = Infinity;
  for (const t of tokens) {
    const pos = (t.pos as number[]) ?? [0, 0];
    const d = Math.hypot(Number(pos[0]) - p.x, Number(pos[1]) - p.y);
    if (d <= Math.max(Number(t.size ?? 1) * 0.5, reach) && d < bestD) {
      best = t;
      bestD = d;
    }
  }
  if (best) {
    const pos = best.pos as number[];
    return { x: Number(pos[0]), y: Number(pos[1]) };
  }
  return noGrid ? { x: p.x, y: p.y } : grid.center(grid.cellAt(p));
}
