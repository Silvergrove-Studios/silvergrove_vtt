// A fight as the DM's screen runs it: the prepared fight that is live, the
// turn order as rows to show, and the ruleset's own "roll initiative".
import type { Dict } from '../lib/game.svelte';
import { currentTurnTokens, turnMembers } from '../lib/turns';

export function liveFight(dm: Dict): Dict | null {
  for (const e of (dm.encounters as Dict[]) ?? []) {
    const live = e.live;
    if (live && typeof live === 'object' && Object.keys(live).length) return e;
  }
  return null;
}

export interface OrderRow {
  entry: string;
  ids: string[];
  name: string;
  label: string;
  current: boolean;
  hidden: boolean;
}

export function orderRows(scene: Dict): OrderRow[] {
  const turns: Dict = scene.turns ?? {};
  const tokens: Dict[] = (scene.tokens as Dict[]) ?? [];
  const up = new Set(currentTurnTokens(turns, tokens));
  const labels: Dict = turns.data?.labels ?? {};
  return ((turns.order as string[]) ?? []).map((entry) => {
    const ids = turnMembers(turns, String(entry));
    const toks = ids.map((id) => tokens.find((t) => t.id === id)).filter((t): t is Dict => !!t);
    const name = entry.startsWith('group:') ? String(turns.data?.groups?.[entry.slice(6)]?.label ?? labels[entry] ?? entry.slice(6)) : String(toks[0]?.name ?? entry);
    return { entry: String(entry), ids, name, label: String(labels[entry] ?? ''), current: ids.some((id) => up.has(id)), hidden: toks.length > 0 && toks.every((t) => t.hidden) };
  });
}

/** A ruleset's action that rolls initiative (and starts the turns): {plugin, action}, or null. */
export function initiativeAction(view: Dict): { plugin: string; action: string } | null {
  for (const [plugin, actions] of Object.entries((view.actions ?? {}) as Dict)) {
    if (actions && typeof actions === 'object' && 'roll_initiative' in actions) return { plugin, action: 'roll_initiative' };
  }
  return null;
}
