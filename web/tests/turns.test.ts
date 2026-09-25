import { describe, expect, it } from 'vitest';
import { currentTurnTokens, turnSummary } from '../src/lib/turns';

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
  it('knows a group acts together', () => {
    const turns = { mode: 'ordered', running: true, order: ['group:gob', 't1'], turn: 0, data: { groups: { gob: { tokens: ['g1', 'g2'] } } } };
    expect(currentTurnTokens(turns, tokens)).toEqual(['g1', 'g2']);
  });
});
