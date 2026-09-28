import { describe, expect, it } from 'vitest';
import { Grid, cellKey } from '../src/lib/grid';
import { WALL_COLORS, seenWalls, wallKind, wallsFor } from '../src/lib/map/walls';

describe('walls, as the DM and the players see them', () => {
  const solid = { move: true, sight: true, light: true, sound: true };
  it('knows each kind as the host colours it (map_canvas.gd wall_color)', () => {
    expect(wallKind({ blocks: solid })).toBe('wall');
    expect(wallKind({ blocks: solid, door: 'door' })).toBe('door');
    expect(wallKind({ blocks: solid, door: 'secret' })).toBe('secret');
    expect(wallKind({ blocks: { move: true, sight: false, light: false, sound: true } })).toBe('window');
    expect(wallKind({ blocks: { move: true, sight: false, light: false, sound: false } })).toBe('fence');
    expect(wallKind({ blocks: { move: false, sight: true, light: true, sound: false }, sight_mode: 'limited' })).toBe('terrain');
    expect(wallKind({ blocks: { move: false, sight: true, light: true, sound: true } })).toBe('ethereal');
    expect(wallKind({})).toBe('wall');
    expect([WALL_COLORS.wall, WALL_COLORS.secret, WALL_COLORS.terrain]).toEqual(['#d8d8d8', '#b070e0', '#70c070']);
  });

  const grid = new Grid({ columns: 20, rows: 10 });
  // what the player sees: a box from the origin to (6, 6)
  const visible = [
    [
      [0, 0],
      [6, 0],
      [6, 6],
      [0, 6],
    ],
  ];
  const near = { id: 'near', points: [[3, 1], [3, 4]], blocks: solid };
  const edge = { id: 'edge', points: [[6, 0], [6, 6]], blocks: solid };
  const far = { id: 'far', points: [[12, 2], [12, 5]], blocks: solid };
  const pillar = { id: 'pillar', points: [[2, 2], [2.5, 2]], blocks: solid, hidden: true };
  const secret = { id: 'secret', points: [[3, 5], [4, 5]], blocks: solid, door: 'secret', state: 'closed' };

  it('gives a player the walls they have seen (from either side), never a hidden one', () => {
    expect(seenWalls([near, edge, far, pillar], grid, visible, new Set()).map((w) => w.id)).toEqual(['near', 'edge']);
    // seen before: the cells beside it explored
    const explored = new Set(
      grid
        .allCells()
        .filter((c) => Math.abs(grid.center(c).x - 12) < 0.8 && grid.center(c).y > 1.5 && grid.center(c).y < 5.5)
        .map(cellKey),
    );
    expect(seenWalls([far], grid, [], explored).map((w) => w.id)).toEqual(['far']);
    expect(seenWalls([far], grid, [], new Set()).map((w) => w.id)).toEqual([]);
  });

  // (a playtest's player saw the chapel's west face, and was drawn the whole
  // building: its outline is one wall)
  it('draws a player only the stretches of a long wall they have seen', () => {
    // an L: down the west side, then along the south, far out of sight
    const ell = { id: 'ell', points: [[3, 1], [3, 6], [15, 6]], blocks: solid };
    const west = [
      [
        [0, 0],
        [4, 0],
        [4, 5.7],
        [0, 5.7],
      ],
    ];
    const runs = seenWalls([ell], grid, west, new Set());
    expect(runs.map((w) => w.id)).toEqual(['ell']);
    const pts = runs[0].points as number[][];
    // on the arm seen, all of it in sight; none of the other arm
    expect(pts.every(([x, y]) => x === 3 && y >= 1 && y <= 5.5)).toBe(true);
    expect(pts[0]).toEqual([3, 1]);
    expect(pts[pts.length - 1]).toEqual([3, 5.5]);
    expect(runs[0].blocks).toBe(solid);
    // seen whole, a wall comes back as it is
    expect(seenWalls([ell], grid, [[[0, 0], [20, 0], [20, 9], [0, 9]]], new Set())[0]).toBe(ell);
    // seen at both ends (two windows on it): two runs, the middle not drawn
    const ends = [
      [
        [0, 0],
        [4, 0],
        [4, 3],
        [0, 3],
      ],
      [
        [12, 4],
        [16, 4],
        [16, 8],
        [12, 8],
      ],
    ];
    const two = seenWalls([ell], grid, ends, new Set());
    expect(two.length).toBe(2);
    expect((two[0].points as number[][]).every(([x, y]) => x === 3 && y <= 3)).toBe(true);
    expect((two[1].points as number[][]).every(([x, y]) => y === 6 && x >= 12)).toBe(true);
    // a door is one thing: seen at all, seen whole; a closed secret door is the wall it looks like
    const door = { id: 'door', points: [[3.5, 5.5], [3.5, 6.5]], blocks: solid, door: 'door' };
    expect(seenWalls([door], grid, west, new Set())[0]).toBe(door);
    const hid = { id: 'hid', points: [[3, 1], [3, 9]], blocks: solid, door: 'secret', state: 'closed' };
    expect((seenWalls([hid], grid, west, new Set())[0].points as number[][]).every(([, y]) => y <= 5.5)).toBe(true);
  });

  it('draws every wall for the DM, and a player only what they may see', () => {
    const lvl = { walls: [near, far, pillar, secret] };
    expect(wallsFor(lvl, grid, { fog: true, visible, explored: [] }, true).map((w) => w.id)).toEqual(['near', 'far', 'pillar', 'secret']);
    expect(wallsFor(lvl, grid, { fog: true, visible, explored: [] }, false).map((w) => w.id)).toEqual(['near', 'secret']);
    // no fog: every wall but the hidden ones
    expect(wallsFor(lvl, grid, { fog: false }, false).map((w) => w.id)).toEqual(['near', 'far', 'secret']);
  });
});
