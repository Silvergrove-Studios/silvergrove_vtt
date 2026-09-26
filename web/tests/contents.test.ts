import { describe, expect, it } from 'vitest';
import { book, contents, folderChoices, kindWord, topOrder } from '../src/dm/contents';

const players = [{ id: 'pl_a', name: 'Ana' }];
const dm = {
  people: [
    { id: 'a1', name: 'Wren', kind: 'pc', owner: 'pl_a' },
    { id: 'a2', name: 'Marta Vell', kind: 'npc', place: 'p1', notes: 'knows the way' },
  ],
  places: [
    { id: 'p1', name: 'Thornwick', kind: 'place', text: 'A village.' },
    { id: 'p2', name: 'The chapel', kind: 'encounter' },
  ],
  journal: [
    { id: 'n1', kind: 'note', title: 'Background' },
    { id: 'n2', kind: 'note', title: 'Start here', tags: ['start'] },
    { id: 'h1', kind: 'handout', title: 'The map', ref: 'picture:x', audience: 'all' },
  ],
  pictures: [{ ref: 'art:map', name: 'Old map' }],
  maps: [{ id: 'm1', name: 'The Vale', role: 'regional' }],
  player_notes: [],
  contents: { titles: { places: 'Where' }, folders: [{ id: 'f1', title: 'Villains', parent: 'section:people' }, { id: 'f2', title: 'Session 2', parent: '' }], in: { 'actor:a2': 'f1' }, order: ['folder:f2'] },
};

describe('the DM’s book', () => {
  it('puts the DM’s folders where they were put', () => {
    expect(topOrder(dm)[0]).toBe('folder:f2');
    const b = book(dm, players, '');
    // (Fights shows even empty, after the places: it is where a new fight is made)
    expect(b.map((n) => n.title)).toEqual(['Session 2', 'Notes for you', 'The party', 'Where', 'Fights', 'People', 'Shown to the players', 'Pictures', 'Maps']);
    const people = b.find((n) => n.node === 'section:people')!;
    expect(people.folders[0].title).toBe('Villains');
    expect(people.folders[0].items.map((i) => i.label)).toEqual(['Marta Vell']);
    expect(people.items).toEqual([]);
  });
  it('lists the author’s “Start here” first, and people under their places', () => {
    const c = contents(dm, players, '');
    expect(c.notes.map((i) => i.label)).toEqual(['Start here', 'Background']);
    expect(c.places[0].children?.map((i) => i.label)).toEqual(['Marta Vell']);
    expect(c.shown[0].sub).toBe('→ everyone');
    expect(c.party[0].sub).toBe('Ana');
  });
  it('searches everything, leaving out what does not match', () => {
    const b = book(dm, players, 'way');
    expect(b.map((n) => n.title)).toEqual(['People']);
  });
  it('names folders by where they are', () => {
    expect(folderChoices(dm).map((f) => f.path)).toEqual(['People › Villains', 'Session 2']);
  });
  // (a playtest's DM opened the picture "The ruined chapel" meaning the place)
  it('says what each thing is, and flags a name two things share', () => {
    const c = contents({ ...dm, places: [...dm.places, { id: 'p3', name: 'OLD MAP', kind: 'place' }] }, players, '');
    const all = Object.values(c).flatMap((items) => items.flatMap((i) => [i, ...(i.children ?? [])]));
    expect(all.every((i) => kindWord(i.kind) !== '')).toBe(true);
    const chapel = c.places.find((i) => i.ref === 'place:p2')!;
    expect([chapel.kind, chapel.sub, kindWord(chapel.kind)]).toEqual(['place', 'fight here', 'place']);
    expect(c.places.find((i) => i.ref === 'place:p3')!.twin).toBe(true);
    expect([c.pictures[0].kind, c.pictures[0].twin]).toEqual(['picture', true]);
    // Marta, under Thornwick and in People, is the same person listed twice: no twin
    expect(c.people[0].twin).toBe(false);
    expect(c.places[0].children?.[0].twin).toBe(false);
    expect(c.party[0].kind).toBe('character');
  });
  it('counts what each part holds, its folders’ too', () => {
    const b = book(dm, players, '');
    expect(b.find((n) => n.node === 'section:people')!.count).toBe(1);
    // two places: Marta under Thornwick is not counted again
    expect(b.find((n) => n.node === 'section:places')!.count).toBe(2);
    expect(b.find((n) => n.node === 'section:fights')!.count).toBe(0);
  });
  it('lists what the players wrote newest first, a note changed today at the top', () => {
    const notes = [
      { id: 'pn_1', owner: 'pl_a', title: 'Old', created: '2026-09-01T10:00:00', updated: '2026-09-01T10:00:00' },
      { id: 'pn_2', owner: 'pl_a', title: 'Changed today', created: '2026-09-01T11:00:00', updated: '2026-09-26T09:00:00' },
      { id: 'pn_3', owner: 'pl_a', title: 'New', created: '2026-09-20T10:00:00', updated: '2026-09-20T10:00:00' },
    ];
    expect(contents({ ...dm, player_notes: notes }, players, '').from_players.map((i) => i.label)).toEqual(['Changed today', 'New', 'Old']);
  });
});
