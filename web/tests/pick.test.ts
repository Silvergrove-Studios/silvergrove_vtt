import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import { moveTo, moveWords, pickCount, pickTarget, pickWords, togglePicked, withTarget } from '../src/lib/map/pick';
import { FAN_SIZE, layout, tokenAt } from '../src/lib/map/render';

describe('picking a target', () => {
  const grid = new Grid({ columns: 10, rows: 8 });
  const tokens = [
    { id: 'a', pos: [grid.center({ q: 1, r: 1 }).x, grid.center({ q: 1, r: 1 }).y], actor: 'hero' },
    { id: 'g', pos: [grid.center({ q: 4, r: 2 }).x, grid.center({ q: 4, r: 2 }).y], hidden: true },
  ];
  it('picks a token under the point, but a player never picks a hidden one', () => {
    const at = { x: tokens[0].pos[0] + 0.1, y: tokens[0].pos[1] };
    expect(pickTarget(grid, tokens, { pick: 'token' }, at, false)).toBe('token:a');
    const g = { x: tokens[1].pos[0], y: tokens[1].pos[1] };
    expect(pickTarget(grid, tokens, { pick: 'token' }, g, false)).toBeNull();
    expect(pickTarget(grid, tokens, { pick: 'token' }, g, true)).toBe('token:g');
  });
  it('picks cells in bounds and aims areas from the actor’s token', () => {
    expect(pickTarget(grid, tokens, { pick: 'cell' }, grid.center({ q: 3, r: 3 }), false)).toBe('3,3');
    expect(pickTarget(grid, tokens, { pick: 'cell' }, { x: -5, y: -5 }, false)).toBeNull();
    const cone = pickTarget(grid, tokens, { pick: 'area', area: { shape: 'cone', length: 3 }, ctx: { actor: 'hero' } }, { x: tokens[0].pos[0] + 2, y: tokens[0].pos[1] }, false) as Record<string, unknown>;
    expect(cone.at).toBe('token:a');
    expect(Math.round(Number(cone.direction))).toBe(0);
  });
  it('sends the intent with its target', () => {
    const sent = withTarget({ kind: 'action', pick: 'token', label: 'Attack', ctx: { actor: 'hero' } }, 'token:g', 's1');
    expect(sent).toEqual({ kind: 'action', ctx: { actor: 'hero', target: 'token:g', scene: 's1' } });
  });
  it('fans out tokens on one cell, and a tap on each picks that one', () => {
    const c = grid.center({ q: 5, r: 5 });
    const stack = [
      { id: 'ada', pos: [c.x, c.y], owner: 'pl_a' },
      { id: 'gob', pos: [c.x, c.y], actor: 'a_g' },
    ];
    const placed = layout(stack, grid);
    const a = placed.get('ada')!;
    const b = placed.get('gob')!;
    expect(a.k).toBe(FAN_SIZE);
    expect(Math.hypot(a.pos.x - b.pos.x, a.pos.y - b.pos.y)).toBeCloseTo(0.44);
    for (const t of stack) {
      // where it is drawn, with a finger's reach
      const hit = tokenAt(stack, placed.get(t.id)!.pos, 0.3, placed);
      expect(hit?.id).toBe(t.id);
      // (the pick was re-found by position: the last one on the cell, whichever was tapped)
      expect(pickTarget(grid, stack, { pick: 'token' }, { x: c.x, y: c.y }, false, hit)).toBe(`token:${t.id}`);
    }
    // three or four round a circle; one alone, or a large one, stays where it stands
    const lone = grid.center({ q: 1, r: 1 });
    const more = [...stack, { id: 'jin', pos: [c.x, c.y], owner: 'pl_j' }, { id: 'lone', pos: [lone.x, lone.y] }, { id: 'ogre', pos: [c.x, c.y], size: 2 }];
    const p3 = layout(more, grid);
    const three = ['ada', 'gob', 'jin'].map((id) => p3.get(id)!.pos);
    for (let i = 0; i < 3; i++) for (let j = i + 1; j < 3; j++) expect(Math.hypot(three[i].x - three[j].x, three[i].y - three[j].y)).toBeGreaterThan(0.3);
    expect(p3.get('lone')).toEqual({ pos: lone, k: 1 });
    expect(p3.get('ogre')).toEqual({ pos: c, k: 1 });
    for (const id of ['ada', 'gob', 'jin']) expect(tokenAt(more.filter((t) => t.id !== 'ogre'), p3.get(id)!.pos, 0.25, p3)?.id).toBe(id);
    // a token being dragged is drawn where the pointer is: the others close up
    expect(layout(stack, grid, 'gob').get('ada')).toEqual({ pos: c, k: 1 });
  });

  it('moves a token armed with a tap to the centre of the cell tapped next', () => {
    const grace = { id: 'g', name: 'Grace', pos: [grid.center({ q: 1, r: 1 }).x, grid.center({ q: 1, r: 1 }).y] };
    expect(moveWords(grace)).toBe('Move Grace: tap where to go');
    const target = grid.center({ q: 5, r: 1 });
    // anywhere in the cell: its centre, four spaces off
    expect(moveTo(grid, grace, { x: target.x + 0.2, y: target.y - 0.1 })).toEqual({ pos: [target.x, target.y], spaces: 4 });
    // on a map drawn with no grid, where it was tapped
    expect(moveTo(grid, grace, { x: target.x + 0.2, y: target.y }, false)?.pos).toEqual([target.x + 0.2, target.y]);
    // off the map: nowhere
    expect(moveTo(grid, grace, { x: -3, y: -3 })).toBeNull();
    // on squares, a diagonal is a step
    const squares = new Grid({ shape: 'square', columns: 10, rows: 8 });
    expect(moveTo(squares, { pos: [0.5, 0.5] }, { x: 3.5, y: 2.5 })).toEqual({ pos: [3.5, 2.5], spaces: 3 });
  });

  it('never picks a hidden creature for a player, whatever was hit', () => {
    const g = { id: 'g', pos: tokens[1].pos, hidden: true };
    expect(pickTarget(grid, tokens, { pick: 'token' }, { x: g.pos[0], y: g.pos[1] }, false, g)).toBeNull();
    expect(pickTarget(grid, tokens, { pick: 'token' }, { x: g.pos[0], y: g.pos[1] }, true, g)).toBe('token:g');
  });

  it('picks several creatures for a spell that takes them (Bless: up to three)', () => {
    const bless = { kind: 'action', pick: 'token', picks: 3, label: 'Cast', ctx: { actor: 'hero' } };
    expect(pickCount(bless)).toBe(3);
    expect(pickCount({ pick: 'cell', picks: 3 })).toBe(1);
    expect(pickCount({ pick: 'token', picks: '' })).toBe(1);
    expect(pickWords(bless)).toBe('Cast: tap up to 3 creatures on the map, then Done');
    let picked = togglePicked([], 'token:a', 3);
    picked = togglePicked(picked, 'token:b', 3);
    picked = togglePicked(picked, 'token:c', 3);
    expect(togglePicked(picked, 'token:d', 3)).toEqual(['token:a', 'token:b', 'token:c']);
    expect(togglePicked(picked, 'token:b', 3)).toEqual(['token:a', 'token:c']);
    expect(withTarget(bless, picked, 's1')).toEqual({ kind: 'action', ctx: { actor: 'hero', target: ['token:a', 'token:b', 'token:c'], scene: 's1' } });
  });
});
