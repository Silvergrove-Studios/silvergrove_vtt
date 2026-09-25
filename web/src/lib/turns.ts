// Whose turn it is, as the host says it (EncounterState.current_turn_tokens,
// Session.turn_summary): the tokens up now, and one line for a header.
import type { Dict } from './game.svelte';

/** The tokens an order entry stands for: itself, or a group's members. */
export function turnMembers(turns: Dict, entry: string): string[] {
  if (entry.startsWith('group:')) {
    const g = turns.data?.groups?.[entry.slice(6)] ?? {};
    return ((g.tokens as string[]) ?? []).map(String);
  }
  return [entry];
}

export function currentTurnTokens(turns: Dict, tokens: Dict[]): string[] {
  if (String(turns.strategy ?? 'ordered') === 'focus') {
    const f = String(turns.focus ?? '');
    return turns.running && f.startsWith('token:') && tokens.some((t) => t.id === f.slice(6)) ? [f.slice(6)] : [];
  }
  if (String(turns.mode ?? 'free') !== 'ordered' || !turns.running) return [];
  const order: string[] = (turns.order as string[]) ?? [];
  const turn = Number(turns.turn ?? 0);
  if (turn < 0 || turn >= order.length) return [];
  return turnMembers(turns, String(order[turn]));
}

function owned(t: Dict, me: string): boolean {
  return !!me && String(t.owner ?? '') === me;
}

/** One line for a player's header, and whether it is their move. */
export function turnSummary(scene: Dict, me: string): { text: string; mine: boolean } {
  const turns: Dict = scene.turns ?? {};
  const tokens: Dict[] = (scene.tokens as Dict[]) ?? [];
  if (String(turns.strategy ?? 'ordered') === 'focus' && turns.running) {
    const up = currentTurnTokens(turns, tokens);
    const t = tokens.find((x) => x.id === up[0]);
    return { text: t ? `Focus: ${t.name}` : 'Focus: the DM', mine: !!t && owned(t, me) };
  }
  switch (String(turns.mode ?? 'free')) {
    case 'free':
      return { text: 'Free movement', mine: false };
    case 'dm': {
      const active: string[] = (turns.active as string[]) ?? [];
      const mine = tokens.filter((t) => owned(t, me) && active.includes(String(t.id))).map((t) => String(t.name ?? ''));
      return mine.length ? { text: `You may move: ${mine.join(', ')}`, mine: true } : { text: 'Waiting for the DM', mine: false };
    }
    case 'ordered': {
      if (!turns.running) return { text: 'Waiting to begin', mine: false };
      const round = Number(turns.round ?? 1);
      const up = currentTurnTokens(turns, tokens)
        .map((id) => tokens.find((t) => t.id === id))
        .filter((t): t is Dict => !!t);
      if (!up.length) return { text: `Round ${round}`, mine: false };
      const who = up.map((t) => String(t.name ?? '')).join(', ');
      return up.some((t) => owned(t, me)) ? { text: `Your turn: ${who} (round ${round})`, mine: true } : { text: `${who}'s turn (round ${round})`, mine: false };
    }
  }
  return { text: '', mine: false };
}
