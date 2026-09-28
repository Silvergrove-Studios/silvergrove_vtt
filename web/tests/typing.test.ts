import { describe, expect, it, vi } from 'vitest';
import { TypingSignal, typingWords } from '../src/lib/typing';

// a screen tells the table it is typing, now and then, while its chat box holds something
describe('TypingSignal', () => {
  const make = () => {
    let t = 1000;
    const send = vi.fn();
    const sig = new TypingSignal(send, 3000, () => t);
    return { sig, send, at: (ms: number) => (t = ms) };
  };

  it('tells the table at once, then at most once every three seconds', () => {
    const { sig, send, at } = make();
    expect(sig.input('H')).toBe(true);
    at(1500);
    expect(sig.input('He')).toBe(false);
    at(3999);
    expect(sig.input('Hel')).toBe(false);
    expect(send).toHaveBeenCalledTimes(1);
    at(4000);
    expect(sig.input('Hell')).toBe(true);
    expect(send).toHaveBeenCalledTimes(2);
  });

  it('says nothing for an empty box', () => {
    const { sig, send } = make();
    expect(sig.input('')).toBe(false);
    expect(sig.input('   ')).toBe(false);
    expect(send).not.toHaveBeenCalled();
  });

  it('starts over once a message is sent', () => {
    const { sig, send, at } = make();
    sig.input('Hello');
    sig.sent();
    at(1200);
    expect(sig.input('A')).toBe(true);
    expect(send).toHaveBeenCalledTimes(2);
  });
});

describe('typingWords', () => {
  it('names who is typing', () => {
    expect(typingWords([])).toBe('');
    expect(typingWords(['Leo'])).toBe('Leo is typing…');
    expect(typingWords(['Leo', 'the DM'])).toBe('Leo and the DM are typing…');
    expect(typingWords(['the DM'])).toBe('The DM is typing…');
    expect(typingWords(['Leo', 'Kofi', 'Nadia'])).toBe('Leo, Kofi and Nadia are typing…');
    expect(typingWords(['', 'Hana'])).toBe('Hana is typing…');
  });
});
