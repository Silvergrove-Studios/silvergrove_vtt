import { describe, expect, it } from 'vitest';
import { freshRolls, natural, rollSummary } from '../src/lib/rolls';
import { pillText } from '../src/lib/prompts';

const d20 = (face: number, kept = true) => ({ sides: 20, face, kept });

describe('natural', () => {
  it("takes the ruleset's natural die", () => {
    expect(natural({ result: { natural: 20, dice: [d20(20)] } })).toBe(20);
    expect(natural({ result: { natural: 1, dice: [d20(1)] } })).toBe(1);
    expect(natural({ result: { natural: 14, dice: [d20(14)] } })).toBeNull();
  });
  it('under advantage, the dropped 20 is no natural 20', () => {
    expect(natural({ result: { natural: 12, dice: [d20(12), d20(20, false)] } })).toBeNull();
  });
  it('reads a free roll of one d20', () => {
    expect(natural({ result: { dice: [d20(1)] } })).toBe(1);
    expect(natural({ result: { dice: [{ sides: 4, face: 4, kept: true }, { sides: 4, face: 1, kept: true }] } })).toBeNull();
    expect(natural({ result: { dice: [d20(20), d20(20)] } })).toBeNull();
  });
});

describe('rollSummary', () => {
  it('says the total, the outcome and a natural', () => {
    expect(rollSummary({ label: 'Perception check', result: { total: 17, outcome: 'success', natural: 15 } })).toBe('Perception check: 17, success');
    expect(rollSummary({ label: 'Persuasion check', result: { total: 22, outcome: 'success', natural: 20 } })).toBe('Persuasion check: 22, success (natural 20!)');
    expect(rollSummary({ label: 'Strength check', result: { total: 9, outcome: 'rolled', natural: 7 } })).toBe('Strength check: 9');
  });
});

describe('freshRolls', () => {
  it('primes on the first view, then finds only my new rolls', () => {
    const seen = new Set<string>();
    const mine = new Set(['a_ada']);
    const log = [{ id: 'r1', kind: 'roll', actor: 'a_ada' }, { id: 'c1', kind: 'chat' }];
    expect(freshRolls(log, mine, seen, false)).toEqual([]);
    const more = [...log, { id: 'r2', kind: 'roll', actor: 'a_zeb' }, { id: 'r3', kind: 'roll', actor: 'a_ada' }];
    expect(freshRolls(more, mine, seen, true).map((e) => e.id)).toEqual(['r3']);
    expect(freshRolls(more, mine, seen, true)).toEqual([]);
  });
});

describe('pillText', () => {
  it('says what the DM asks for', () => {
    const roll = { id: 'p1', form: { title: 'Deception check (DC 13)', choices: [{ id: 'skill:deception', label: 'Roll Deception +4' }] } };
    expect(pillText([roll])).toBe('The DM asks you to roll: Deception check (DC 13) ›');
    expect(pillText([{ id: 'p0', form: { title: 'Strike as they leave?' } }, roll])).toBe('The DM asks you to roll: Deception check (DC 13) (+1 more) ›');
    expect(pillText([{ id: 'p2', form: { title: 'Take the dare?' } }])).toBe('The DM asks: Take the dare? ›');
    expect(pillText([{ id: 'p3', form: {} }])).toBe('The DM is waiting for your answer ›');
    expect(pillText([])).toBe('');
  });
  it("names the character when I have more than one", () => {
    const roll = { id: 'p1', actor: 'a_b', form: { title: 'Perception check', choices: [{ id: 'skill:perception' }] } };
    expect(pillText([roll], { a_a: 'Ada', a_b: 'Bram' })).toBe('The DM asks you to roll (Bram): Perception check ›');
    expect(pillText([roll], { a_b: 'Bram' })).toBe('The DM asks you to roll: Perception check ›');
  });
});
