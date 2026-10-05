import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import { amount, feetToUnits, gridless, ruleOf, snapPoint, straight, words } from '../src/lib/map/measure';

// The same distances the host's Measure counts (tests/suites/marks.gd, test_ruler_distances).
describe('a ruler’s distance, as the map counts it', () => {
  const sq = new Grid({ shape: 'square', columns: 20, rows: 14, distance: 5, units: 'ft' });
  const a = [
    { x: 0.5, y: 0.5 },
    { x: 3.5, y: 2.5 },
  ];
  it('counts squares by the diagonal rule', () => {
    expect(straight(sq, a, '5-5-5')).toBe(15);
    expect(straight(sq, a, '5-10-5')).toBe(20);
    expect(straight(sq, a, 'euclid')).toBeCloseTo(Math.sqrt(13) * 5);
    expect(amount(straight(sq, a, 'euclid'), 'ft')).toBe('18 ft');
  });
  it('counts 5-10-5’s second diagonal along the whole path', () => {
    const bent = [
      { x: 0.5, y: 0.5 },
      { x: 1.5, y: 1.5 },
      { x: 2.5, y: 2.5 },
    ];
    expect(straight(sq, bent, '5-10-5')).toBe(15);
    expect(straight(sq, [...bent, { x: 3.5, y: 3.5 }], '5-10-5')).toBe(20);
    expect(straight(sq, [{ x: 0.5, y: 0.5 }, { x: 4.5, y: 0.5 }, { x: 4.5, y: 3.5 }], '5-5-5')).toBe(35);
  });
  it('counts hexes by their steps, whatever the rule', () => {
    const hex = new Grid({ shape: 'hex', orientation: 'pointy', offset: 'odd', columns: 20, rows: 14, distance: 5 });
    const h0 = hex.center(hex.fromOffset(2, 3));
    const h1 = hex.center(hex.fromOffset(6, 3));
    for (const rule of ['5-5-5', '5-10-5', 'euclid'] as const) expect(straight(hex, [h0, h1], rule)).toBe(20);
  });
  it('goes by the map’s scale and unit', () => {
    const metric = new Grid({ shape: 'square', columns: 20, rows: 14, distance: 1.5, units: 'm' });
    const d = straight(metric, [{ x: 0.5, y: 0.5 }, { x: 3.5, y: 0.5 }]);
    expect(d).toBeCloseTo(4.5);
    expect(amount(d, 'm')).toBe('4.5 m');
  });
  it('goes point to point on a map with no grid drawn', () => {
    expect(straight(sq, [{ x: 1, y: 1 }, { x: 4, y: 5 }], '5-5-5', true)).toBe(25);
    expect(gridless({ style: { show_grid: false } })).toBe(true);
    expect(gridless({ style: {} })).toBe(false);
  });
  it('takes the scene’s rule, or every step a square', () => {
    expect(ruleOf({ measure: { diagonals: '5-10-5' } })).toBe('5-10-5');
    expect(ruleOf({ measure: { diagonals: '7-14-7' } })).toBe('5-5-5');
    expect(ruleOf({})).toBe('5-5-5');
  });
  it('says both where the walk is longer', () => {
    expect(words({ straight: 30, walk: 45, units: 'ft' })).toBe('30 ft straight, 45 ft to walk round');
    expect(words({ straight: 30, units: 'ft' })).toBe('30 ft');
    expect(words({ straight: 30, no_way: true, units: 'ft' })).toBe('30 ft straight; no way to walk there');
  });
  it('turns feet into the map’s cells by its scale', () => {
    expect(feetToUnits(20, sq)).toBe(4);
    const ten = new Grid({ shape: 'square', distance: 10, units: 'ft' });
    expect(feetToUnits(20, ten)).toBe(2);
    const metric = new Grid({ shape: 'square', distance: 1.5, units: 'm' });
    expect(feetToUnits(20, metric)).toBeCloseTo((20 * 0.3048) / 1.5);
  });
  it('snaps to a creature this screen shows, else the cell, never to one it doesn’t', () => {
    const shown = [{ id: 't1', pos: [6.5, 6.5], size: 1 }];
    expect(snapPoint(sq, { x: 6.2, y: 6.7 }, false, shown)).toEqual({ x: 6.5, y: 6.5 });
    // a creature hidden from this screen is not among its tokens: the cell's middle
    expect(snapPoint(sq, { x: 9.2, y: 9.7 }, false, shown)).toEqual({ x: 9.5, y: 9.5 });
    expect(snapPoint(sq, { x: 9.2, y: 9.7 }, true, shown)).toEqual({ x: 9.2, y: 9.7 });
  });
});
