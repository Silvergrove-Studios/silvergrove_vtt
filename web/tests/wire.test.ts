import { describe, expect, it } from 'vitest';
import { apply, Reader, schemaRecords, type Node } from '../src/lib/wire';
import type { Msg } from '../src/lib/net';

type Dict = Record<string, any>;

// The host's diff (hexmap/net/wire.gd), as the format says it: here to make
// patches to read back, random ones too.
function same(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}
function diff(old: any, now: any): Node {
  if (typeof old === typeof now && same(old, now) && Array.isArray(old) === Array.isArray(now)) return {};
  const dict = (v: any) => !!v && typeof v === 'object' && !Array.isArray(v);
  if (dict(old) && dict(now)) {
    const d: Record<string, Node> = {};
    const x: string[] = [];
    for (const k of Object.keys(now)) {
      if (!(k in old)) d[k] = { v: now[k] };
      else {
        const sub = diff(old[k], now[k]);
        if (Object.keys(sub).length) d[k] = sub;
      }
    }
    for (const k of Object.keys(old)) if (!(k in now)) x.push(k);
    const out: Node = {};
    if (Object.keys(d).length) out.d = d;
    if (x.length) out.x = x;
    return out;
  }
  if (Array.isArray(old) && Array.isArray(now)) {
    const m = Math.min(old.length, now.length);
    let p = 0;
    while (p < m && same(old[p], now[p])) p++;
    if (old.length === now.length) {
      const i: Record<string, Node> = {};
      for (let k = p; k < m; k++) {
        const sub = diff(old[k], now[k]);
        if (Object.keys(sub).length) i[String(k)] = sub;
      }
      return Object.keys(i).length ? { k: m, i } : {};
    }
    let s = 0;
    while (s < m - p && same(old[old.length - 1 - s], now[now.length - 1 - s])) s++;
    const out: Node = { k: p };
    if (now.length - s > p) out.a = now.slice(p, now.length - s);
    if (s > 0) out.s = s;
    return out;
  }
  return { v: now };
}

const wire = (m: Dict): Msg => JSON.parse(JSON.stringify(m));

describe('apply', () => {
  it('a value whole; a dictionary by what changed, what is new and what is gone', () => {
    expect(apply(1, { v: 'one' })).toBe('one');
    expect(apply({ a: 1, b: { c: 2, d: 3 }, gone: true }, { d: { b: { d: { c: { v: 4 } } }, e: { v: 5 } }, x: ['gone'] })).toEqual({ a: 1, b: { c: 4, d: 3 }, e: 5 });
    expect(apply({ a: 1 }, {})).toEqual({ a: 1 });
  });

  it('an array: the lines after those it had (the log), one changed in place, one taken out or put in the middle, cut short', () => {
    const log = [{ id: 'l1' }, { id: 'l2' }];
    expect(apply(log, { k: 2, a: [{ id: 'l3' }] })).toEqual([{ id: 'l1' }, { id: 'l2' }, { id: 'l3' }]);
    expect(apply(log, { k: 2, i: { '1': { d: { ruled: { v: 'a miss' } } } } })).toEqual([{ id: 'l1' }, { id: 'l2', ruled: 'a miss' }]);
    expect(apply(['a', 'b', 'c', 'd'], { k: 1, s: 2 })).toEqual(['a', 'c', 'd']);
    expect(apply(['a', 'c'], { k: 1, a: ['b'], s: 1 })).toEqual(['a', 'b', 'c']);
    expect(apply(['a', 'b', 'c'], { k: 1 })).toEqual(['a']);
    expect(apply(['a'], { k: 0 })).toEqual([]);
  });

  it('refuses a patch that does not fit what it is given', () => {
    expect(() => apply([1, 2], { k: 3 })).toThrow();
    expect(() => apply([1, 2], { k: 1, s: 2 })).toThrow();
    expect(() => apply([1, 2], { k: 1, i: { '1': { v: 0 } } })).toThrow();
    expect(() => apply({ a: 1 }, { k: 0 })).toThrow();
    expect(() => apply([1], { d: { a: { v: 1 } } })).toThrow();
    expect(() => apply({}, { d: { a: { k: 0 } } })).toThrow();
  });

  it('reads back whatever the host makes of a random change (300 random documents)', () => {
    let seed = 4711;
    const rand = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
    const int = (a: number, b: number) => a + Math.floor(rand() * (b - a + 1));
    const tree = (depth: number): any => {
      const pick = int(0, depth < 4 ? 9 : 4);
      if (pick === 0) return int(-5, 50);
      if (pick === 1) return Math.round(rand() * 2000) / 100;
      if (pick === 2) return ['fire', 'cold', '', 'Goblin 2'][int(0, 3)];
      if (pick === 3) return null;
      if (pick === 4) return rand() < 0.5;
      if (pick <= 7) {
        const d: Dict = {};
        for (let j = int(0, 5); j > 0; j--) d[`k${int(0, 7)}`] = tree(depth + 1);
        return d;
      }
      return Array.from({ length: int(0, 6) }, () => tree(depth + 1));
    };
    const mutate = (v: any, depth: number): any => {
      if (rand() < 0.15 || depth > 5) return tree(depth);
      if (Array.isArray(v)) {
        const r = int(0, 4);
        if (r === 0) v.push(tree(depth + 1));
        else if (r === 1 && v.length) v.splice(int(0, v.length - 1), 1);
        else if (r === 2) v.splice(int(0, v.length), 0, tree(depth + 1));
        else for (let j = 0; j < v.length; j++) if (rand() < 0.4) v[j] = mutate(v[j], depth + 1);
        return v;
      }
      if (v && typeof v === 'object') {
        for (const k of Object.keys(v)) {
          const r = rand();
          if (r < 0.15) delete v[k];
          else if (r < 0.5) v[k] = mutate(v[k], depth + 1);
        }
        if (rand() < 0.3) v[`n${int(0, 3)}`] = tree(depth + 1);
        return v;
      }
      return tree(depth);
    };
    for (let i = 0; i < 300; i++) {
      const a = tree(0);
      const b = mutate(structuredClone(a), 0);
      const got = apply(structuredClone(a), JSON.parse(JSON.stringify(diff(a, b))));
      expect(got).toEqual(b);
    }
  });
});

const SHEET = { type: 'column', children: [{ type: 'text', text: 'Hit points' }] };
const SHEET2 = { type: 'column', children: [{ type: 'text', text: 'By hand' }] };
const STATUS = { type: 'text', expr: "'Round ' .. @round" };
const CARD = { type: 'text', bind: '/entry/name' };
const PARTY = { type: 'column', children: [] };
const ids = { sheet: 't/sheet@1111', sheet2: 't/sheet@2222', status: 't/status@3333', card: 't/entry:spells@4444', party: 't/party@5555' };

/** A view as it comes: its schemas by id. */
function view(hp: number, sheet = ids.sheet): Dict {
  return {
    actors: { a_ana: { id: 'a_ana', sheets: [{ plugin: 't', schema_ref: sheet, data: { hp } }] }, a_ben: { id: 'a_ben', sheets: [{ plugin: 't', schema_ref: sheet, data: { hp: 8 } }] } },
    status: [{ plugin: 't', schema_ref: ids.status, data: { round: hp } }],
    cards: { spells: { plugin: 't', schema_ref: ids.card } },
    log: [{ id: 'l1', text: 'one' }],
  };
}

describe('Reader', () => {
  it('a view whole, its schemas put in their places (the sheet once for both actors)', () => {
    const r = new Reader();
    const got = r.read(wire({ t: 'view', n: 1, view: view(10), schemas: { [ids.sheet]: SHEET, [ids.status]: STATUS, [ids.card]: CARD } }));
    expect(got.added).toBe(true);
    const v = got.msg!.view as Dict;
    expect(v.actors.a_ana.sheets[0].schema).toEqual(SHEET);
    expect(v.actors.a_ben.sheets[0].schema).toEqual(SHEET);
    expect('schema_ref' in v.actors.a_ana.sheets[0]).toBe(false);
    expect(v.status[0].schema).toEqual(STATUS);
    expect(v.cards.spells.schema).toEqual(CARD);
    expect(v.actors.a_ana.sheets[0].data.hp).toBe(10);
  });

  it('then patches on the one before, each read whole, the screen’s copy its own', () => {
    const r = new Reader();
    r.read(wire({ t: 'view', n: 1, view: view(10), schemas: { [ids.sheet]: SHEET, [ids.status]: STATUS, [ids.card]: CARD } }));
    const first = r.read(wire({ t: 'view', n: 2, base: 1, patch: diff(view(10), view(7)) })).msg!.view as Dict;
    expect(first.actors.a_ana.sheets[0].data.hp).toBe(7);
    expect(first.status[0].data.round).toBe(7);
    expect(first.actors.a_ana.sheets[0].schema).toEqual(SHEET);
    // what a screen does with its copy is no matter to the next patch
    first.actors.a_ana.sheets[0].data.hp = 999;
    first.log.push({ id: 'mine' });
    const next = view(7);
    next.log.push({ id: 'l2', text: 'two' });
    const second = r.read(wire({ t: 'view', n: 3, base: 2, patch: diff(view(7), next) })).msg!.view as Dict;
    expect(second.actors.a_ana.sheets[0].data.hp).toBe(7);
    expect(second.log.map((e: Dict) => e.id)).toEqual(['l1', 'l2']);
    // nothing changed for this screen: nothing to draw again, and the next goes on from it
    expect(r.read(wire({ t: 'view', n: 4, base: 3, patch: {} }))).toEqual({ same: true, added: false });
    const after = view(1);
    after.log.push({ id: 'l2', text: 'two' });
    expect((r.read(wire({ t: 'view', n: 5, base: 4, patch: diff(next, after) })).msg!.view as Dict).status[0].data.round).toBe(1);
  });

  it('a sheet built anew: its new schema with the patch that needs it', () => {
    const r = new Reader();
    r.read(wire({ t: 'view', n: 1, view: view(10), schemas: { [ids.sheet]: SHEET, [ids.status]: STATUS, [ids.card]: CARD } }));
    const got = r.read(wire({ t: 'view', n: 2, base: 1, patch: diff(view(10), view(10, ids.sheet2)), schemas: { [ids.sheet2]: SHEET2 } }));
    expect((got.msg!.view as Dict).actors.a_ana.sheets[0].schema).toEqual(SHEET2);
    expect(got.added).toBe(true);
  });

  it('asks once for the whole when it cannot read one: a base it lacks, a schema it lacks', () => {
    const r = new Reader();
    r.read(wire({ t: 'view', n: 1, view: view(10), schemas: { [ids.sheet]: SHEET, [ids.status]: STATUS, [ids.card]: CARD } }));
    expect(r.read(wire({ t: 'view', n: 3, base: 2, patch: {} }))).toEqual({ need: true, added: false });
    expect(r.read(wire({ t: 'view', n: 4, base: 3, patch: {} }))).toEqual({ added: false });
    // the whole comes: read again
    expect((r.read(wire({ t: 'view', n: 5, view: view(3) })).msg!.view as Dict).status[0].data.round).toBe(3);
    // a patch that doesn't fit
    expect(r.read(wire({ t: 'view', n: 6, base: 5, patch: { d: { log: { k: 9 } } } })).need).toBe(true);
    const fresh = new Reader();
    expect(fresh.read(wire({ t: 'view', n: 1, view: view(10) })).need).toBe(true);
  });

  it("the DM's state by the view's ids, and a scene's fields", () => {
    const r = new Reader();
    r.read(wire({ t: 'view', n: 1, view: view(10), schemas: { [ids.sheet]: SHEET, [ids.status]: STATUS, [ids.card]: CARD } }));
    const state = { party_views: [{ plugin: 't', schema_ref: ids.party, data: {} }], cards: { spells: { plugin: 't', schema_ref: ids.card } }, campaign: { name: 'Chapel' } };
    const dm = r.read(wire({ t: 'dm', n: 1, state, schemas: { [ids.party]: PARTY } })).msg!;
    expect((dm.state as Dict).party_views[0].schema).toEqual(PARTY);
    expect((dm.state as Dict).cards.spells.schema).toEqual(CARD);
    const scene = { scene: { id: 's1', tokens: [{ id: 't1', pos: [1, 2] }] }, players: [], online: ['pl_ana'] };
    const s1 = r.read(wire({ t: 'scene', n: 1, ...scene })).msg!;
    expect(s1).toEqual({ t: 'scene', ...scene });
    const moved = structuredClone(scene);
    moved.scene.tokens[0].pos = [3, 2];
    const s2 = r.read(wire({ t: 'scene', n: 2, base: 1, patch: diff(scene, moved) })).msg!;
    expect(s2).toEqual({ t: 'scene', ...moved });
  });

  it('says on joining what it holds: once views have come, only what they use; kept across a reload', () => {
    const r = new Reader();
    expect(r.have()).toEqual([]);
    r.restore({ [ids.sheet]: SHEET, [ids.status]: STATUS, [ids.card]: CARD, [ids.sheet2]: SHEET2, bad: 'not a schema' });
    // a page just loaded holds what it kept
    expect(r.have().sort()).toEqual([ids.card, ids.sheet, ids.sheet2, ids.status].sort());
    r.read(wire({ t: 'view', n: 1, view: view(10) }));
    expect([...r.inUse()].sort()).toEqual([ids.card, ids.sheet, ids.status].sort());
    // a reconnect: the sheet no view uses any more is let go
    expect(r.have().sort()).toEqual([ids.card, ids.sheet, ids.status].sort());
    expect(Object.keys(r.keep()).sort()).toEqual([ids.card, ids.sheet, ids.status].sort());
    const again = new Reader();
    again.restore(JSON.parse(JSON.stringify(r.keep())));
    expect((again.read(wire({ t: 'view', n: 1, view: view(4) })).msg!.view as Dict).actors.a_ana.sheets[0].schema).toEqual(SHEET);
  });

  it('finds the records that hold schemas where views and DM states have them', () => {
    expect(schemaRecords('view', view(1)).length).toBe(4);
    expect(schemaRecords('dm', { party_views: [{}], cards: { a: {}, b: {} } }).length).toBe(3);
    expect(schemaRecords('scene', { scene: {} })).toEqual([]);
  });
});
