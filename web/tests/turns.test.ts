import { describe, expect, it } from 'vitest';
import { currentTurnTokens, movedOn, turnNote, turnSummary } from '../src/lib/turns';
import { orderRows } from '../src/dm/fight';

describe('turns', () => {
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
