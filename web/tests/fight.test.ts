import { describe, expect, it } from 'vitest';
import { endedByPlayer, entryName, nothingSince, orderRows, turnAfter, unusedOnTurn } from '../src/dm/fight';

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

  it('asks before a Next that would end a player’s turn with an action or a bonus action unused', () => {
    // Grace's turn: her counters as the ruleset reset them when it began
    const at = (counters: Record<string, unknown>, extra: Record<string, unknown> = {}) => ({ ...scene, turns: { ...turns, counters, ...extra } });
    expect(unusedOnTurn(at({ 'token:t_grace': { actions: 1, bonus: 1, reactions: 1 } }), players)).toBe('Grace still has an action and a bonus action.');
    expect(unusedOnTurn(at({ 'token:t_grace': { actions: 0, bonus: 1, reactions: 1 } }), players)).toBe('Grace still has a bonus action.');
    expect(unusedOnTurn(at({ 'token:t_grace': { actions: 1, bonus: 0, reactions: 0 } }), players)).toBe('Grace still has an action.');
    // both used (a reaction is not the turn's): on
    expect(unusedOnTurn(at({ 'token:t_grace': { actions: 0, bonus: 0, reactions: 1 } }), players)).toBe('');
    // a creature's turn, a ruleset with no budgets, turns that aren't running or ordered: on
    expect(unusedOnTurn(at({ 'token:t_g1': { actions: 1, bonus: 1 } }, { turn: 2 }), players)).toBe('');
    expect(unusedOnTurn(at({}), players)).toBe('');
    expect(unusedOnTurn(at({ 'token:t_grace': { actions: 1 } }, { running: false }), players)).toBe('');
    expect(unusedOnTurn(at({ 'token:t_grace': { actions: 1 } }, { mode: 'dm' }), players)).toBe('');
    // one of the party in a shared slot
    const grouped = at({ 'token:t_grace': { actions: 0, bonus: 1 }, 'token:t_ada': { actions: 0, bonus: 0 } }, { order: ['group:pcs', 't_g1'], turn: 0, data: { groups: { pcs: { label: 'The party', tokens: ['t_ada', 't_grace'] } } } });
    expect(unusedOnTurn(grouped, players)).toBe('Grace still has a bonus action.');
    // at 0 hit points there is nothing to use (a dying character's turn is its death save)
    const withActor = { ...scene, tokens: tokens.map((t) => (t.id === 't_grace' ? { ...t, actor: 'a_grace' } : t)), turns: { ...turns, counters: { 'token:t_grace': { actions: 1, bonus: 1 } } } };
    expect(unusedOnTurn(withActor, players, { a_grace: { resources: { srd5e: { hp: { current: 0, max: 12 } } } } })).toBe('');
    expect(unusedOnTurn(withActor, players, { a_grace: { resources: { srd5e: { hp: { current: 5, max: 12 } } } } })).toBe('Grace still has an action and a bonus action.');
  });

  it('shows the order that runs, or this scene’s, and no other fight’s', () => {
    expect(orderRows(scene).map((r) => r.name)).toEqual(['Ada Vex', 'Grace', 'Goblin Warrior']);
    // the lookout fight's order, left behind, with a new goblin given one of its ids
    const left = { ...turns, running: false, scene: 's_lookout', order: ['t_g1', 't_old'] };
    expect(orderRows({ ...scene, turns: left })).toEqual([]);
    expect(orderRows({ ...scene, turns: { ...left, scene: 's1' } }).map((r) => r.name)).toEqual(['Goblin Warrior']);
  });
});
