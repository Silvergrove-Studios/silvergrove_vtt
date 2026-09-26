import { describe, expect, it } from 'vitest';
import { Grid, cellKey } from '../src/lib/grid';
import { UNSEEN_WORDS, fogOf, fogWords, ghostsOf, inAny, inPolygon } from '../src/lib/map/sight';

describe('sight, from what the table sent', () => {
  const grid = new Grid({ columns: 10, rows: 6 });
  const box = (x0: number, y0: number, x1: number, y1: number) => [
    [x0, y0],
    [x1, y0],
    [x1, y1],
    [x0, y1],
  ];
  // row 2's centres are at x = col + 0.5
  const at = (col: number, row: number) => grid.fromOffset(col, row);
  // in the dark: seen out to x 3 (a torch), the line of sight out to x 7
  const scene = { fog: true, light: 'dark', visible: [box(0, 0, 3, 6)], los: [box(0, 0, 7, 6)], explored: [cellKey(at(8, 2))] };

  it('counts a point in a polygon as the host does', () => {
    expect(inPolygon({ x: 1, y: 1 }, box(0, 0, 2, 2))).toBe(true);
    expect(inPolygon({ x: 3, y: 1 }, box(0, 0, 2, 2))).toBe(false);
    expect(inAny({ x: 5, y: 1 }, [box(0, 0, 2, 2), box(4, 0, 6, 2)])).toBe(true);
    expect(inAny({ x: 5, y: 1 }, [])).toBe(false);
  });

  it('says what the fog is over each cell: seen, too dark, seen before, or behind walls', () => {
    expect(fogOf(grid, scene, at(1, 2))).toBe('seen');
    expect(fogOf(grid, scene, at(5, 2))).toBe('dark');
    expect(fogOf(grid, scene, at(8, 2))).toBe('explored');
    expect(fogOf(grid, scene, at(9, 4))).toBe('unseen');
    expect(fogOf(grid, { fog: false }, at(9, 4))).toBe('seen');
    // by day there is no line of sight apart: out of sight is walls
    expect(fogOf(grid, { fog: true, visible: [box(0, 0, 3, 6)], explored: [] }, at(5, 2))).toBe('unseen');
  });

  it('says why, when a player taps the fog', () => {
    expect(fogWords('dark')).toMatch(/too dark/i);
    expect(fogWords('unseen')).toMatch(/walls/);
    expect(fogWords('explored')).toMatch(/last saw/);
    expect(fogWords('seen')).toBe('');
  });

  it('puts the creatures a player can’t see where they are, with why, for the DM’s See as', () => {
    const tokens = [
      { id: 'hero', pos: [1, 1] },
      { id: 'g1', pos: [5, 2] },
      { id: 'g2', pos: [9, 4], hidden: true },
    ];
    const ghosts = ghostsOf(tokens, { g1: 'dark', g2: 'hidden' });
    expect(ghosts.map((g) => [g.id, g.why])).toEqual([
      ['g1', 'dark'],
      ['g2', 'hidden'],
    ]);
    expect([UNSEEN_WORDS.dark, UNSEEN_WORDS.walls, UNSEEN_WORDS.hidden]).toEqual(['too dark', 'walls', 'hidden']);
  });
});
