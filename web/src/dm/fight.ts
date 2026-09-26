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
  const rows: OrderRow[] = [];
  for (const entry of (turns.order as string[]) ?? []) {
    const ids = turnMembers(turns, String(entry));
    const toks = ids.map((id) => tokens.find((t) => t.id === id)).filter((t): t is Dict => !!t);
    const group = String(entry).startsWith('group:');
    // a token that isn't on this scene has no row (a playtest's DM read "t_bffa8bc2's turn")
    if (!group && !toks.length) continue;
    const name = group ? String(turns.data?.groups?.[String(entry).slice(6)]?.label ?? labels[entry] ?? String(entry).slice(6)) : String(toks[0]?.name ?? '');
    rows.push({ entry: String(entry), ids, name, label: String(labels[entry] ?? ''), current: ids.some((id) => up.has(id)), hidden: toks.length > 0 && toks.every((t) => t.hidden) });
  }
  return rows;
}

/** A ruleset's action that rolls initiative (and starts the turns): {plugin, action}, or null. */
export function initiativeAction(view: Dict): { plugin: string; action: string } | null {
  for (const [plugin, actions] of Object.entries((view.actions ?? {}) as Dict)) {
    if (actions && typeof actions === 'object' && 'roll_initiative' in actions) return { plugin, action: 'roll_initiative' };
  }
  return null;
}
