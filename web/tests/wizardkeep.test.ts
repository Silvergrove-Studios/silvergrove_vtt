import { describe, expect, it } from 'vitest';
import { forgetKept, keepKept, KEEP_MS, keptKey, loadKept } from '../src/lib/views/wizardkeep';

/** A browser's storage, in memory. */
function memory(): Storage {
  const m = new Map<string, string>();
  return {
    get length() {
      return m.size;
    },
    clear: () => m.clear(),
    getItem: (k: string) => (m.has(k) ? m.get(k)! : null),
    key: (i: number) => [...m.keys()][i] ?? null,
    removeItem: (k: string) => void m.delete(k),
    setItem: (k: string, v: string) => void m.set(k, v),
  };
}

describe('a wizard’s answers, kept in the browser until it is done', () => {
  const key = keptKey('pl_1', 'Level up', ['Subclass', 'Ability Score Improvement', 'The new level']);

  it('keeps where it was left and the answers, for a day', () => {
    const s = memory();
    keepKept(s, key, { at: 2, title: 'The new level', values: { subclass: 'champion' } }, 1000);
    expect(loadKept(s, key, 1000 + 60_000)).toEqual({ at: 2, title: 'The new level', values: { subclass: 'champion' } });
    expect(loadKept(s, key, 1000 + KEEP_MS + 1)).toBeNull();
  });

  // (a level-up wizard stood again at once for the next level, at its last step with
  // the last level's answers: its feat step never shown)
  it('forgets them once the table has taken what it sent', () => {
    const s = memory();
    keepKept(s, key, { at: 2, title: 'The new level', values: { feat: 'ability-score-improvement', asi: ['str'] } });
    forgetKept(s, key);
    expect(loadKept(s, key)).toBeNull();
  });

  it('is its own for each player and each wizard', () => {
    expect(keptKey('pl_1', 'Level up', ['A'])).not.toBe(keptKey('pl_2', 'Level up', ['A']));
    expect(keptKey('pl_1', 'Level up', ['A'])).not.toBe(keptKey('pl_1', 'Gain a level', ['A']));
  });

  it('reads nothing from what isn’t a wizard’s', () => {
    const s = memory();
    s.setItem(key, 'not json');
    expect(loadKept(s, key)).toBeNull();
    expect(loadKept(null, key)).toBeNull();
  });
});
