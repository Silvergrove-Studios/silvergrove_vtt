import { afterEach, describe, expect, it, vi } from 'vitest';
import { chatIds, loadRead, readKey, saveRead, startFrom, unreadAfter } from '../src/lib/unread';

// (after a reload a playtest's badge said 279: the count began from nothing)
describe('what of the chat is not read', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('counts the messages and rolls, not what the rules said', () => {
    const log = [
      { id: 'm1', kind: 'chat', text: 'Hello' },
      { id: 'n1', kind: 'note', text: 'Wren is given a rope' },
      { id: 'r1', kind: 'roll', label: 'Stealth' },
      { kind: 'chat', text: 'no id' },
      { id: 'm2', kind: 'chat', text: 'Ready?' },
    ];
    expect(chatIds(log)).toEqual(['m1', 'r1', 'm2']);
  });

  it('counts what came after the last line read', () => {
    const ids = ['m1', 'r1', 'm2', 'm3'];
    expect(unreadAfter(ids, 'm3')).toBe(0);
    expect(unreadAfter(ids, 'r1')).toBe(2);
    // one it doesn't have (long ago, or another table's): nothing to count from
    expect(unreadAfter(ids, 'm_gone')).toBe(0);
    // begun when nothing had been said: every line since
    expect(unreadAfter(ids, '')).toBe(4);
    expect(unreadAfter([], '')).toBe(0);
  });

  it('starts from the line read last time, or from the newest', () => {
    const ids = ['m1', 'r1', 'm2'];
    expect(startFrom(ids, 'r1')).toBe('r1');
    expect(startFrom(ids, '')).toBe('m2');
    expect(startFrom(ids, 'm_gone')).toBe('m2');
    expect(startFrom([], '')).toBe('');
  });

  it('keeps it in the browser, for the table and the seat', () => {
    const kept = new Map<string, string>();
    vi.stubGlobal('localStorage', { getItem: (k: string) => kept.get(k) ?? null, setItem: (k: string, v: string) => void kept.set(k, v) });
    expect(loadRead('The Ruined Chapel', 'dm')).toBe('');
    saveRead('The Ruined Chapel', 'dm', 'm7');
    saveRead('The Ruined Chapel', 'pl_ana', 'm3');
    expect(kept.get('hexmap.read/The Ruined Chapel/dm')).toBe('m7');
    expect(readKey('The Ruined Chapel', 'pl_ana')).toBe('hexmap.read/The Ruined Chapel/pl_ana');
    expect(loadRead('The Ruined Chapel', 'dm')).toBe('m7');
    expect(loadRead('The Ruined Chapel', 'pl_ana')).toBe('m3');
  });

  it('does without, where the browser keeps nothing', () => {
    vi.stubGlobal('localStorage', {
      getItem: () => {
        throw new Error('denied');
      },
      setItem: () => {
        throw new Error('denied');
      },
    });
    expect(loadRead('T', 'dm')).toBe('');
    expect(() => saveRead('T', 'dm', 'm1')).not.toThrow();
  });
});
