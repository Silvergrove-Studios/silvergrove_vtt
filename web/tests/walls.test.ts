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

  it('draws every wall for the DM, and a player only what they may see', () => {
    const lvl = { walls: [near, far, pillar, secret] };
    expect(wallsFor(lvl, grid, { fog: true, visible, explored: [] }, true).map((w) => w.id)).toEqual(['near', 'far', 'pillar', 'secret']);
    expect(wallsFor(lvl, grid, { fog: true, visible, explored: [] }, false).map((w) => w.id)).toEqual(['near', 'secret']);
    // no fog: every wall but the hidden ones
    expect(wallsFor(lvl, grid, { fog: false }, false).map((w) => w.id)).toEqual(['near', 'far', 'secret']);
  });
});
