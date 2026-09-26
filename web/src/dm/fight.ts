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
  // an order that isn't running and isn't this scene's is another fight's (a
  // playtest's chapel fight showed the lookout's, a new goblin in it)
  if (!turns.running && String(turns.scene ?? '') !== String(scene.id ?? '')) return [];
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

/** What an order entry is called here: a group's label, or its token's name ('' when it isn't on this scene). */
export function entryName(turns: Dict, tokens: Dict[], entry: string): string {
  if (entry.startsWith('group:')) return String(turns.data?.groups?.[entry.slice(6)]?.label ?? turns.data?.labels?.[entry] ?? entry.slice(6));
  return String(tokens.find((t) => t.id === entry)?.name ?? '');
}

/** The turn after (round, turn) in an order of `n`. */
export function turnAfter(round: number, turn: number, n: number): { round: number; turn: number } {
  return turn + 1 >= n ? { round: round + 1, turn: 0 } : { round, turn: turn + 1 };
}

/** Who ended the turn just before this one, when a player did ("Ada Vex"), or ''. */
export function endedByPlayer(scene: Dict, players: string[]): string {
  const turns: Dict = scene.turns ?? {};
  const last: Dict | null = turns.last && typeof turns.last === 'object' ? turns.last : null;
  if (!turns.running || !last || !players.includes(String(last.by ?? ''))) return '';
  const after = turnAfter(Number(last.round ?? 0), Number(last.turn ?? 0), ((turns.order as unknown[]) ?? []).length);
  if (after.round !== Number(turns.round ?? 1) || after.turn !== Number(turns.turn ?? 0)) return '';
  return entryName(turns, (scene.tokens as Dict[]) ?? [], String(last.entry ?? ''));
}

function samePos(a: unknown, b: unknown): boolean {
  const p = (a as number[]) ?? [];
  const q = (b as number[]) ?? [];
  return p.length >= 2 && q.length >= 2 && Math.abs(Number(p[0]) - Number(q[0])) < 0.01 && Math.abs(Number(p[1]) - Number(q[1])) < 0.01;
}

/** Next pressed while nothing has happened since a player ended the turn
 *  before (no roll or note in the log since this turn began, its tokens
 *  where they stood): the names to ask with, or null to go on. A playtest's
 *  DM pressed Next a moment after a player's End turn, and a second turn
 *  went by. */
export function nothingSince(scene: Dict, log: Dict[], players: string[]): { ended: string; up: string } | null {
  const ended = endedByPlayer(scene, players);
  if (!ended) return null;
  const turns: Dict = scene.turns;
  const last: Dict = turns.last;
  const tokens: Dict[] = (scene.tokens as Dict[]) ?? [];
  const mark = String(last.log ?? '');
  const at = mark ? log.findIndex((e) => String(e?.id ?? '') === mark) : -1;
  // (a log this screen can't place the turn in: don't ask)
  if (mark && at < 0) return null;
  if (log.slice(at + 1).some((e) => e?.kind === 'roll' || e?.kind === 'note')) return null;
  for (const [id, p] of Object.entries((last.pos as Dict) ?? {})) {
    const t = tokens.find((x) => x.id === id);
    if (!t || !samePos(t.pos, p)) return null;
  }
  const up = entryName(turns, tokens, String(((turns.order as string[]) ?? [])[Number(turns.turn ?? 0)] ?? ''));
  return { ended, up: up || 'this' };
}

/** A ruleset's action that rolls initiative (and starts the turns): {plugin, action}, or null. */
export function initiativeAction(view: Dict): { plugin: string; action: string } | null {
  for (const [plugin, actions] of Object.entries((view.actions ?? {}) as Dict)) {
    if (actions && typeof actions === 'object' && 'roll_initiative' in actions) return { plugin, action: 'roll_initiative' };
  }
  return null;
}
