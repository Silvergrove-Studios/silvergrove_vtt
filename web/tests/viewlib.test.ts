import { describe, expect, it } from 'vitest';
import { atPointer, facts, fillIntent, matchWords, num, optionsFrom, pickLabel, putValue, shownTabs, textOf, timeLeft, valueOf, wordsOf } from '../src/lib/views/viewlib';

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
  it('puts its last choices after the data', () => {
    // (a DM's "Someone else…" after the party's characters: a playtest's DM found
    // the world's people among the characters)
    expect(optionsFrom({ bind: '/list', first: [{ id: '', name: 'The whole party' }], last: [{ id: 'else', name: 'Someone else…' }] }, data)).toEqual([
      { id: '', name: 'The whole party' },
      { id: 'a', name: 'Alpha' },
      { id: 'b', name: 'Beta' },
      { id: 'else', name: 'Someone else…' },
    ]);
    expect(optionsFrom({ bind: '/nothing', last: [{ id: 'else', name: 'Someone else…' }] }, data)).toEqual([{ id: 'else', name: 'Someone else…' }]);
  });
  it("says what a picker's choice does", () => {
    // (a playtest's player found a spell's Read button, but not how to learn it)
    const spell = { id: 'fire-bolt', name: 'Fire Bolt', level: 0 };
    expect(pickLabel({ pick_label: "'Learn ' .. @item.name" }, spell, data)).toBe('Learn Fire Bolt');
    expect(pickLabel({}, spell, data)).toBe('Fire Bolt');
    expect(pickLabel({ pick_label: "'Learn ' .. @item.name" }, 'plain', data)).toBe('plain');
    expect(pickLabel({ pick_label: '@item.nothing.here' }, spell, data)).toBe('Fire Bolt');
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

describe('timeLeft', () => {
  // day 2, 10:00: 1440 + 600 minutes from the first day's start
  const clock = { day: 2, minute: 600 };
  const until = (m: number) => ({ key: 'concentrating', duration: { kind: 'time', until: 2040 + m } });
  it("says what's left of a timed effect", () => {
    expect(timeLeft(until(8), clock)).toBe('8 min left');
    expect(timeLeft(until(80), clock)).toBe('1 h 20 min left');
    expect(timeLeft(until(480), clock)).toBe('8 h left');
    expect(timeLeft(until(1440 * 3), clock)).toBe('3 days left');
    expect(timeLeft(until(0.5), clock)).toBe('under a minute left');
    expect(timeLeft({ duration: { kind: 'rounds', rounds: 1 } }, clock)).toBe('1 round left');
    expect(timeLeft({ duration: { kind: 'rounds', rounds: 7 } }, clock)).toBe('7 rounds left');
  });
  it('says nothing of an effect that is over, untimed, or with no clock', () => {
    expect(timeLeft(until(0), clock)).toBe('');
    expect(timeLeft(until(-5), clock)).toBe('');
    expect(timeLeft({ duration: { kind: 'until_cleared' } }, clock)).toBe('');
    expect(timeLeft({ duration: { kind: 'turn_start', of: 'tok_1' } }, clock)).toBe('');
    expect(timeLeft({ key: 'prone' }, clock)).toBe('');
    expect(timeLeft(until(8), undefined)).toBe('');
  });
  it("leaves out the tabs a viewer isn't to have", () => {
    // (the DM's Adjust tab on a sheet; a player's own when the table allows it)
    const node = { type: 'tabs', tabs: [{ title: 'Stat block', children: [] }, { title: 'Adjust', if: "@role == 'gm'", children: [] }, null] };
    expect(shownTabs(node, { role: 'gm' }).map((t) => t.title)).toEqual(['Stat block', 'Adjust']);
    expect(shownTabs(node, { role: 'player' }).map((t) => t.title)).toEqual(['Stat block']);
    expect(shownTabs({ type: 'tabs' }, {})).toEqual([]);
  });
});
