import { describe, expect, it } from 'vitest';
import { fightToken } from '../src/dm/fight';

describe('the book in a fight', () => {
  // (a playtest's DM, the Warden risen, clicked its name in the book and got its picture)
  it('knows the fight’s creature a book entry stands for', () => {
    const toks = [
      { id: 't_w', name: 'Chapel Warden', actor: 'a_w' },
      { id: 't_g1', name: 'Goblin Warrior', actor: 'a_g1', tags: ['dead'] },
      { id: 't_g2', name: 'Goblin Warrior 2', actor: 'a_g2' },
      { id: 't_g3', name: 'Goblin Warrior 3', actor: 'a_g3' },
      { id: 't_ada', name: 'Ada Vex', actor: 'a_ada', owner: 'pl_ada' },
      { id: 't_cart', name: 'The cart', tags: ['thing'] },
    ];
    const dm = { pictures: [{ ref: 'pack:chapel/warden', name: 'The Chapel Warden' }, { ref: 'pack:chapel/cart', name: 'The cart' }] };
    expect(fightToken('picture:pack:chapel/warden', dm, toks)).toBe('t_w');
    expect(fightToken('entry:creatures/chapel-warden', dm, toks)).toBe('t_w');
    expect(fightToken('actor:a_ada', dm, toks)).toBe('t_ada');
    // of several, the one whose turn it is, else one alive
    expect(fightToken('entry:creatures/goblin-warrior', dm, toks)).toBe('t_g2');
    expect(fightToken('entry:creatures/goblin-warrior', dm, toks, 't_g3')).toBe('t_g3');
    // what isn't one of its creatures opens as ever
    expect(fightToken('picture:pack:chapel/cart', dm, toks)).toBe('');
    expect(fightToken('place:pl_chapel', dm, toks)).toBe('');
    expect(fightToken('entry:spells/bless', dm, toks)).toBe('');
  });
});
