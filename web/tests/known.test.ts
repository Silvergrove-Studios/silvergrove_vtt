import { describe, expect, it } from 'vitest';
import { catchName, catchWords, UNKNOWN } from '../src/lib/map/marks';
import { capital, turnSummary } from '../src/lib/turns';
import { orderRows } from '../src/dm/fight';
import { pickChoices } from '../src/lib/map/pick';

// A creature the players don't know by name, as the table sends it to their
// screens (Knowledge): "a creature", its label "?" or a number, `unknown`.
const wren = { id: 't_wren', name: 'Wren', pos: [5.5, 5.5], size: 1, owner: 'pl_ana', actor: 'a_wren' };
const gob1 = { id: 't_g1', name: UNKNOWN, label: '1', unknown: true, pos: [6.5, 5.5], size: 1, actor: 'a_c1' };
const gob2 = { id: 't_g2', name: UNKNOWN, label: '2', unknown: true, pos: [7.5, 5.5], size: 1, actor: 'a_c2' };

describe('what the players know of a creature', () => {
  it('a template says the creatures it catches it knows by name, and counts the rest', () => {
    expect(catchName(gob1)).toBe('a creature');
    expect(catchName(wren)).toBe('Wren');
    expect(catchWords([UNKNOWN, UNKNOWN])).toBe('catches 2 creatures');
    expect(catchWords([UNKNOWN])).toBe('catches a creature');
    expect(catchWords(['Wren', UNKNOWN, UNKNOWN])).toBe('catches 3: Wren, 2 creatures');
    expect(catchWords(['Wren', UNKNOWN])).toBe('catches 2: Wren, a creature');
    // names known: as before
    expect(catchWords(['Goblin 1', 'Goblin 2'])).toBe('catches 2: Goblin 1, Goblin 2');
    expect(catchWords([])).toBe('catches nobody you can see');
  });
  it('a creature’s turn starts its sentence with a capital', () => {
    const turns = { mode: 'ordered', running: true, order: ['t_g1', 't_wren'], turn: 0, round: 2 };
    expect(turnSummary({ turns, tokens: [wren, gob1] }, 'pl_ana')).toEqual({ text: "A creature's turn (round 2)", mine: false });
    expect(capital('a creature')).toBe('A creature');
    expect(capital('')).toBe('');
  });
  it('a pick lists one by the label its screen knows it by', () => {
    const list = pickChoices([wren, gob1, gob2], { pick: 'token', ctx: { actor: 'a_wren' } });
    expect(list.map((c) => [c.name, c.label])).toEqual([
      ['a creature', '1'],
      ['a creature', '2'],
    ]);
  });
  it('the DM’s order says what the players call one whose name they don’t know', () => {
    const tokens = [
      { id: 't_g1', name: 'Goblin Warrior', actor: 'a_c1', name_known: false, player_label: '1' },
      { id: 't_g2', name: 'Goblin Boss', actor: 'a_c2', name_known: true },
      { id: 't_g3', name: 'Goblin Warrior 2', actor: 'a_c3', name_known: false, player_label: '?', hidden: true },
      { id: 't_wren', name: 'Wren', owner: 'pl_ana' },
    ];
    const scene = { id: 's1', tokens, turns: { mode: 'ordered', running: true, scene: 's1', order: ['t_g1', 't_g2', 't_g3', 't_wren'], turn: 0, round: 1 } };
    expect(orderRows(scene).map((r) => [r.name, r.playerLabel])).toEqual([
      ['Goblin Warrior', '1'],
      ['Goblin Boss', ''],
      // (hidden from the players: they don't call it anything)
      ['Goblin Warrior 2', ''],
      ['Wren', ''],
    ]);
  });
});
