// The grid — hex or square — as the host's HexGrid (hexmap/core/hex_grid.gd)
// has it, so a click lands on the same cell here and there. Units are hex
// units: the flat-to-flat width of a hex, or a square's side. Cells are
// axial (q, r); offset coordinates (col, row) bound the map.

export type Vec = { x: number; y: number };
export type Cell = { q: number; r: number };

export const SQRT3 = 1.7320508075688772;
/** Circumradius of a hex whose flat-to-flat width is 1. */
export const R = 1 / SQRT3;
/** Inradius. */
export const I = 0.5;
export const INSCRIBED_SQUARE = 0.7320508075688772;

export interface GridDoc {
  shape?: string;
  orientation?: string;
  offset?: string;
  columns?: number;
  rows?: number;
  distance?: number;
  units?: string;
}

/** GDScript's roundi: half away from zero. */
export function roundi(v: number): number {
  return v < 0 ? -Math.round(-v) : Math.round(v);
}

export class Grid {
  square: boolean;
  pointy: boolean;
  odd: boolean;
  columns: number;
  rows: number;
  distance: number;
  units: string;

  constructor(d: GridDoc = {}) {
    this.square = d.shape === 'square';
    this.pointy = d.orientation !== 'flat';
    this.odd = d.offset !== 'even';
    this.columns = d.columns ?? 20;
    this.rows = d.rows ?? 14;
    this.distance = d.distance ?? 5;
    this.units = d.units ?? 'ft';
  }

  cornerCount(): number {
    return this.square ? 4 : 6;
  }

  /** Centre of a cell, in hex units. */
  center(c: Cell): Vec {
    const { q, r } = c;
    if (this.square) return { x: q + 0.5, y: r + 0.5 };
    if (this.pointy) {
      let x = q + r * 0.5 + I;
      const y = r * 1.5 * R + R;
      if (!this.odd) x += I;
      return { x, y };
    }
    const x = q * 1.5 * R + R;
    let y = r + q * 0.5 + I;
    if (!this.odd) y += I;
    return { x, y };
  }

  /** The cell under a point (hex units). */
  cellAt(p: Vec): Cell {
    if (this.square) return { q: Math.floor(p.x), r: Math.floor(p.y) };
    let fq: number;
    let fr: number;
    if (this.pointy) {
      const x = p.x - I - (!this.odd ? I : 0);
      const y = p.y - R;
      fr = y / (1.5 * R);
      fq = x - fr * 0.5;
    } else {
      const x = p.x - R;
      const y = p.y - I - (!this.odd ? I : 0);
      fq = x / (1.5 * R);
      fr = y - fq * 0.5;
    }
    return cubeRound(fq, fr);
  }

  /** A cell's corners, clockwise on screen, in hex units. */
  corners(c: Cell): Vec[] {
    return this.cornersAt(this.center(c));
  }

  cornersAt(c: Vec): Vec[] {
    if (this.square) {
      return [
        { x: c.x - I, y: c.y - I },
        { x: c.x + I, y: c.y - I },
        { x: c.x + I, y: c.y + I },
        { x: c.x - I, y: c.y + I },
      ];
    }
    const start = this.pointy ? -30 : 0;
    const out: Vec[] = [];
    for (let i = 0; i < 6; i++) {
      const a = ((start + 60 * i) * Math.PI) / 180;
      out.push({ x: c.x + Math.cos(a) * R, y: c.y + Math.sin(a) * R });
    }
    return out;
  }

  toOffset(c: Cell): { col: number; row: number } {
    if (this.square) return { col: c.q, row: c.r };
    const { q, r } = c;
    if (this.pointy) {
      const col = q + (this.odd ? (r - (r & 1)) >> 1 : (r + (r & 1)) >> 1);
      return { col, row: r };
    }
    const row = r + (this.odd ? (q - (q & 1)) >> 1 : (q + (q & 1)) >> 1);
    return { col: q, row };
  }

  fromOffset(col: number, row: number): Cell {
    if (this.square) return { q: col, r: row };
    if (this.pointy) {
      const q = col - (this.odd ? (row - (row & 1)) >> 1 : (row + (row & 1)) >> 1);
      return { q, r: row };
    }
    const r = row - (this.odd ? (col - (col & 1)) >> 1 : (col + (col & 1)) >> 1);
    return { q: col, r };
  }

  inBounds(c: Cell): boolean {
    const o = this.toOffset(c);
    return o.col >= 0 && o.row >= 0 && o.col < this.columns && o.row < this.rows;
  }

  allCells(): Cell[] {
    const out: Cell[] = [];
    for (let row = 0; row < this.rows; row++) for (let col = 0; col < this.columns; col++) out.push(this.fromOffset(col, row));
    return out;
  }

  /** The map's bounding box in hex units, from the origin. */
  size(): Vec {
    if (this.square) return { x: this.columns, y: this.rows };
    if (this.pointy) return { x: this.columns + (this.rows > 1 ? I : 0), y: 2 * R + (this.rows - 1) * 1.5 * R };
    return { x: 2 * R + (this.columns - 1) * 1.5 * R, y: this.rows + (this.columns > 1 ? I : 0) };
  }

  /** Steps between cells: hex steps, or Chebyshev on squares. */
  steps(a: Cell, b: Cell): number {
    if (this.square) return Math.max(Math.abs(a.q - b.q), Math.abs(a.r - b.r));
    const dq = a.q - b.q;
    const dr = a.r - b.r;
    return (Math.abs(dq) + Math.abs(dr) + Math.abs(dq + dr)) / 2;
  }
}

export function cubeRound(fq: number, fr: number): Cell {
  const fs = -fq - fr;
  let q = roundi(fq);
  let r = roundi(fr);
  const s = roundi(fs);
  const dq = Math.abs(q - fq);
  const dr = Math.abs(r - fr);
  const ds = Math.abs(s - fs);
  if (dq > dr && dq > ds) q = -r - s;
  else if (dr > ds) r = -q - s;
  return { q: q + 0, r: r + 0 };
}

/** "q,r" — how cells are keyed in maps and scenes. */
export function cellKey(c: Cell): string {
  return `${c.q},${c.r}`;
}

export function keyCell(k: string): Cell {
  const [q, r] = k.split(',').map(Number);
  return { q, r };
}
