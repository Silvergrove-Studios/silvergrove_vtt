// What the pill says while the DM waits on a player: what is asked, not
// just "answer" (a playtest's player on a phone missed a roll the DM had
// asked for while on another tab). And a reaction's card (`urgent`: Shield
// against a hit, an opportunity attack): at the front at once, its seconds
// counting down, and everyone told who the table waits on (`waiting`).
import type { Dict } from './views/viewlib';

// what the DM showed, by the kind of card it came from (its ref's prefix)
const SHOWN_KINDS: Record<string, string> = { place: 'a place', actor: 'someone', picture: 'a picture', note: 'a handout', handout: 'a handout' };

/** The pill's words for something the DM showed that waits while I'm busy:
 *  what it is, not just "look" (a playtest's players didn't know a pill from
 *  a portrait). */
export function handoutPill(h: Dict | null | undefined): string {
  if (!h || typeof h !== 'object') return '';
  const ref = String(h.ref ?? '');
  const kind = SHOWN_KINDS[ref.includes(':') ? ref.split(':')[0] : ''] ?? '';
  const title = String(h.title ?? '').trim();
  if (!title) return `The DM is showing you ${kind || 'something'} ›`;
  return `The DM is showing you ${kind ? `${kind}: ` : ''}${title} ›`;
}

function isCard(p: unknown): p is Dict {
  return !!p && typeof p === 'object';
}

/** The card to put in front: a reaction's (urgent) before any other, then the
 *  newest by when it opened (the table's ids are random: a playtest's player was
 *  sent to an old question left open, not the live one). */
export function frontPrompt(prompts: Dict[]): Dict | null {
  let best: Dict | null = null;
  for (const p of (prompts ?? []).filter(isCard)) {
    if (!best) {
      best = p;
      continue;
    }
    const pu = p.urgent === true ? 1 : 0;
    const bu = best.urgent === true ? 1 : 0;
    if (pu > bu || (pu === bu && Number(p.opened ?? 0) >= Number(best.opened ?? 0))) best = p;
  }
  return best;
}

/** What an urgent card is, at the head of its window and its pill: its form's
    own `heading` ("Your hit": a hit's choice of damage type, asked as it
    lands), else a reaction's ("Your reaction"; the DM's, "A reaction"). */
export function cardHeading(p: Dict | null | undefined, dm = false): string {
  const form = (p?.form && typeof p.form === 'object' ? p.form : {}) as Dict;
  const own = String(form.heading ?? '').trim();
  if (own) return own;
  if (p?.urgent === true) return dm ? 'A reaction' : 'Your reaction';
  return dm ? 'The rules ask you' : 'The DM asks';
}

/** What a card's button answers: its fields' values and the button's id as
    `choice`, as the host's own card answers (view_renderer.gd: a form's values
    are its fields'). The card's default is what it answers when nobody does;
    its other keys aren't the player's to send (a reaction's `late` went with
    every answer: a "No reaction" pressed was said as "No answer in time"). */
export function buttonAnswer(fields: Dict[], values: Dict, choice: string): Dict {
  const out: Dict = {};
  for (const f of fields ?? []) {
    const key = f && typeof f === 'object' ? String(f.key ?? '') : '';
    if (key !== '' && values && key in values) out[key] = values[key];
  }
  out.choice = choice;
  return out;
}

/** The pill's words for the prompts waiting on me, the one in front first.
    `names` gives my characters' names by id, said only when I have several. */
export function pillText(prompts: Dict[], names: Record<string, string> = {}): string {
  const list = (prompts ?? []).filter(isCard);
  const p = frontPrompt(list);
  if (!p) return '';
  const form = (p.form && typeof p.form === 'object' ? p.form : {}) as Dict;
  const title = String(form.title ?? p.title ?? '').trim();
  const who = Object.keys(names).length > 1 && p.actor && names[String(p.actor)] ? ` (${names[String(p.actor)]})` : '';
  const more = list.length > 1 ? ` (+${list.length - 1} more)` : '';
  if (p.urgent === true) return `${cardHeading(p)}${who}: ${title.replace(/\s*Your reaction\?$/, '').replace(/[.:]$/, '')}${more} ›`;
  // (a card of the rules' own, not the DM's: a spell's choice as it's cast)
  if (String(form.heading ?? '').trim() !== '' && title !== '') return `${cardHeading(p)}${who}: ${title}${more} ›`;
  if (title === '') return `The DM is waiting for your answer${more} ›`;
  const roll = Array.isArray(form.choices) && form.choices.length > 0;
  return `${roll ? 'The DM asks you to roll' : 'The DM asks'}${who}: ${title}${more} ›`;
}

/** The seconds a card has left, counted down from when its view came (`left`,
 *  as the table sent it, `viewAt` and `now` in ms); null when nothing counts
 *  (a card that waits for its answer). */
export function secondsLeft(rec: Dict | null | undefined, viewAt: number, now: number): number | null {
  if (!rec || typeof rec !== 'object' || rec.left === undefined || rec.left === null) return null;
  const left = Number(rec.left);
  if (!Number.isFinite(left)) return null;
  return Math.max(0, Math.ceil(left - Math.max(0, now - viewAt) / 1000));
}

/** What the table waits on, in words: "Waiting on Ana: a reaction (Sela) · 23 s",
 *  "Waiting on you: …", "Waiting on the DM: a reaction". */
export function waitingText(w: Dict, me: string, secs: number | null): string {
  const to = String(w?.to ?? '');
  const who = me !== '' && to === me ? 'you' : String(w?.who ?? 'a player');
  const what = String(w?.what ?? '').trim();
  return `Waiting on ${who}${what ? `: ${what}` : ''}${secs !== null ? ` · ${secs} s` : ''}`;
}

/** What the table waits on that isn't this screen's own card to answer: a
 *  player's are everyone else's; the DM's own (`to` "gm") are asked of the DM. */
export function waitingOn(waiting: Dict[] | undefined, me: string, dm: boolean): Dict[] {
  return (waiting ?? []).filter((w) => isCard(w) && (dm ? String(w.to ?? '') !== 'gm' : String(w.to ?? '') !== me));
}
