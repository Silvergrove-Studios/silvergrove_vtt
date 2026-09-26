// A roll as the table sees it: its natural die, and what a player is told
// of their own rolls wherever they are (a playtest's players pressed a
// roll's button, saw nothing on the tab they were on, and rolled again).
import type { Dict } from './views/viewlib';

/** The natural d20 of a roll when it's a 20 or a 1: the ruleset's own
    (`result.natural`, set on every D20 Test), else a lone kept d20 (a free
    `/roll 1d20+3`). Two kept d20s, or none, have no natural. */
export function natural(entry: Dict): 20 | 1 | null {
  const r = (entry?.result ?? {}) as Dict;
  let n: number | null = null;
  if (typeof r.natural === 'number' && r.natural > 0) n = r.natural;
  else {
    const kept = ((r.dice as Dict[]) ?? []).filter((d) => d && typeof d === 'object' && d.kept !== false && Number(d.sides) === 20);
    if (kept.length === 1) n = Number(kept[0].face);
  }
  return n === 20 ? 20 : n === 1 ? 1 : null;
}

/** "Perception check: 17, success" — what a toast says of a roll. */
export function rollSummary(entry: Dict): string {
  const r = (entry?.result ?? {}) as Dict;
  const outcome = String(r.outcome ?? '');
  const nat = natural(entry);
  const said = outcome && outcome !== 'rolled' ? `, ${outcome}` : '';
  return `${String(entry.label ?? 'Roll')}: ${String(r.total ?? '')}${said}${nat === 20 ? ' (natural 20!)' : nat === 1 ? ' (natural 1)' : ''}`;
}

/** Rolls in `log` by my characters that `seen` hasn't had yet (which it
    takes in). The first call only primes `seen`: what was rolled before
    this page opened isn't news. */
export function freshRolls(log: Dict[], mine: Set<string>, seen: Set<string>, primed: boolean): Dict[] {
  const out: Dict[] = [];
  for (const e of log ?? []) {
    if (!e || typeof e !== 'object' || e.kind !== 'roll') continue;
    const id = String(e.id ?? '');
    if (id === '' || seen.has(id)) continue;
    seen.add(id);
    if (primed && mine.has(String(e.actor ?? ''))) out.push(e);
  }
  return out;
}
