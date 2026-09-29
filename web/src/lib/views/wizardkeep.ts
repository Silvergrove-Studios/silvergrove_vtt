// Where a wizard was left, and its answers, kept in this browser so that a
// phone that drops the page while in another app comes back to them — until
// the wizard is done: once the table has taken what it sent, they go, and the
// wizard starts over at its first step. (A sheet's level-up wizard is drawn
// again at once for the next level, which asks its own questions: the last
// level's answers, kept, were taken for them and it opened at its last step.)
import type { Dict } from './viewlib';

/** How long kept answers last: a day. */
export const KEEP_MS = 24 * 60 * 60 * 1000;

export interface Kept {
  /** the step's index when it was left */
  at: number;
  /** and its title (the steps shown change with the answers) */
  title: string;
  values: Dict;
}

/** The key a wizard's answers are kept under: whose, which wizard (its label and its steps). */
export function keptKey(me: string, label: string, titles: string[]): string {
  return `hexmap.wizard/${me}/${label}/${titles.join('|')}`;
}

/** What was kept, if it's there and not too old. */
export function loadKept(store: Pick<Storage, 'getItem'> | null, key: string, now = Date.now()): Kept | null {
  try {
    const raw = store?.getItem(key);
    if (!raw) return null;
    const v = JSON.parse(raw) as { at: number; title?: string; values: Dict; t: number };
    if (!v || typeof v !== 'object' || now - Number(v.t ?? 0) > KEEP_MS) return null;
    return { at: Number(v.at) || 0, title: String(v.title ?? ''), values: v.values && typeof v.values === 'object' ? v.values : {} };
  } catch {
    return null;
  }
}

/** Keep where the wizard is, and its answers. */
export function keepKept(store: Pick<Storage, 'setItem'> | null, key: string, kept: Kept, now = Date.now()): void {
  try {
    store?.setItem(key, JSON.stringify({ ...kept, t: now }));
  } catch {
    /* private mode, or full */
  }
}

/** The wizard is done: what it kept goes. */
export function forgetKept(store: Pick<Storage, 'removeItem'> | null, key: string): void {
  try {
    store?.removeItem(key);
  } catch {
    /* private mode */
  }
}

/** The browser's storage, or null where there is none (a test, private mode). */
export function browserStore(): Storage | null {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}
