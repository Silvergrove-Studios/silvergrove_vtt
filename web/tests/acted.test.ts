import { describe, expect, it } from 'vitest';
import { actedWords } from '../src/lib/acted';

// what a player is told of an action done that nothing else on the screen shows
describe('actedWords', () => {
  it('says what was done, to what', () => {
    expect(actedWords('Cast', 'Fire Bolt')).toBe('Cast Fire Bolt');
    expect(actedWords('Use', 'Arcane Recovery')).toBe('Used Arcane Recovery');
    expect(actedWords('Prepare', 'Bless')).toBe('Prepared Bless');
    expect(actedWords('Cast on yourself', 'Mage Armor')).toBe('Cast Mage Armor on yourself');
    expect(actedWords('Take it off', 'Chain Mail')).toBe('Took Chain Mail off');
    expect(actedWords('Drop one', 'Torch')).toBe('Dropped one: Torch');
  });

  it('leaves out what the label says of itself', () => {
    // the Metamagic armed, the cost, the banner's words before the colon
    expect(actedWords('Cast — Careful Spell', 'Sleep')).toBe('Cast Sleep');
    expect(actedWords('Ready for level 2: Gain a level')).toBe('Gained a level');
    expect(actedWords('Dash  [1 action]')).toBe('Dash ✓');
    // a button named for its row's thing says it once
    expect(actedWords('Second Wind  [1 bonus action]', 'Second Wind')).toBe('Second Wind ✓');
  });

  it('ticks what is not a verb, and reads a whole label better where it can', () => {
    expect(actedWords('Short rest')).toBe('Short rest ✓');
    expect(actedWords('Bardic Inspiration', 'Kofi')).toBe('Bardic Inspiration: Kofi ✓');
    expect(actedWords('End turn')).toBe('Ended your turn');
    expect(actedWords('')).toBe('');
  });
});
