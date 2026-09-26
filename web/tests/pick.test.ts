import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import { pickCount, pickTarget, pickWords, togglePicked, withTarget } from '../src/lib/map/pick';

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
