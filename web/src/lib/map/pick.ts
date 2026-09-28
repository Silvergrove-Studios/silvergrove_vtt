// Picking a target on the map for an intent that wants one (an attack, a
// spell's area): what was picked, as the host's MapQuery.pick_target says
// it — "token:<id>", a "q,r" cell, or an area spec — and the intent as it
// is then sent, with ctx.target and ctx.scene filled in; or, with no target
// at all, sent to be rolled and nothing applied (theatre of the mind).
import { Grid, cellKey, type Vec } from '../grid';
import { isDead, tokenPos } from './render';
import type { Dict } from '../game.svelte';
import { clone } from '../views/viewlib';

/** The token a pick starts from: the intent's ctx.token, or a token of its ctx.actor. */
export function pickFrom(payload: Dict, tokens: Dict[]): string {
  const ctx: Dict = payload.ctx && typeof payload.ctx === 'object' ? payload.ctx : {};
  if (ctx.token) return String(ctx.token);
  if (ctx.actor) return String(tokens.find((t) => String(t.actor ?? '') === String(ctx.actor))?.id ?? '');
  return '';
}

/** Whether a pick may take the dead: one that brings them back (Revivify's) says so. */
export function takesDead(payload: Dict): boolean {
  return payload.dead === true;
}

/** A token the DM put down with no stat block (a cart, a villager): there, but nothing the rules can act on. */
export function isThing(t: Dict): boolean {
  return Array.isArray(t.tags) && (t.tags as unknown[]).includes('thing');
}

/** Whether a token pick may take this token: not the dead (unless the pick
 *  brings them back), not a thing with no stat block, not one hidden from a player. */
function takes(t: Dict, payload: Dict, gm: boolean): boolean {
  return (gm || !t.hidden) && !isThing(t) && (takesDead(payload) || !isDead(t));
}

/** What a tap at `p` picks. `hit` is the token the map says was tapped: the
 *  one drawn there, of several fanned out on one cell (a playtest's tap went
 *  to whichever was last in the list, by position). The dead are passed
 *  over for whoever else is under the tap. */
export function pickTarget(grid: Grid, tokens: Dict[], payload: Dict, p: Vec, gm: boolean, hit: Dict | null = null): string | Dict | null {
  const cell = grid.cellAt(p);
  switch (String(payload.pick ?? '')) {
    case 'token':
      if (hit && takes(hit, payload, gm)) return `token:${hit.id}`;
      for (let i = tokens.length - 1; i >= 0; i--) {
        const t = tokens[i];
        if (!takes(t, payload, gm)) continue;
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

/** What each of a pick's several is, when one creature may have more than
 *  one (Magic Missile's darts, Scorching Ray's rays): "dart", "ray" — or ''
 *  when each is a creature of its own (Bless). */
export function pickEach(payload: Dict): string {
  const each = String(payload.each ?? '');
  return /^[a-z]+$/.test(each) && pickCount(payload) > 1 ? each : '';
}

/** A creature tapped while picking several: added, or (tapped again) taken
 *  back; picking darts (`repeat`), tapped again is another dart at it. */
export function togglePicked(picked: string[], target: string, max: number, repeat = false): string[] {
  if (!repeat && picked.includes(target)) return picked.filter((x) => x !== target);
  return picked.length >= max ? picked : [...picked, target];
}

/** One dart fewer at a creature. */
export function unpick(picked: string[], target: string): string[] {
  const i = picked.lastIndexOf(target);
  return i < 0 ? picked : [...picked.slice(0, i), ...picked.slice(i + 1)];
}

/** The intent as it goes, without what only the pick needed. */
function sendable(payload: Dict): Dict {
  const out = clone(payload);
  for (const k of ['pick', 'picks', 'area', 'label', 'each', 'dead']) delete out[k];
  if (!out.ctx || typeof out.ctx !== 'object') out.ctx = {};
  return out;
}

/** The intent to send once its target (or, picking several, its targets) is picked. */
export function withTarget(payload: Dict, target: string | Dict | string[], scene: string): Dict {
  const out = sendable(payload);
  out.ctx.target = target;
  out.ctx.scene = scene;
  return out;
}

/** The intent sent with no target: the ruleset rolls everything and
 *  applies nothing (the owner: people play theatre of the mind with no
 *  tokens all the time, and still need to see the rolls). */
export function withNoTarget(payload: Dict, scene: string): Dict {
  const out = sendable(payload);
  delete out.ctx.target;
  out.ctx.no_target = true;
  if (scene) out.ctx.scene = scene;
  return out;
}

/** Whether a pick offers "No target: just roll": one of a creature or of an
 *  area (a space, for putting something on the map, needs the map). */
export function offersNoTarget(payload: Dict): boolean {
  return ['token', 'area'].includes(String(payload.pick ?? ''));
}

/** Whether the scene on a screen is a battle map to pick on: not a region
 *  (the table says which each map is), and not no scene at all. */
export function onBattleMap(scene: Dict): boolean {
  return !!scene?.id && String(scene.role ?? '') !== 'regional';
}

/** Where a tap sends a token armed to move (tap it, then where it goes: a
 *  playtest's tablet player never managed to drag hers): the centre of the
 *  cell tapped — or the point itself, `snap` off, on a map drawn with no
 *  grid — and how many spaces that is from where it stands. null off the map. */
export function moveTo(grid: Grid, token: Dict, at: Vec, snap = true): { pos: [number, number]; spaces: number } | null {
  const cell = grid.cellAt(at);
  if (!grid.inBounds(cell)) return null;
  const c = snap ? grid.center(cell) : at;
  return { pos: [c.x, c.y], spaces: grid.steps(grid.cellAt(tokenPos(token)), cell) };
}

/** What the banner says while a token waits to be moved. */
export function moveWords(token: Dict): string {
  return `Move ${String(token.name ?? 'your token')}: tap where to go`;
}

/** The creatures a token pick may take: those on the map but the picker's
 *  own token, the markers (a place, the party on a regional map), the dead
 *  (unless the pick brings them back) and the things the DM put down with
 *  no stat block. */
export function pickables(tokens: Dict[], payload: Dict, gm = false): Dict[] {
  const from = pickFrom(payload, tokens);
  return tokens.filter((t) => {
    const tags: string[] = Array.isArray(t.tags) ? t.tags : [];
    return String(t.id) !== from && takes(t, payload, gm) && !tags.includes('place') && !tags.includes('party');
  });
}

/** A creature a pick lists by name: its target, its name and map label,
 *  whether it is one of the party, and whether only the DM sees it. */
export interface PickChoice {
  target: string;
  name: string;
  label: string;
  party: boolean;
  hidden: boolean;
}

/** The creatures a creature pick lists as buttons, to choose by name
 *  rather than by a tap on the map (a screen reader can't tap a canvas, and
 *  a playtest's agents, playing through the page's structure, fought line
 *  of sight far harder than people): the pickables in the picker's sight
 *  (`sees`: the rest of the party is on a player's map wherever they are),
 *  nearest the picker first. */
export function pickChoices(tokens: Dict[], payload: Dict, opts: { gm?: boolean; sees?: (p: Vec) => boolean } = {}): PickChoice[] {
  if (String(payload.pick ?? '') !== 'token') return [];
  const from = tokens.find((t) => String(t.id) === pickFrom(payload, tokens));
  const o = from ? tokenPos(from) : null;
  const away = (t: Dict) => (o ? Math.hypot(tokenPos(t).x - o.x, tokenPos(t).y - o.y) : 0);
  return pickables(tokens, payload, opts.gm)
    .filter((t) => !opts.sees || opts.sees(tokenPos(t)))
    .map((t, i) => ({ t, i, d: away(t) }))
    .sort((a, b) => a.d - b.d || a.i - b.i)
    .map(({ t }) => {
      const name = String(t.name ?? '') || String(t.label ?? '') || 'a creature';
      const label = String(t.label ?? '');
      return { target: `token:${t.id}`, name, label: label === name ? '' : label, party: String(t.owner ?? '') !== '', hidden: !!t.hidden };
    });
}

/** What a token pick says when there is nothing in sight to pick: a
 *  playtest's players were asked to tap a creature on a black map. */
export const NOTHING_IN_SIGHT = 'Nothing in sight: walls or darkness block your view. Move, or ask the DM.';

/** What a tap on the dead says while a pick waits. */
export const DEAD_WORDS = 'That one’s dead';

/** Whether a pick's tap on `hit` found only the dead (a pick that doesn't bring them back). */
export function tappedTheDead(hit: Dict | null, payload: Dict): boolean {
  return !!hit && String(payload.pick ?? '') === 'token' && isDead(hit) && !takesDead(payload);
}

/** What the banner says while a pick is waiting; with the tokens on the
 *  map (a player's, and what their characters see of it), that there is
 *  nothing to pick when there isn't. */
export function pickWords(payload: Dict, tokens?: Dict[], sees?: (p: Vec) => boolean): string {
  if (tokens && String(payload.pick ?? '') === 'token' && pickChoices(tokens, payload, { sees }).length === 0) return NOTHING_IN_SIGHT;
  const many = pickCount(payload);
  const each = pickEach(payload);
  // (a playtest's player read "1 of up to 3" as tapping one goblin three times)
  if (each) return `${many} ${each}s: tap a creature for each ${each} (the same one again for another), then Done`;
  if (many > 1) return `${String(payload.label ?? 'Choose')}: tap up to ${many} creatures on the map, then Done`;
  const what = String(payload.pick ?? 'target');
  const noun = what === 'token' ? 'a creature' : what === 'cell' ? 'a space' : 'where it goes';
  return `${String(payload.label ?? 'Choose')}: tap ${noun} on the map`;
}

/** What has been chosen so far, in words (`name` names a target): the
 *  creature, the several with their count, the darts with theirs. */
export function pickedWords(payload: Dict, picked: string[], name: (target: string) => string): string {
  if (!picked.length) return '';
  const many = pickCount(payload);
  const each = pickEach(payload);
  if (each) {
    const counts = new Map<string, number>();
    for (const t of picked) counts.set(t, (counts.get(t) ?? 0) + 1);
    const who = [...counts].map(([t, n]) => (n > 1 ? `${name(t)} ×${n}` : name(t))).join(', ');
    const rest = picked.length < many ? '; the rest go to those chosen' : '';
    return `${who}: ${picked.length} of ${many} ${each}s${rest}`;
  }
  const who = picked.map(name).join(', ');
  return many > 1 ? `${String(payload.label ?? 'Choose')} → ${who} (${picked.length} of up to ${many})` : `${String(payload.label ?? 'Choose')} → ${who}`;
}
