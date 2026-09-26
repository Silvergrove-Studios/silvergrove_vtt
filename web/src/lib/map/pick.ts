// Picking a target on the map for an intent that wants one (an attack, a
// spell's area): what was picked, as the host's MapQuery.pick_target says
// it — "token:<id>", a "q,r" cell, or an area spec — and the intent as it
// is then sent, with ctx.target and ctx.scene filled in.
import { Grid, cellKey, type Vec } from '../grid';
import { tokenPos } from './render';
import type { Dict } from '../game.svelte';
import { clone } from '../views/viewlib';

/** The token a pick starts from: the intent's ctx.token, or a token of its ctx.actor. */
export function pickFrom(payload: Dict, tokens: Dict[]): string {
  const ctx: Dict = payload.ctx && typeof payload.ctx === 'object' ? payload.ctx : {};
  if (ctx.token) return String(ctx.token);
  if (ctx.actor) return String(tokens.find((t) => String(t.actor ?? '') === String(ctx.actor))?.id ?? '');
  return '';
}

export function pickTarget(grid: Grid, tokens: Dict[], payload: Dict, p: Vec, gm: boolean): string | Dict | null {
  const cell = grid.cellAt(p);
  switch (String(payload.pick ?? '')) {
    case 'token':
      for (let i = tokens.length - 1; i >= 0; i--) {
        const t = tokens[i];
        if (!gm && t.hidden) continue;
        const c = tokenPos(t);
        if (Math.hypot(c.x - p.x, c.y - p.y) <= Number(t.size ?? 1) * 0.5) return `token:${t.id}`;
      }
      return null;
    case 'cell':
      return grid.inBounds(cell) ? cellKey(cell) : null;
    case 'area': {
      if (!grid.inBounds(cell)) return null;
      const out: Dict = payload.area && typeof payload.area === 'object' ? clone(payload.area) : {};
      const shape = String(out.shape ?? 'circle');
      const from = pickFrom(payload, tokens);
      const origin = tokens.find((t) => String(t.id) === from);
      out.shape = shape;
      if (shape === 'circle' || !from || !origin) {
        out.at = cellKey(cell);
        out.direction = 0;
      } else {
        const o = tokenPos(origin);
        out.at = `token:${from}`;
        out.direction = (Math.atan2(p.y - o.y, p.x - o.x) * 180) / Math.PI;
      }
      out.from = from ? `token:${from}` : '';
      return out;
    }
  }
  return null;
}

/** How many creatures a pick takes: a spell for up to three (Bless) says so
 *  in `picks` (a playtest's Bless took the first tap and no more). */
export function pickCount(payload: Dict): number {
  if (String(payload.pick ?? '') !== 'token') return 1;
  const n = Math.floor(Number(payload.picks ?? 1));
  return Number.isFinite(n) && n > 1 ? n : 1;
}

/** A creature tapped while picking several: added, or (tapped again) taken back. */
export function togglePicked(picked: string[], target: string, max: number): string[] {
  if (picked.includes(target)) return picked.filter((x) => x !== target);
  return picked.length >= max ? picked : [...picked, target];
}

/** The intent to send once its target (or, picking several, its targets) is picked. */
export function withTarget(payload: Dict, target: string | Dict | string[], scene: string): Dict {
  const out = clone(payload);
  delete out.pick;
  delete out.picks;
  delete out.area;
  delete out.label;
  if (!out.ctx || typeof out.ctx !== 'object') out.ctx = {};
  out.ctx.target = target;
  out.ctx.scene = scene;
  return out;
}

/** The creatures a token pick may take: those on the map but the picker's
 *  own token and the markers (a place, the party on a regional map). */
export function pickables(tokens: Dict[], payload: Dict, gm = false): Dict[] {
  const from = pickFrom(payload, tokens);
  return tokens.filter((t) => {
    const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
    return String(t.id) !== from && (gm || !t.hidden) && !tags.includes('place') && !tags.includes('party');
  });
}

/** What a token pick says when there is nothing in sight to pick: a
 *  playtest's players were asked to tap a creature on a black map. */
export const NOTHING_IN_SIGHT = 'Nothing in sight: walls or darkness block your view. Move, or ask the DM.';

/** What the banner says while a pick is waiting; with the tokens on the
 *  map (a player's), that there is nothing to pick when there isn't. */
export function pickWords(payload: Dict, tokens?: Dict[]): string {
  if (tokens && String(payload.pick ?? '') === 'token' && pickables(tokens, payload).length === 0) return NOTHING_IN_SIGHT;
  const many = pickCount(payload);
  if (many > 1) return `${String(payload.label ?? 'Choose')}: tap up to ${many} creatures on the map, then Done`;
  const what = String(payload.pick ?? 'target');
  const noun = what === 'token' ? 'a creature' : what === 'cell' ? 'a space' : 'where it goes';
  return `${String(payload.label ?? 'Choose')}: tap ${noun} on the map`;
}
