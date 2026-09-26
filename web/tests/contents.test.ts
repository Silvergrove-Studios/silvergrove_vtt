import { describe, expect, it } from 'vitest';
import { book, contents, folderChoices, topOrder } from '../src/dm/contents';

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
});
