import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import { DEAD_APART, DEAD_SIZE, FAN_SIZE, OBJECT_APART, drawFlash, drawnAsThing, hpWords, isDead, isObject, layout, tokenAt, underDiscs } from '../src/lib/map/render';

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

  // (the owner: her dancing lights "should be able to be on the same square as a player")
  it('draws a thing on a creature\'s space at its upper corner, small, over it: a tap finds either', () => {
    const wren = { id: 'w', pos: [c.x, c.y], owner: 'pl_1', actor: 'a_w' };
    const light = { id: 'l1', pos: [c.x, c.y], owner: 'pl_1', size: 0.5, tags: ['object'], light: { dim: 10, color: '#ffe7a3' } };
    expect(isObject(light) && !isObject(wren)).toBe(true);
    const placed = layout([wren, light], grid);
    // the creature whole, where it stands: not fanned out as for another creature
    expect(placed.get('w')).toEqual({ pos: c, k: 1 });
    const l = placed.get('l1')!;
    expect(Math.hypot(l.pos.x - c.x, l.pos.y - c.y)).toBeCloseTo(OBJECT_APART);
    expect(l.pos.y).toBeLessThan(c.y); // the upper corner first
    expect(l.k).toBe(1); // a Tiny light at its own size
    // a tap on the light finds the light, even with a finger's reach; on the creature, the creature
    expect(tokenAt([wren, light], l.pos, 0.3, placed)?.id).toBe('l1');
    expect(tokenAt([light, wren], c, 0.3, placed)?.id).toBe('w');
    // a sphere five feet across shares a space drawn as small as a light
    const sphere = { id: 's', pos: [c.x, c.y], size: 1, tags: ['object'] };
    expect(layout([wren, sphere], grid).get('s')!.k).toBeCloseTo(0.5);
    // four lights on one creature: each at a corner of its own
    const four = [wren, ...[1, 2, 3, 4].map((i) => ({ ...light, id: `l${i}` }))];
    const p4 = layout(four, grid);
    const at = [1, 2, 3, 4].map((i) => p4.get(`l${i}`)!.pos);
    for (let i = 0; i < 4; i++) for (let j = i + 1; j < 4; j++) expect(Math.hypot(at[i].x - at[j].x, at[i].y - at[j].y)).toBeGreaterThan(0.46);
    for (let i = 1; i <= 4; i++) expect(tokenAt(four, p4.get(`l${i}`)!.pos, 0.3, p4)?.id).toBe(`l${i}`);
    expect(tokenAt(four, c, 0.3, p4)?.id).toBe('w');
    // lights alone on a space fan out as creatures do; one alone stays where it is
    const two = layout([light, { ...light, id: 'l2' }], grid);
    expect(two.get('l1')!.k).toBe(FAN_SIZE);
    expect(layout([light], grid).get('l1')).toEqual({ pos: c, k: 1 });
    // a likeness of its caster (Mislead's double) is drawn as the creature it copies: fanned out with her, not at a corner
    const double = { id: 'd', pos: [c.x, c.y], owner: 'pl_1', size: 1, tags: ['object', 'likeness'] };
    expect(isObject(double) && !drawnAsThing(double) && drawnAsThing(light)).toBe(true);
    const pair = layout([wren, double], grid);
    expect(pair.get('w')!.k).toBe(FAN_SIZE);
    expect(pair.get('d')!.k).toBe(FAN_SIZE);
    // a big thing (a Large hand) lies under the creatures: a tap on the creature finds it, elsewhere the hand
    const hand = { id: 'h', pos: [c.x + 0.4, c.y], size: 2, tags: ['object'] };
    expect(tokenAt([hand, wren], c, 0.3, layout([hand, wren], grid))?.id).toBe('w');
    expect(tokenAt([hand, wren], { x: c.x + 1.1, y: c.y }, 0.3, layout([hand, wren], grid))?.id).toBe('h');
  });

  // (a playtest's "Fire of broken pews" covered two goblins and the Warden)
  // (a token chosen from the DM's list: which of three Goblin Warriors it is)
  it('pulses a token chosen from a list: rings going out from it and fading, big enough to see zoomed out', () => {
    const arcs: { r: number; alpha: number }[] = [];
    let alpha = 1;
    const ctx = {
      save: () => {},
      restore: () => (alpha = 1),
      beginPath: () => {},
      stroke: () => {},
      arc: (_x: number, _y: number, r: number) => arcs.push({ r, alpha }),
      set globalAlpha(a: number) {
        alpha = a;
      },
      lineWidth: 1,
      strokeStyle: '',
    } as unknown as CanvasRenderingContext2D;
    const d = { t: { id: 'g', size: 1 }, pos: { x: 3, y: 3 }, k: 1 };
    drawFlash(ctx, d, 0.1, 40);
    const early = arcs.splice(0);
    drawFlash(ctx, d, 0.6, 40);
    const later = arcs.splice(0);
    // one ring at first, the second following; each wider and fainter as it goes
    expect(early.length).toBe(1);
    expect(later.length).toBe(2);
    expect(later[0].r).toBeGreaterThan(early[0].r);
    expect(later[0].alpha).toBeLessThan(early[0].alpha);
    // gone at the end
    drawFlash(ctx, d, 1, 40);
    expect(arcs.splice(0).filter((a) => a.alpha > 0.01).length).toBe(0);
    // zoomed far out (4 px a hex), it still reaches about 30 px out
    drawFlash(ctx, d, 0.64, 4);
    expect(arcs[0].r * 4).toBeGreaterThan(25);
  });

  it('knows a label a token is over', () => {
    const box = { x0: 2, y0: 2, x1: 5, y1: 2.3 };
    expect(underDiscs(box, [{ x: 3, y: 2.6, r: 0.4 }])).toBe(true);
    expect(underDiscs(box, [{ x: 3, y: 3, r: 0.4 }])).toBe(false);
    expect(underDiscs(box, [{ x: 5.3, y: 2.1, r: 0.35 }])).toBe(true);
    expect(underDiscs(box, [])).toBe(false);
  });

  // (the DM's "What players see of a monster's health": exactly, its token
  // carries its hit points from the host; otherwise it carries none)
  it('says a creature\'s hit points under its token where the table shows them', () => {
    expect(hpWords({ id: 'g', hp: [7, 15] })).toBe('7/15');
    expect(hpWords({ id: 'g', hp: [0, 15], tags: ['dead'] })).toBe('0/15');
    expect(hpWords({ id: 'g', hp: [-2.4, 15] })).toBe('0/15');
    expect(hpWords({ id: 'g' })).toBe('');
    expect(hpWords({ id: 'g', hp: [7] })).toBe('');
    expect(hpWords({ id: 'g', hp: 'lots' })).toBe('');
  });
});
