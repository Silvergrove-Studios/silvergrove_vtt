import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import { DEAD_APART, DEAD_SIZE, FAN_SIZE, isDead, layout, tokenAt, underDiscs } from '../src/lib/map/render';

describe('the map, as it is drawn', () => {
  const grid = new Grid({ columns: 10, rows: 8 });
  const c = grid.center({ q: 4, r: 3 });

  // (a playtest's cleric tapped a dead goblin's X for the living Warden beside it)
  it('draws the dead small, and off to a corner of a cell they share with the living', () => {
    const warden = { id: 'w', pos: [c.x, c.y], actor: 'a_w' };
    const corpse = { id: 'g', pos: [c.x, c.y], actor: 'a_g', tags: ['fey', 'dead'] };
    expect(isDead(corpse) && !isDead(warden)).toBe(true);
    const placed = layout([corpse, warden], grid);
    // the living where it would be without the dead: whole, on the cell's centre
    expect(placed.get('w')).toEqual({ pos: c, k: 1 });
    const g = placed.get('g')!;
    expect(g.k).toBe(DEAD_SIZE);
    expect(Math.hypot(g.pos.x - c.x, g.pos.y - c.y)).toBeCloseTo(DEAD_APART);
    // (below the living: the lower corner first)
    expect(g.pos.y).toBeGreaterThan(c.y);
    // a tap on the living finds the living
    expect(tokenAt([corpse, warden], { x: c.x - 0.1, y: c.y - 0.1 }, 0.3, placed)?.id).toBe('w');
    // two living and one dead: the living fan out as before, the dead aside
    const ally = { id: 'a', pos: [c.x, c.y], owner: 'pl_1' };
    const three = layout([warden, corpse, ally], grid);
    expect(three.get('w')!.k).toBe(FAN_SIZE);
    expect(three.get('a')!.k).toBe(FAN_SIZE);
    expect(three.get('g')!.k).toBe(DEAD_SIZE);
    // the dead alone: where they lie, small
    const lone = { id: 'l', pos: [1.2, 1.1], tags: ['dead'] };
    expect(layout([lone], grid).get('l')).toEqual({ pos: { x: 1.2, y: 1.1 }, k: DEAD_SIZE });
    // a large one dead: small too
    expect(layout([{ id: 'o', pos: [5, 5], size: 2, tags: ['dead'] }], grid).get('o')!.k).toBe(DEAD_SIZE);
  });

  // (a playtest's "Fire of broken pews" covered two goblins and the Warden)
  it('knows a label a token is over', () => {
    const box = { x0: 2, y0: 2, x1: 5, y1: 2.3 };
    expect(underDiscs(box, [{ x: 3, y: 2.6, r: 0.4 }])).toBe(true);
    expect(underDiscs(box, [{ x: 3, y: 3, r: 0.4 }])).toBe(false);
    expect(underDiscs(box, [{ x: 5.3, y: 2.1, r: 0.35 }])).toBe(true);
    expect(underDiscs(box, [])).toBe(false);
  });
});
