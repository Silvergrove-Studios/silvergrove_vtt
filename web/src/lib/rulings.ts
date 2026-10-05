// What the DM may do with a line of the log: the buttons a ruleset keeps on
// the entry, in its part of the entry's `dm` block (the DM's alone: the
// Table never sends it to a player) — a ruling on a roll (Call it a miss,
// Halve it, Reroll), an outcome waiting for the DM (Apply, Change, Skip).
import type { Dict } from './views/viewlib';

export interface DmAction {
  /** The ruleset whose button it is. */
  plugin: string;
  id: string;
  label: string;
  /** What it does, for its tooltip. */
  hint: string;
  /** What pressing it sends (an action of the ruleset's). */
  intent: Dict;
}

function blocks(entry: Dict | null | undefined): [string, Dict][] {
  const dm = entry && typeof entry === 'object' ? entry.dm : null;
  if (!dm || typeof dm !== 'object' || Array.isArray(dm)) return [];
  return Object.keys(dm)
    .sort()
    .filter((k) => dm[k] && typeof dm[k] === 'object' && !Array.isArray(dm[k]))
    .map((k) => [k, dm[k] as Dict]);
}

/** The DM's buttons on a log entry, every ruleset's, in their order. */
export function dmActions(entry: Dict | null | undefined): DmAction[] {
  const out: DmAction[] = [];
  for (const [plugin, block] of blocks(entry)) {
    for (const a of Array.isArray(block.actions) ? block.actions : []) {
      if (!a || typeof a !== 'object' || !a.intent || typeof a.intent !== 'object') continue;
      const label = String(a.label ?? '').trim();
      if (!label) continue;
      out.push({ plugin, id: String(a.id ?? label), label, hint: String(a.hint ?? ''), intent: a.intent as Dict });
    }
  }
  return out;
}

/** Whether a line's buttons wait for the DM (an outcome not yet applied):
 *  shown at once under it, not behind its Rule button. */
export function dmWaiting(entry: Dict | null | undefined): boolean {
  return blocks(entry).some(([, b]) => b.waiting === true) && dmActions(entry).length > 0;
}
