import { describe, expect, it } from 'vitest';
import { currentTurnTokens, movedOn, turnNote, turnSummary, turnWaiting } from '../src/lib/turns';
import { orderRows } from '../src/dm/fight';

describe('turns', () => {
  // a card a turn's end or start waits on (the host's turn steps: a roll its
  // roller makes) is in the waiting list marked `turn`; the screens say the
  // turn waits on it, and on whom
  it('says on whom the turn waits', () => {
    const waiting = [
      { id: 'p1', to: 'pl_a', who: 'Ana', what: 'a death saving throw (Brann)', turn: true },
      { id: 'p2', to: 'pl_b', who: 'Bo', what: 'a reaction (Sela)' },
    ];
    expect(turnWaiting(waiting, 'pl_c')).toBe('waiting on Ana: a death saving throw (Brann)');
    expect(turnWaiting(waiting, 'pl_a')).toBe('waiting on you: a death saving throw (Brann)');
    expect(turnWaiting([{ id: 'p3', to: 'gm', who: 'the DM', what: 'a roll', turn: true }], '', true)).toBe('waiting on you: a roll');
    expect(turnWaiting([{ id: 'p3', to: 'gm', who: 'the DM', what: 'a roll', turn: true }], 'pl_a')).toBe('waiting on the DM: a roll');
    // a reaction's card isn't the turn's; nothing waiting, nothing said
    expect(turnWaiting([waiting[1]], 'pl_c')).toBe('');
    expect(turnWaiting(undefined, 'pl_c')).toBe('');
  });
  const tokens = [
    { id: 't1', name: 'Wren', owner: 'pl_a' },
    { id: 'g1', name: 'Goblin' },
    { id: 'g2', name: 'Goblin 2' },
  ];
  it('says whose turn it is', () => {
    const turns = { mode: 'ordered', running: true, order: ['g1', 't1'], turn: 1, round: 2 };
    expect(turnSummary({ turns, tokens }, 'pl_a')).toEqual({ text: 'Your turn: Wren (round 2)', mine: true });
    expect(turnSummary({ turns: { ...turns, turn: 0 }, tokens }, 'pl_a')).toEqual({ text: "Goblin's turn (round 2)", mine: false });
    expect(turnSummary({ turns: { mode: 'free' }, tokens }, 'pl_a').text).toBe('Free movement');
    expect(turnSummary({ turns: { mode: 'dm', active: ['t1'] }, tokens }, 'pl_a')).toEqual({ text: 'You may move: Wren', mine: true });
  });
  // (the ruleset's line for a turn, `turns.data.notes`: its movement left, which
  // nothing counted before — a player's header, the DM's order and fight bar)
  it('says what is left of a turn, where the ruleset says it', () => {
    const turns = { mode: 'ordered', running: true, order: ['g1', 't1'], turn: 1, round: 2, data: { notes: { t1: 'Movement 15 of 30 ft' } } };
    expect(turnSummary({ turns, tokens }, 'pl_a')).toEqual({ text: 'Your turn: Wren (round 2)', mine: true, note: 'Movement 15 of 30 ft' });
    // another's turn: the player isn't told theirs
    expect(turnSummary({ turns: { ...turns, turn: 0, data: { notes: { g1: 'Movement 30 of 30 ft' } } }, tokens }, 'pl_a')).toEqual({ text: "Goblin's turn (round 2)", mine: false });
    expect(turnNote(turns, ['g1', 't1'])).toBe('Movement 15 of 30 ft');
    expect(turnNote({ data: { notes: false } }, ['t1'])).toBe('');
    expect(turnNote({ data: { notes: [] } }, ['t1'])).toBe('');
    expect(turnNote({}, ['t1'])).toBe('');
    // the DM's order: the line under the one whose turn it is
    const scene = { id: 's1', turns: { ...turns, scene: 's1' }, tokens };
    expect(orderRows(scene).map((r) => [r.name, r.note])).toEqual([
      ['Goblin', ''],
      ['Wren', 'Movement 15 of 30 ft'],
    ]);
  });
  // (the table sends a player no part of the order of a creature they don't
  // see: on its turn nobody is up for them, and their header says what it
  // says while the DM narrates — never "Round 2" with nobody, which told
  // them a creature they couldn't see was acting)
  it('reads the turn of a creature this screen is not sent as the DM’s', () => {
    const turns = { mode: 'ordered', running: true, order: ['g1', 't1'], turn: -1, round: 2 };
    expect(turnSummary({ turns, tokens }, 'pl_a')).toEqual({ text: "The DM's turn (round 2)", mine: false });
    // nor does an entry it was sent but cannot draw (a creature out of its sight) say more
    expect(turnSummary({ turns: { ...turns, order: ['gx', 't1'], turn: 0 }, tokens }, 'pl_a')).toEqual({ text: "The DM's turn (round 2)", mine: false });
  });
  it('knows a group acts together', () => {
    const turns = { mode: 'ordered', running: true, order: ['group:gob', 't1'], turn: 0, data: { groups: { gob: { tokens: ['g1', 'g2'] } } } };
    expect(currentTurnTokens(turns, tokens)).toEqual(['g1', 'g2']);
  });
  it('tells a player the DM ended their turn, and not otherwise', () => {
    const turns = { mode: 'ordered', running: true, order: ['t1', 'g1'], turn: 1, round: 2, last: { by: 'gm', entry: 't1', round: 2, turn: 0 } };
    expect(movedOn({ turns, tokens }, { round: 2, turn: 0 })).toBe("The DM moved on: it's Goblin's turn.");
    expect(movedOn({ turns: { ...turns, last: { ...turns.last, by: 'pl_a' } }, tokens }, { round: 2, turn: 0 })).toBe('');
    expect(movedOn({ turns, tokens }, { round: 1, turn: 0 })).toBe('');
    expect(movedOn({ turns, tokens: [tokens[0]] }, { round: 2, turn: 0 })).toBe('The DM moved on.');
  });
});
