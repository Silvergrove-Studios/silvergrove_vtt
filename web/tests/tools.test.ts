import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// what the tools send to the table, and what the page waits on
const h = vi.hoisted(() => ({ sent: [] as Record<string, any>[], submitted: [] as Record<string, any>[] }));
vi.mock('../src/lib/game.svelte', () => ({
  game: { role: 'player', me: 'pl_ana', view: { actors: { a_sela: { name: 'Sela' } } }, marks: {}, marksBorn: {}, players: [], packs: {} },
  send: (m: Record<string, any>) => {
    h.sent.push(JSON.parse(JSON.stringify(m)));
    return true;
  },
  notice: vi.fn(),
  submit: vi.fn(async (p: Record<string, any>) => {
    h.submitted.push(JSON.parse(JSON.stringify(p)));
    return { ok: true };
  }),
}));

import { Grid } from '../src/lib/grid';
import { game } from '../src/lib/game.svelte';
import { SEND_MS, abort, castHere, clearMine, done, drag, hover, ping, press, release, removeMark, startPing, startPreview, startRuler, startTemplate, stop, togglePin, tools, turn, type Where } from '../src/lib/map/tools.svelte';
import { markLine, placeLabel, rulerMeasure } from '../src/lib/map/marks';

const grid = new Grid({ shape: 'square', columns: 20, rows: 14, distance: 5, units: 'ft' });
const tokens = [
  { id: 't_sela', name: 'Sela', pos: [5.5, 5.5], size: 1, owner: 'pl_ana', actor: 'a_sela' },
  { id: 't_gob', name: 'Goblin 1', pos: [8.5, 5.5], size: 1, actor: 'a_gob' },
];
const where: Where = { grid, scene: { id: 's1', measure: { diagonals: '5-5-5' } }, map: { grid: {} }, tokens, scale: 40 };
const marks = () => h.sent.filter((m) => m.t === 'mark' && m.op === 'set').map((m) => m.mark);
const last = () => marks()[marks().length - 1];

beforeEach(() => {
  vi.useFakeTimers();
  h.sent.length = 0;
  h.submitted.length = 0;
  stop();
  h.sent.length = 0;
});
afterEach(() => {
  vi.useRealTimers();
  (game as any).role = 'player';
  tools.private = false;
});

describe('the ruler, on a phone and with a mouse', () => {
  it('tap to start, tap for each point, Done', () => {
    startRuler();
    expect(press(where, { x: 2.2, y: 2.7 })).toBe(true);
    release(where, { x: 2.2, y: 2.7 }, false);
    expect(tools.tapping).toBe(true);
    vi.advanceTimersByTime(SEND_MS);
    press(where, { x: 6.1, y: 2.4 });
    release(where, { x: 6.1, y: 2.4 }, false);
    vi.advanceTimersByTime(SEND_MS);
    press(where, { x: 6.3, y: 6.6 });
    release(where, { x: 6.3, y: 6.6 }, false);
    expect(tools.draft?.points).toEqual([[2.5, 2.5], [6.5, 2.5], [6.5, 6.5]]);
    expect(tools.draft?.live).toBe(true);
    done(where);
    // let go: it lingers on the table and goes, the tool put away
    expect(last()).toMatchObject({ kind: 'ruler', scene: 's1', live: false, points: [[2.5, 2.5], [6.5, 2.5], [6.5, 6.5]] });
    expect(tools.mode).toBe('');
    // the walk is the table's: counted here meanwhile, by the same rule
    expect(rulerMeasure(last(), { grid, rule: '5-5-5', noGrid: false }).straight).toBe(40);
  });
  it('drag from a point: measured, and let go when the press is', () => {
    startRuler();
    press(where, { x: 1.4, y: 1.4 });
    vi.advanceTimersByTime(SEND_MS);
    drag(where, { x: 3.6, y: 1.5 });
    vi.advanceTimersByTime(SEND_MS);
    drag(where, { x: 5.6, y: 1.5 });
    release(where, { x: 5.6, y: 1.5 }, true);
    expect(last()).toMatchObject({ kind: 'ruler', live: false, points: [[1.5, 1.5], [5.5, 1.5]] });
    // ready for another
    expect(tools.mode).toBe('ruler');
    expect(tools.draft).toBe(null);
  });
  it('follows the mouse from the last point, sent ten times a second at most', () => {
    startRuler();
    press(where, { x: 1.5, y: 1.5 });
    release(where, { x: 1.5, y: 1.5 }, false);
    const before = marks().length;
    for (let i = 0; i < 20; i++) {
      hover(where, { x: 2 + i * 0.5, y: 1.5 });
      vi.advanceTimersByTime(10);
    }
    const during = marks().length - before;
    expect(during).toBeGreaterThan(0);
    expect(during).toBeLessThan(5);
    vi.advanceTimersByTime(SEND_MS);
    // the last of them goes once its turn comes
    expect(last().points[1]).toEqual([11.5, 1.5]);
  });
  it('a pinch is no point: the ruler it would have started goes, a point it would have added isn’t', () => {
    startRuler();
    press(where, { x: 1.5, y: 1.5 });
    abort(where);
    expect(tools.draft).toBe(null);
    expect(h.sent.some((m) => m.op === 'remove')).toBe(true);
    press(where, { x: 1.5, y: 1.5 });
    release(where, { x: 1.5, y: 1.5 }, false);
    press(where, { x: 6.5, y: 1.5 });
    abort(where);
    expect(tools.draft?.points).toEqual([[1.5, 1.5], [1.5, 1.5]]);
    press(where, { x: 3.5, y: 1.5 });
    release(where, { x: 3.5, y: 1.5 }, false);
    expect(tools.draft?.points).toEqual([[1.5, 1.5], [3.5, 1.5]]);
  });
  it('snaps to a creature it shows, else the middle of a cell', () => {
    startRuler();
    press(where, { x: 8.2, y: 5.2 });
    expect(tools.draft?.points[0]).toEqual([8.5, 5.5]);
  });
});

describe('a template, a ping, a preview', () => {
  it('a template: its shape and size in feet, put where tapped, turned and pinned', () => {
    startTemplate();
    tools.shape = 'cone';
    tools.feet = 15;
    expect(press(where, { x: 10.2, y: 3.9 })).toBe(true);
    expect(last()).toMatchObject({ kind: 'template', points: [[10.5, 3.5]], shape: { type: 'cone', size: 3 }, label: '15-ft cone' });
    turn(15);
    expect(last().direction).toBe(15);
    togglePin();
    expect(last().pinned).toBe(true);
    // a press on it moves it, by its middle
    expect(press(where, { x: 10.6, y: 3.4 })).toBe(true);
    drag(where, { x: 12.6, y: 6.4 });
    release(where, { x: 12.6, y: 6.4 }, true);
    expect(last()).toMatchObject({ points: [[12.5, 6.5]], live: false, pinned: true });
    done(where);
    expect(tools.mode).toBe('');
  });
  it('a ping: where it is tapped', () => {
    startPing();
    press(where, { x: 4.25, y: 7.75 });
    expect(last()).toMatchObject({ kind: 'ping', points: [[4.25, 7.75]] });
    expect(tools.mode).toBe('');
    ping(where, { x: 1, y: 1 });
    expect(last().kind).toBe('ping');
  });
  it('a preview from its caster: at once, facing the nearest creature; Cast here casts it as it faces', async () => {
    const cast = { kind: 'action', plugin: 'rules', action: 'cast', ctx: { actor: 'a_sela', spell: 'burning-hands' }, pick: 'area', area: { shape: 'cone' }, label: 'Cast' };
    startPreview({ kind: 'preview', actor: 'a_sela', area: { from: 'self', type: 'cone', size: 3, angle: 53, origin: 'edge', label: 'Burning Hands, 15-ft cone' }, cast }, where);
    expect(tools.mode).toBe('preview');
    expect(last()).toMatchObject({ kind: 'preview', token: 't_sela', points: [[5.5, 5.5]], label: 'Burning Hands, 15-ft cone', direction: 0, actor: 'a_sela' });
    turn(-90);
    await castHere(where);
    expect(h.submitted[0]).toMatchObject({ kind: 'action', action: 'cast', ctx: { actor: 'a_sela', spell: 'burning-hands', target: { at: 'token:t_sela', direction: -90 }, scene: 's1' } });
    expect(h.submitted[0].pick).toBeUndefined();
    // taken: the preview goes
    expect(h.sent.some((m) => m.op === 'remove')).toBe(true);
    expect(tools.mode).toBe('');
  });
  it('a preview put within range: where tapped, its cast at that cell', async () => {
    const cast = { kind: 'action', action: 'cast', ctx: { actor: 'a_sela', spell: 'fireball' }, pick: 'area' };
    startPreview({ kind: 'preview', actor: 'a_sela', area: { from: 'point', type: 'circle', size: 4, label: 'Fireball, 20-ft sphere' }, cast }, where);
    expect(tools.draft).toBe(null);
    press(where, { x: 12.3, y: 8.8 });
    expect(last()).toMatchObject({ kind: 'preview', points: [[12.5, 8.5]], shape: { type: 'circle', size: 4 } });
    await castHere(where);
    expect(h.submitted[0].ctx.target).toEqual({ at: '12,8', direction: 0 });
  });
  it('one round its caster with nothing to aim (an emanation): cast as it is', async () => {
    const cast = { kind: 'action', action: 'cast', ctx: { actor: 'a_sela', spell: 'spirit-guardians' }, pick: '' };
    startPreview({ kind: 'preview', actor: 'a_sela', area: { from: 'self', type: 'circle', size: 3, include_self: false, label: 'Spirit Guardians, 15-ft emanation' }, cast }, where);
    await castHere(where);
    expect(h.submitted[0].ctx).toEqual({ actor: 'a_sela', spell: 'spirit-guardians', scene: 's1' });
  });
  it('a preview from a caster who isn’t on the map says so', () => {
    startPreview({ kind: 'preview', actor: 'a_nobody', area: { from: 'self', type: 'cone', size: 3, label: 'x' } }, where);
    expect(tools.mode).toBe('');
  });
});

describe('the marks’ words on the map', () => {
  const px = 0.025; // (40 px a square)
  const view = { x0: 0, y0: 0, x1: 10, y1: 8 };
  it('beside the place, up and to the right', () => {
    const b = placeLabel({ x: 2, y: 3 }, 3, 0.5, px, [], view);
    expect(b.x0).toBeCloseTo(2.25);
    expect(b.y1).toBeLessThanOrEqual(3);
  });
  it('to the left when it would run off the right of the view', () => {
    const b = placeLabel({ x: 9, y: 3 }, 3, 0.5, px, [], view);
    expect(b.x1).toBeLessThanOrEqual(9);
  });
  it('clear of the words already there: a ruler ending where a preview is', () => {
    const placed: { x0: number; y0: number; x1: number; y1: number }[] = [];
    const a = placeLabel({ x: 4, y: 4 }, 3, 0.5, px, placed, view);
    const b = placeLabel({ x: 4, y: 4 }, 2, 0.5, px, placed, view);
    expect(b.y0).toBeGreaterThanOrEqual(a.y1);
  });
});

describe('the DM’s marks and the list', () => {
  it('Only me keeps the DM’s marks to the DM', () => {
    (game as any).role = 'dm';
    tools.private = true;
    startPing();
    press(where, { x: 3, y: 3 });
    expect(last().private).toBe(true);
  });
  it('a player’s are never sent private', () => {
    tools.private = true;
    startPing();
    press(where, { x: 3, y: 3 });
    expect(last().private).toBeUndefined();
  });
  it('clear mine, take one off', () => {
    clearMine();
    expect(h.sent.some((m) => m.t === 'mark' && m.op === 'clear' && m.whose === undefined)).toBe(true);
    removeMark('pr-x-1-abc');
    expect(h.sent.some((m) => m.t === 'mark' && m.op === 'remove' && m.id === 'pr-x-1-abc')).toBe(true);
  });
  it('says each in words: whose, what, and who a template would catch here', () => {
    const look = { grid, rule: '5-5-5' as const, noGrid: false, tokens };
    expect(markLine({ kind: 'ruler', name: 'Wren', points: [[1.5, 1.5], [6.5, 1.5]], measure: { straight: 30, walk: 45, units: 'ft' } }, look)).toEqual({ who: 'Wren', what: 'ruler: 30 ft straight, 45 ft to walk round', catches: [] });
    const pv = { kind: 'preview', name: 'Sela', label: 'Fireball, 20-ft sphere', points: [[8.5, 5.5]], shape: { type: 'circle', size: 4 } };
    expect(markLine(pv, look).catches).toEqual(['Sela', 'Goblin 1']);
    // a screen without the goblin (hidden from it) never names it
    expect(markLine(pv, { ...look, tokens: [tokens[0]] }).catches).toEqual(['Sela']);
    // nor one whose name it doesn't know: "a creature", as the table sends it
    expect(markLine(pv, { ...look, tokens: [tokens[0], { ...tokens[1], name: 'a creature', label: '?', unknown: true }] }).catches).toEqual(['Sela', 'a creature']);
  });
});
