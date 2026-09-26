import { describe, expect, it } from 'vitest';
import { Grid, cellKey, keyCell } from '../src/lib/grid';

describe('Grid, as the host has it', () => {
  const g = new Grid({ shape: 'hex', orientation: 'pointy', offset: 'odd', columns: 24, rows: 16 });
  it('centres and finds cells both ways', () => {
    for (const c of g.allCells()) {
      const back = g.cellAt(g.center(c));
      expect(back).toEqual(c);
    }
  });
  it('converts offset and axial', () => {
    const c = g.fromOffset(9, 8);
    expect(g.toOffset(c)).toEqual({ col: 9, row: 8 });
    expect(g.inBounds(c)).toBe(true);
    expect(g.inBounds(g.fromOffset(24, 0))).toBe(false);
  });
  it('has six corners at the circumradius', () => {
    const cs = g.corners({ q: 0, r: 0 });
    expect(cs.length).toBe(6);
    const c = g.center({ q: 0, r: 0 });
    for (const p of cs) expect(Math.hypot(p.x - c.x, p.y - c.y)).toBeCloseTo(1 / Math.sqrt(3));
  });
  it('knows squares and flat hexes', () => {
    const s = new Grid({ shape: 'square', columns: 10, rows: 8 });
    expect(s.center({ q: 2, r: 3 })).toEqual({ x: 2.5, y: 3.5 });
    expect(s.cellAt({ x: 2.9, y: 3.1 })).toEqual({ q: 2, r: 3 });
    expect(s.steps({ q: 0, r: 0 }, { q: 3, r: 5 })).toBe(5);
    const f = new Grid({ orientation: 'flat', offset: 'even', columns: 6, rows: 6 });
    for (const c of f.allCells()) expect(f.cellAt(f.center(c))).toEqual(c);
  });
  it('goes to the map’s column and row and back on an odd row, where they differ from axial', () => {
    // (a playtest's party star was sent as axial q,r and read as column,row: it landed cells away)
    for (const [col, row] of [[9, 7], [0, 1], [23, 15], [4, 8]]) {
      const c = g.fromOffset(col, row);
      expect(g.toOffset(g.cellAt(g.center(c)))).toEqual({ col, row });
    }
    const odd = g.fromOffset(9, 7);
    expect([odd.q, odd.r]).not.toEqual([9, 7]);
  });
  it('keys cells as the maps do', () => {
    expect(cellKey({ q: -1, r: 10 })).toBe('-1,10');
    expect(keyCell('-1,10')).toEqual({ q: -1, r: 10 });
  });
});
