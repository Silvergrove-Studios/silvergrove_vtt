import { describe, expect, it } from 'vitest';
import { atPointer, facts, fillIntent, matchWords, num, optionsFrom, putValue, textOf, valueOf, wordsOf } from '../src/lib/views/viewlib';

describe('views', () => {
  const data = { actor: { name: 'Ana', stats: { dex: 14 } }, list: [{ id: 'a', name: 'Alpha', ok: true }, { id: 'b', name: 'Beta', ok: false }], 'a/b': 1 };
  it('reads JSON pointers', () => {
    expect(atPointer(data, '/actor/stats/dex')).toBe(14);
    expect(atPointer(data, 'list/1/name')).toBe('Beta');
    expect(atPointer(data, '/a~1b')).toBe(1);
    expect(atPointer(data, '/nothing/here')).toBeNull();
  });
  it('takes a value from an expression, a pointer or a literal', () => {
    expect(valueOf({ expr: "@actor.name .. '!'" }, data)).toBe('Ana!');
    expect(valueOf({ bind: '/actor/name' }, data)).toBe('Ana');
    expect(valueOf({ text: 'Hi' }, data, 'text')).toBe('Hi');
  });
  it('fills intents', () => {
    expect(fillIntent({ kind: 'act', actor: '$/actor/name', args: ['$/list/0/id', 3] }, data)).toEqual({ kind: 'act', actor: 'Ana', args: ['a', 3] });
    expect(putValue({ kind: 'answer', answer: '$values' }, { x: 1 }, '$values')).toEqual({ kind: 'answer', answer: { x: 1 } });
  });
  it('turns data into choices', () => {
    expect(optionsFrom({ bind: '/list', if: '@item.ok', first: [{ id: '', name: 'None' }] }, data)).toEqual([
      { id: '', name: 'None' },
      { id: 'a', name: 'Alpha' },
    ]);
  });
  it('finds a name by the starts of its words, in any order, whatever the punctuation', () => {
    // (a playtest's DM found nothing for "Lantern, Hooded" nor "thieves' tools")
    expect(wordsOf("Thieves' Tools")).toEqual(['thieves', 'tools']);
    expect(matchWords('Lantern, Hooded', 'hooded lan')).toBe(true);
    expect(matchWords('Lantern, Hooded', 'Lantern, Hooded')).toBe(true);
    expect(matchWords("Thieves' Tools", "thieves' tools")).toBe(true);
    expect(matchWords('Anything', '  ')).toBe(true);
    expect(matchWords('Lantern, Hooded', 'hooded lamp')).toBe(false);
    expect(matchWords('Rope', 'ope')).toBe(false);
  });
  it('shows numbers as the sheets do', () => {
    expect(num(3)).toBe('3');
    expect(num(2.25)).toBe('2.3');
    expect(textOf({ total: 15, parts: [] })).toBe('15');
  });
  it('lists an entry’s facts', () => {
    expect(facts({ id: 'x', name: 'Fireball', level: 3, ritual: false, concentration: true, classes: ['wizard', 'sorcerer'], text: 'Boom' })).toEqual([
      'classes wizard, sorcerer',
      'concentration',
      'level 3',
    ]);
  });
});
