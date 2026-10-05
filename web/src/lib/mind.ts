// A fight in the theatre of the mind, as the screens show it: no map, the
// creatures in it as a list — "Who's in the fight" — each with its name,
// what the viewer may know of its health (the host sends a player only what
// the table shows them: a monster's marks, its hit points where they're
// shown exactly, or nothing), its conditions where the viewer sees them, and
// its place in the order. A target is chosen from that list, and an area's
// creatures are named from it ("Who does your Fireball catch?"): there is no
// place on a map for a template to fall. The host's scene says `space:
// "mind"`; its tokens are only who is in the fight, where they stand meaning
// nothing (hexmap/encounter/encounter.gd, Encounter.new_mind_scene).
import type { Dict } from './game.svelte';
import { currentTurnTokens, turnMembers, turnNote } from './turns';
import { hpWords, isDead, isObject } from './map/render';
import { clone } from './views/viewlib';

/** Whether a scene is a fight in the theatre of the mind. */
export function inMind(scene: Dict | null | undefined): boolean {
  return String(scene?.space ?? '') === 'mind';
}

/** One creature of the fight, as its list shows it. */
export interface MindRow {
  /** its token's id */
  id: string;
  /** what a pick sends for it: "token:<id>" */
  target: string;
  actor: string;
  name: string;
  /** its map label (GW1), when it isn't its name */
  label: string;
  /** one of the party (a player's) */
  party: boolean;
  /** the viewer's own */
  mine: boolean;
  /** hidden from the players (only the DM's list has these) */
  hidden: boolean;
  dead: boolean;
  /** its turn now */
  current: boolean;
  /** where it is in the order (0 first), or -1 when it isn't in it */
  order: number;
  /** the ruleset's label for its place in the order (its initiative), or '' */
  init: string;
  /** what the viewer may know of its health: "Bloodied", "Down", "Dead", or '' */
  marks: string;
  /** its hit points as the viewer may see them ("7/15"), or '' */
  hp: string;
  /** its conditions and what else is on it, where the viewer sees them */
  effects: string[];
  /** what the ruleset says of its turn now ("Movement 15 of 30 ft"), or '' */
  note: string;
  /** the DM's list: what the players see of a monster's health ("Bloodied", "nothing"), or '' */
  seen: string;
}

/** What the players see of a monster's health, for the DM's list: the
 *  table's way (`mode`: the rulesets' "exact", "marks" or "none"; '' when
 *  none says) with this creature's marks and hit points. */
export function playersSee(mode: string, marks: string, hp: string): string {
  if (mode === 'none') return 'nothing of its health';
  if (mode === 'exact') return [marks, hp && `${hp} hp`].filter(Boolean).join(', ') || 'its hit points';
  if (mode === 'marks') return marks || 'no mark yet';
  return '';
}

const MARKS: [string, string][] = [
  ['dead', 'Dead'],
  ['down', 'Down'],
  ['bloodied', 'Bloodied'],
];

/** What the viewer may know of a creature's health from its token: the
 *  ruleset's marks as the host sent them (a player gets none where the
 *  table shows nothing). */
export function marksOf(t: Dict): string {
  const tags: unknown[] = Array.isArray(t.tags) ? t.tags : [];
  for (const [tag, words] of MARKS) if (tags.includes(tag)) return words;
  return '';
}

/** A creature's hit points from an actor the viewer has (any ruleset's
 *  `hp` pool): "7/15", or ''. */
export function actorHp(actor: Dict | undefined): string {
  for (const res of Object.values((actor?.resources ?? {}) as Dict)) {
    const hp = res && typeof res === 'object' ? (res as Dict).hp : null;
    if (hp && typeof hp === 'object' && hp.current !== undefined && hp.max !== undefined) return `${Math.max(0, Math.round(Number(hp.current)))}/${Math.round(Number(hp.max))}`;
  }
  return '';
}

/** What is on a creature, as badges say it: each effect's label (its value
 *  after it), once each — where the viewer has the creature at all. */
export function effectsOf(actor: Dict | undefined): string[] {
  const out: string[] = [];
  for (const fx of (actor?.effects as Dict[]) ?? []) {
    if (!fx || typeof fx !== 'object') continue;
    const words = `${String(fx.label ?? fx.key ?? '')}${fx.value !== undefined && fx.value !== null && typeof fx.value !== 'object' ? ` ${fx.value}` : ''}`.trim();
    if (words && !out.includes(words)) out.push(words);
  }
  return out;
}

/** The fight's list: every creature on the scene (not a thing a spell put
 *  there), in the order's order when it runs, the rest after in the order
 *  they joined. `actors` are the viewer's (view.actors): the DM has every
 *  one, a player the party's; `gm` the DM's own list (hit points from the
 *  stat block). */
export function mindRows(scene: Dict, actors: Dict = {}, opts: { me?: string; gm?: boolean; seen?: string } = {}): MindRow[] {
  const tokens: Dict[] = ((scene?.tokens as Dict[]) ?? []).filter((t) => t && !isObject(t) && (t.actor || t.owner));
  const turns: Dict = scene?.turns ?? {};
  const ours = turns.running || String(turns.scene ?? '') === String(scene?.id ?? '');
  const order: string[] = ours ? ((turns.order as string[]) ?? []).map(String) : [];
  const place = new Map<string, number>();
  order.forEach((entry, i) => turnMembers(turns, entry).forEach((id) => place.has(id) || place.set(id, i)));
  const labels: Dict = turns.data?.labels ?? {};
  const up = new Set(ours ? currentTurnTokens(turns, tokens) : []);
  const rows = tokens.map((t, i) => {
    const id = String(t.id);
    const actor = t.actor ? (actors[String(t.actor)] as Dict | undefined) : undefined;
    const name = String(t.name ?? '') || String(actor?.name ?? '') || 'A creature';
    const label = String(t.label ?? '');
    const at = place.has(id) ? (place.get(id) as number) : -1;
    const entry = at >= 0 ? order[at] : '';
    const current = up.has(id);
    return {
      row: {
        id,
        target: `token:${id}`,
        actor: String(t.actor ?? ''),
        name,
        label: label === name ? '' : label,
        party: String(t.owner ?? '') !== '',
        mine: !!opts.me && String(t.owner ?? '') === opts.me,
        hidden: !!t.hidden,
        dead: isDead(t),
        current,
        order: at,
        init: entry ? String(labels[entry] ?? '') : '',
        marks: marksOf(t),
        hp: hpWords(t) || (opts.gm ? actorHp(actor) : ''),
        effects: effectsOf(actor),
        note: current ? turnNote(turns, [id]) : '',
        seen: opts.gm && String(t.owner ?? '') === '' ? playersSee(opts.seen ?? '', marksOf(t), hpWords(t) || actorHp(actor)) : '',
      } as MindRow,
      i,
    };
  });
  rows.sort((a, b) => (a.row.order < 0 ? 1e9 : a.row.order) - (b.row.order < 0 ? 1e9 : b.row.order) || a.i - b.i);
  return rows.map((r) => r.row);
}

/** A pick as the theatre of the mind asks it: a creature's (or several's)
 *  as it is, chosen from the list; an area's becomes the creatures it
 *  catches, named from the list — "Who does your Fireball catch?" — sent
 *  with the creatures as its target and `caught` (the ruleset takes them as
 *  the area's: the DM confirms what lands). `count` is how many could be
 *  caught (the creatures listed). Anything else (a space) is unchanged. */
export function mindPick(payload: Dict, count: number, gm = false): Dict {
  if (String(payload.pick ?? '') !== 'area') return payload;
  const out = clone(payload);
  const what = String(payload.what ?? '') || String(payload.label ?? '') || 'it';
  out.pick = 'token';
  out.picks = Math.max(1, Math.floor(count));
  delete out.area;
  delete out.each;
  out.caught = true;
  out.label = gm ? `Who does ${what} catch?` : `Who does your ${what} catch?`;
  out.ctx = { ...(out.ctx && typeof out.ctx === 'object' ? out.ctx : {}), caught: true };
  return out;
}

/** Whether a pick names an area's creatures (mindPick). */
export function namesCaught(payload: Dict | null): boolean {
  return !!payload && payload.caught === true;
}

/** What a pick in the theatre of the mind says while it waits. */
export function mindPickWords(payload: Dict): string {
  // (a spell's pick says its name: "Fire Bolt", not its button's "Cast")
  const label = namesCaught(payload) ? String(payload.label ?? 'Choose') : String(payload.what ?? '') || String(payload.label ?? 'Choose');
  const many = Math.max(1, Math.floor(Number(payload.picks ?? 1)) || 1);
  const each = String(payload.each ?? '');
  if (namesCaught(payload)) return `${label} Choose each creature it catches below, then Done.`;
  if (each && many > 1) return `${many} ${each}s: choose a creature below for each ${each} (the same one again for another), then Done.`;
  if (many > 1) return `${label}: choose up to ${many} creatures below, then Done.`;
  return `${label}: choose a creature below, then Done.`;
}

/** What has been chosen so far, in words: an area's "Fireball catches the
 *  Goblin 1, the Goblin 2", else as the map's pick says it. */
export function caughtWords(payload: Dict, picked: string[], name: (target: string) => string): string {
  if (!picked.length) return namesCaught(payload) ? 'Nobody chosen yet.' : '';
  const what = String(payload.what ?? '') || 'It';
  return `${what} catches ${picked.map(name).join(', ')}`;
}
