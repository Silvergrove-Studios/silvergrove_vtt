import { describe, expect, it } from 'vitest';
import {
  bonusProblem,
  canLower,
  canRaise,
  chooseProblem,
  fieldProblem,
  finalScores,
  pointBuy,
  resolve,
  scoresProblem,
  scoresValue,
  spent,
  startingBase,
  startingBonus,
  suggestedBase,
  toggle,
} from '../src/lib/views/fieldcheck';

const STATS = ['str', 'dex', 'con', 'int', 'wis', 'cha'].map((id) => ({ id, name: id.toUpperCase() }));
const DRUID = { str: 8, dex: 12, con: 14, int: 13, wis: 15, cha: 10 };

function scores(method: string, extra: Record<string, unknown> = {}) {
  return { key: 'abilities', type: 'scores', stats: STATS, method, array: [15, 14, 13, 12, 10, 8], ...extra };
}

describe('resolve', () => {
  it('works out {expr} properties against the answers and what they picked', () => {
    const ctx = { values: { class: 'druid' }, chosen: { class: { skill_choices: { count: 2, from: ['arcana', 'nature'] } } } };
    const f = resolve({ count: { expr: '@chosen.class.skill_choices.count' }, allowed: { expr: '@chosen.class.skill_choices.from' }, query: { filter: { classes: { expr: '@values.class' }, level: 0 } }, if: '@x' }, ctx);
    expect(f.count).toBe(2);
    expect(f.allowed).toEqual(['arcana', 'nature']);
    expect(f.query.filter).toEqual({ classes: 'druid', level: 0 });
    expect(f.if).toBe('@x');
  });
  it('falls back to a default when the answer is not there yet', () => {
    expect(resolve({ n: { expr: '@chosen.class.count', default: 0 } }, {}).n).toBe(0);
  });
});

describe('point buy', () => {
  const f = scores('point_buy');
  const pb = pointBuy(f);
  it('prices scores as the SRD does: 27 points, 8 to 15', () => {
    expect(pb).toMatchObject({ budget: 27, min: 8, max: 15 });
    expect(spent(DRUID, pb)).toBe(27);
    expect(spent({ str: 15, dex: 15, con: 15, int: 8, wis: 8, cha: 8 }, pb)).toBe(27);
  });
  it('lets a score go up only while the points last, and not past 15 or below 8', () => {
    const all8 = { str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8 };
    expect(canRaise('str', all8, pb)).toBe(true);
    expect(canLower('str', all8, pb)).toBe(false);
    expect(canRaise('wis', DRUID, pb)).toBe(false);
    expect(canRaise('str', { ...all8, str: 15 }, pb)).toBe(false);
    // one point left but a 13 costs two to raise
    const oneLeft = { str: 13, dex: 13, con: 13, int: 13, wis: 13, cha: 9 };
    expect(spent(oneLeft, pb)).toBe(26);
    expect(canRaise('str', oneLeft, pb)).toBe(false);
    expect(canRaise('cha', oneLeft, pb)).toBe(true);
  });
  it('starts from 8s: the class suggestion is the player’s to ask for, and a valid buy', () => {
    expect(startingBase(scores('point_buy', { suggest: DRUID }))).toEqual({ str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8 });
    expect(suggestedBase(scores('point_buy', { suggest: DRUID }))).toEqual(DRUID);
    expect(suggestedBase(f)).toEqual({ str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8 });
  });
  it('will not move on with points to spend, over the budget or out of range', () => {
    const all8 = { str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 8 };
    expect(scoresProblem(f, scoresValue(f, all8, {}))).toMatch(/27 points left/);
    expect(scoresProblem(f, scoresValue(f, { ...DRUID, str: 9 }, {}))).toMatch(/1 more point/);
    expect(scoresProblem(f, scoresValue(f, { ...DRUID, wis: 17 }, {}))).toMatch(/from 8 to 15/);
    expect(scoresProblem(f, scoresValue(f, DRUID, {}))).toBe('');
    // a point that cannot buy anything is not a mistake
    const stuck = { str: 13, dex: 13, con: 13, int: 13, wis: 13, cha: 13 };
    expect(spent(stuck, pb)).toBe(30);
    const stuck2 = { str: 15, dex: 15, con: 13, int: 8, wis: 8, cha: 9 };
    expect(spent(stuck2, pb)).toBe(24);
    expect(scoresProblem(f, scoresValue(f, stuck2, {}))).toMatch(/3 points left/);
  });
});

describe('the standard array and rolled scores', () => {
  it('starts with no number given; asked, puts them highest-first where the class wants them', () => {
    expect(startingBase(scores('array', { suggest: DRUID }))).toEqual({ str: null, dex: null, con: null, int: null, wis: null, cha: null });
    expect(suggestedBase(scores('array', { suggest: DRUID }))).toEqual({ str: 8, dex: 12, con: 14, int: 13, wis: 15, cha: 10 });
    const rolled = scores('rolled', { suggest: DRUID, rolled: { values: [9, 17, 12, 11, 14, 6] } });
    expect(Object.values(startingBase(rolled)).every((v) => v === null)).toBe(true);
    expect(suggestedBase(rolled)).toEqual({ wis: 17, con: 14, int: 12, dex: 11, cha: 9, str: 6 });
  });
  it('asks for every number to be given before moving on', () => {
    const f = scores('array');
    const half = { str: 15, dex: 14, con: 13, int: null, wis: null, cha: null };
    expect(scoresProblem(f, scoresValue(f, half, {}))).toBe('Give a number to each ability (3 to go).');
    expect(scoresValue(f, half, {}).final.int).toBeNull();
  });
  it('uses each number once', () => {
    const f = scores('array');
    expect(scoresProblem(f, scoresValue(f, DRUID, {}))).toBe('');
    expect(scoresProblem(f, scoresValue(f, { ...DRUID, str: 15 }, {}))).toMatch(/each of 15, 14, 13, 12, 10, 8 once/);
  });
  it('asks for the roll before anything else', () => {
    const f = scores('rolled', { rolled: { values: null } });
    expect(scoresProblem(f, null)).toBe('Roll your scores first.');
    const g = scores('rolled', { rolled: { values: [10, 11, 12, 13, 14, 15] } });
    expect(scoresProblem(g, scoresValue(g, { str: 10, dex: 11, con: 12, int: 13, wis: 14, cha: 15 }, {}))).toBe('');
    expect(scoresProblem(g, scoresValue(g, DRUID, {}))).toMatch(/each of/);
  });
});

describe('the background bonus', () => {
  const f = scores('array', { primary: ['wis'], bonus: { among: ['dex', 'con', 'int'], patterns: [[2, 1], [1, 1, 1]], cap: 20 } });
  it('puts +2 on the class key ability when offered, else the first offered, and +1 on the next', () => {
    expect(startingBonus(f)).toEqual({ dex: 2, con: 1 });
    expect(startingBonus({ ...f, primary: ['con'] })).toEqual({ con: 2, dex: 1 });
  });
  it('takes +2/+1 or +1/+1/+1 on the offered three, nothing else', () => {
    expect(bonusProblem(f, { dex: 2, con: 1 })).toBe('');
    expect(bonusProblem(f, { dex: 1, con: 1, int: 1 })).toBe('');
    expect(bonusProblem(f, { dex: 2 })).toMatch(/\+2 and \+1/);
    expect(bonusProblem(f, { wis: 2, con: 1 })).toMatch(/own three/);
    expect(bonusProblem(f, { dex: 2, con: 2 })).toMatch(/\+2 and \+1/);
  });
  it('adds up to the final scores, capped at 20', () => {
    expect(finalScores(f, DRUID, { dex: 2, con: 1 })).toMatchObject({ dex: 14, con: 15, wis: 15 });
    expect(finalScores(f, { ...DRUID, dex: 19 }, { dex: 2 })).toMatchObject({ dex: 20 });
  });
});

describe('choose', () => {
  const skills = { key: 'skills', type: 'choose', count: 2, allowed: ['arcana', 'nature', 'perception'], fixed: ['stealth'] };
  const opts = ['arcana', 'nature', 'perception', 'stealth', 'athletics'].map((id) => ({ id, name: id }));
  it('counts down to the number the class gives', () => {
    expect(chooseProblem(skills, [], opts)).toBe('Choose 2 more.');
    expect(chooseProblem(skills, ['arcana'], opts)).toBe('Choose 1 more.');
    expect(chooseProblem(skills, ['arcana', 'nature'], opts)).toBe('');
  });
  it('refuses what is not on offer or is had already', () => {
    expect(chooseProblem(skills, ['arcana', 'athletics'], opts)).toMatch(/not on offer/);
    expect(chooseProblem(skills, ['arcana', 'stealth'], opts)).toMatch(/yours already/);
  });
  it('stops at the limit and lets a pick go again', () => {
    expect(toggle(skills, ['arcana', 'nature'], 'perception')).toEqual(['arcana', 'nature']);
    expect(toggle(skills, ['arcana', 'nature'], 'nature')).toEqual(['arcana']);
    expect(toggle(skills, ['arcana'], 'nature')).toEqual(['arcana', 'nature']);
  });
  it('a single choice is one id', () => {
    const kit = { key: 'kit', type: 'choose', single: true };
    expect(toggle(kit, 'a', 'b')).toBe('b');
    expect(chooseProblem(kit, '', null)).toBe('Choose one.');
    expect(chooseProblem(kit, 'b', null)).toBe('');
  });
  it('a required text field must be filled in', () => {
    expect(fieldProblem({ key: 'name', label: 'Name', required: true }, '  ')).toMatch(/Name/);
    expect(fieldProblem({ key: 'name', label: 'Name', required: true }, 'Lia')).toBe('');
  });
});
