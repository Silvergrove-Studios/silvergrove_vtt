import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import { castCell, caught, evenSquare, inShape, knob, placeAt, shapeWords, templateCells, type Shape } from '../src/lib/map/template';

// The shapes the host's MapQuery.template lays (tests/suites/marks.gd,
// test_templates_as_the_screens_lay_them, has the same cases on the host).
const sq = new Grid({ shape: 'square', columns: 20, rows: 14, distance: 5, units: 'ft' });
const sorted = (cells: string[]) => [...cells].sort();

describe('a template’s cells, as the rules lay them', () => {
  it('a circle at a point: the cells whose middles are within it', () => {
    const cells = templateCells(sq, { type: 'circle', size: 2 }, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 0 });
    expect(cells.length).toBe(13);
    expect(cells).toContain('5,5');
    expect(cells).toContain('7,5');
    expect(cells).not.toContain('7,6');
  });
  it('a circle round a creature takes in its size', () => {
    const round = templateCells(sq, { type: 'circle', size: 1 }, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 });
    // radius 1 + half a square: the eight round it, and itself
    expect(round.length).toBe(9);
  });
  it('a cube put at a point: a square of its side, on a corner when its side is even', () => {
    const four: Shape = { type: 'square', size: 4 };
    expect(evenSquare(four)).toBe(true);
    const at = placeAt(sq, four, { x: 5.2, y: 5.7 }, false);
    expect(at).toEqual({ x: 6, y: 6 });
    expect(templateCells(sq, four, { at, direction: 0, fromSize: 0 }).length).toBe(16);
    expect(castCell(sq, four, at)).toBe('5,5');
    const three: Shape = { type: 'square', size: 3 };
    const at3 = placeAt(sq, three, { x: 5.2, y: 5.7 }, false);
    expect(at3).toEqual({ x: 5.5, y: 5.5 });
    expect(sorted(templateCells(sq, three, { at: at3, direction: 0, fromSize: 0 }))).toEqual(sorted(['4,4', '5,4', '6,4', '4,5', '5,5', '6,5', '4,6', '5,6', '6,6']));
  });
  it('a cone from a creature’s edge, 53° wide', () => {
    const cone: Shape = { type: 'cone', size: 3, angle: 53, origin: 'edge' };
    const cells = templateCells(sq, cone, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 });
    expect(sorted(cells)).toEqual(sorted(['6,5', '7,5', '8,5', '8,4', '8,6']));
    // turned to face south
    const south = templateCells(sq, cone, { at: { x: 5.5, y: 5.5 }, direction: 90, fromSize: 1 });
    expect(sorted(south)).toEqual(sorted(['5,6', '5,7', '5,8', '4,8', '6,8']));
    expect(knob(cone, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 })).toEqual({ x: 9, y: 5.5 });
  });
  it('a line from a creature’s edge, its width across', () => {
    const line: Shape = { type: 'line', size: 6, width: 1, origin: 'edge' };
    const cells = templateCells(sq, line, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 });
    expect(sorted(cells)).toEqual(sorted(['6,5', '7,5', '8,5', '9,5', '10,5', '11,5']));
    expect(inShape(line, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 }, { x: 9.5, y: 5.9 })).toBe(true);
    expect(inShape(line, { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 }, { x: 9.5, y: 6.6 })).toBe(false);
  });
  it('stays on the map', () => {
    const cells = templateCells(sq, { type: 'circle', size: 2 }, { at: { x: 0.5, y: 0.5 }, direction: 0, fromSize: 0 });
    expect(cells.every((k) => !k.startsWith('-') && !k.includes(',-'))).toBe(true);
    expect(cells.length).toBe(6);
  });
  it('lays hexes too', () => {
    const hex = new Grid({ shape: 'hex', orientation: 'pointy', offset: 'odd', columns: 20, rows: 14 });
    const c = hex.center(hex.fromOffset(8, 6));
    // a hex of hexes: radius 1 takes the six round it
    expect(templateCells(hex, { type: 'circle', size: 1 }, { at: c, direction: 0, fromSize: 0 }).length).toBe(7);
    expect(templateCells(hex, { type: 'circle', size: 2 }, { at: c, direction: 0, fromSize: 0 }).length).toBe(19);
  });
  it('says its size in words', () => {
    expect(shapeWords('circle', 20)).toBe('20-ft circle');
    expect(shapeWords('square', 15)).toBe('15-ft cube');
  });
});

describe('who a template would catch, of what a screen shows', () => {
  const tokens = [
    { id: 'me', name: 'Sela', pos: [5.5, 5.5], size: 1, owner: 'pl_ana', actor: 'a_sela' },
    { id: 'g1', name: 'Goblin 1', pos: [7.5, 5.5], size: 1, actor: 'a_g1' },
    { id: 'g2', name: 'Goblin 2', pos: [8.5, 4.5], size: 1, actor: 'a_g2', tags: ['dead'] },
    { id: 'light', name: 'Light', pos: [6.5, 5.5], size: 0.5, tags: ['object'] },
    { id: 'far', name: 'Goblin 3', pos: [15.5, 5.5], size: 1, actor: 'a_g3' },
  ];
  const cone: Shape = { type: 'cone', size: 3, angle: 53, origin: 'edge' };
  const at = { at: { x: 5.5, y: 5.5 }, direction: 0, fromSize: 1 };
  it('the creatures in it: not its caster, the dead, nor a thing', () => {
    expect(caught(sq, cone, at, tokens, 'me').map((t) => t.name)).toEqual(['Goblin 1']);
  });
  it('only what this screen was sent: a hidden goblin is never among them', () => {
    // Ben's screen was never sent Goblin 1 (hidden from him): his preview catches nobody
    const bens = tokens.filter((t) => t.id !== 'g1');
    expect(caught(sq, cone, at, bens, 'me')).toEqual([]);
    // the DM's has every one
    const dms = [...tokens, { id: 'hidden', name: 'Goblin 4', pos: [6.5, 5.5], size: 1, actor: 'a_g4', hidden: true }];
    expect(caught(sq, cone, at, dms, 'me').map((t) => t.name).sort()).toEqual(['Goblin 1', 'Goblin 4']);
  });
  it('round its caster: the caster too, unless it leaves them out (an emanation)', () => {
    const round: Shape = { type: 'circle', size: 2, include_self: true };
    expect(caught(sq, round, at, tokens, 'me').map((t) => t.id)).toContain('me');
    expect(caught(sq, { ...round, include_self: false }, at, tokens, 'me').map((t) => t.id)).not.toContain('me');
  });
});
