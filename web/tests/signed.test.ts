import { describe, expect, it } from 'vitest';
import { signedOf } from '../src/lib/views/viewlib';

// A `number` with `signed` reads as a modifier (an Initiative of +2 read "2").
describe('signed numbers', () => {
  it('signs a modifier, typed or plain', () => {
    expect(signedOf({ total: 2, parts: [{ label: 'dexterity', value: 2 }] })).toBe('+2');
    expect(signedOf(0)).toBe('+0');
    expect(signedOf(-1)).toBe('-1');
    expect(signedOf({ total: 1.5, parts: [] })).toBe('+1.5');
  });
  it('leaves what is not a number as it reads', () => {
    expect(signedOf('—')).toBe('—');
    expect(signedOf(null)).toBe('');
  });
});
