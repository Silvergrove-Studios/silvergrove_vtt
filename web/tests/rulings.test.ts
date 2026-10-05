import { describe, expect, it } from 'vitest';
import { dmActions, dmWaiting } from '../src/lib/rulings';
import { waitingOn, waitingText } from '../src/lib/prompts';

const miss = { id: 'miss', label: 'Call it a miss', hint: 'Heals back what it dealt', intent: { kind: 'action', plugin: 'srd5e', action: 'ruling', ctx: { roll: 'r_1', how: 'miss' } } };
const total = { id: 'total', label: 'Change the total', intent: { kind: 'action', plugin: 'srd5e', action: 'ruling', ctx: { roll: 'r_1', how: 'total' } } };

describe("the DM's buttons on a line of the log", () => {
  it("are every ruleset's, from its part of the entry's dm block, in their order", () => {
    const entry = { id: 'r_1', kind: 'roll', dm: { srd5e: { rule: { kind: 'attack' }, actions: [miss, total] }, 'house.rules': { actions: [{ id: 'x', label: 'Flip it', intent: { kind: 'action' } }] } } };
    const acts = dmActions(entry);
    expect(acts.map((a) => `${a.plugin}:${a.label}`)).toEqual(['house.rules:Flip it', 'srd5e:Call it a miss', 'srd5e:Change the total']);
    expect(acts[1].hint).toBe('Heals back what it dealt');
    expect(acts[1].intent.ctx.how).toBe('miss');
  });

  it("are none on a player's line (the Table sends no dm block), nor any without a label or an intent", () => {
    expect(dmActions({ id: 'r_1', kind: 'roll', result: { total: 14 } })).toEqual([]);
    expect(dmActions({ id: 'r_1', dm: { srd5e: { actions: [{ id: 'a', label: '', intent: {} }, { id: 'b', label: 'No intent' }] } } })).toEqual([]);
    expect(dmActions({ id: 'r_1', dm: { srd5e: 'nonsense' } })).toEqual([]);
    expect(dmActions(null)).toEqual([]);
  });

  it("wait for the DM, shown at once, when a ruleset's block says so (an outcome to apply)", () => {
    const apply = { id: 'apply', label: 'Apply', intent: { kind: 'action' } };
    expect(dmWaiting({ id: 'n_1', kind: 'note', dm: { srd5e: { waiting: true, actions: [apply] } } })).toBe(true);
    expect(dmWaiting({ id: 'r_1', kind: 'roll', dm: { srd5e: { actions: [miss] } } })).toBe(false);
    // (once done, nothing waits: no buttons)
    expect(dmWaiting({ id: 'n_1', kind: 'note', dm: { srd5e: { waiting: true, actions: [] } } })).toBe(false);
  });
});

describe('what the table waits on, on the DM’s screen', () => {
  const approve = { id: 'p_1', to: 'gm', who: 'the DM', what: 'an outcome to approve' };
  const shield = { id: 'p_2', to: 'pl_ana', who: 'Ana', what: 'a reaction (Sela)' };
  it("lists the players' cards, and the DM's own only once put aside", () => {
    expect(waitingOn([approve, shield], '', true).map((w) => w.id)).toEqual(['p_2']);
    expect(waitingOn([approve, shield], '', true, ['p_1']).map((w) => w.id)).toEqual(['p_1', 'p_2']);
    // a player sees the DM's: the table waits on the DM
    expect(waitingOn([approve, shield], 'pl_ben', false).map((w) => w.id)).toEqual(['p_1', 'p_2']);
  });
  it("calls the DM's own 'you' there, and the DM elsewhere", () => {
    expect(waitingText(approve, '', null, true)).toBe('Waiting on you: an outcome to approve');
    expect(waitingText(approve, 'pl_ben', null)).toBe('Waiting on the DM: an outcome to approve');
  });
});
