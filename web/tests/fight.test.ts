import { describe, expect, it } from 'vitest';
import { endedByPlayer, entryName, nothingSince, turnAfter } from '../src/dm/fight';

describe('the fight on the DM’s screen', () => {
  const tokens = [
    { id: 't_ada', name: 'Ada Vex', owner: 'pl_ada', pos: [2, 2] },
    { id: 't_grace', name: 'Grace', owner: 'pl_grace', pos: [3, 2] },
    { id: 't_g1', name: 'Goblin Warrior', pos: [6, 4] },
  ];
  const players = ['pl_ada', 'pl_grace'];
  // Ada's player ended her turn (round 2, turn 0): Grace's turn began with the note as the newest entry
  const turns = {
    mode: 'ordered',
    running: true,
    order: ['t_ada', 't_grace', 't_g1'],
    round: 2,
    turn: 1,
    last: { by: 'pl_ada', entry: 't_ada', round: 2, turn: 0, log: 'n_end', pos: { t_grace: [3, 2] } },
  };
  const scene = { id: 's1', tokens, turns };
  const log = [
    { id: 'm_1', kind: 'chat', text: 'go on' },
    { id: 'n_end', kind: 'note', text: 'Ada Vex ends their turn' },
  ];

  it('names order entries and the turn after one', () => {
    expect(entryName(turns, tokens, 't_grace')).toBe('Grace');
    expect(entryName({ data: { groups: { gob: { label: 'Goblins', tokens: ['t_g1'] } } } }, tokens, 'group:gob')).toBe('Goblins');
    expect(turnAfter(2, 1, 3)).toEqual({ round: 2, turn: 2 });
    expect(turnAfter(2, 2, 3)).toEqual({ round: 3, turn: 0 });
  });

  it('says a player ended the turn before this one', () => {
    expect(endedByPlayer(scene, players)).toBe('Ada Vex');
    // the DM's own Next, a turn stepped back to, turns that stopped: nothing to say
    expect(endedByPlayer({ ...scene, turns: { ...turns, last: { ...turns.last, by: 'gm' } } }, players)).toBe('');
    expect(endedByPlayer({ ...scene, turns: { ...turns, turn: 0 } }, players)).toBe('');
    expect(endedByPlayer({ ...scene, turns: { ...turns, running: false } }, players)).toBe('');
  });

  it('asks before a Next that would end a turn nothing has happened in', () => {
    expect(nothingSince(scene, log, players)).toEqual({ ended: 'Ada Vex', up: 'Grace' });
    // what the DM says about the turn gone by is not something happening on this one
    expect(nothingSince(scene, [...log, { id: 'm_2', kind: 'chat', text: 'Ada’s arrow misses' }], players)).not.toBeNull();
    // a roll or a note since, or Grace moved: her turn is under way
    expect(nothingSince(scene, [...log, { id: 'r_1', kind: 'roll', label: 'Grace: Attack' }], players)).toBeNull();
    expect(nothingSince(scene, [...log, { id: 'n_2', kind: 'note', text: 'Grace takes the Dodge action' }], players)).toBeNull();
    const moved = tokens.map((t) => (t.id === 't_grace' ? { ...t, pos: [4, 2] } : t));
    expect(nothingSince({ ...scene, tokens: moved }, log, players)).toBeNull();
    // the DM ended the turn before: nothing to ask
    expect(nothingSince({ ...scene, turns: { ...turns, last: { ...turns.last, by: 'gm' } } }, log, players)).toBeNull();
    // a log this screen can't place the turn in: go on
    expect(nothingSince(scene, [log[0]], players)).toBeNull();
  });
});
