// What the pill says while the DM waits on a player: what is asked, not
// just "answer" (a playtest's player on a phone missed a roll the DM had
// asked for while on another tab).
import type { Dict } from './views/viewlib';

/** The pill's words for the prompts waiting on me, the newest first.
    `names` gives my characters' names by id, said only when I have several. */
export function pillText(prompts: Dict[], names: Record<string, string> = {}): string {
  const list = (prompts ?? []).filter((p) => p && typeof p === 'object');
  if (list.length === 0) return '';
  const p = list[list.length - 1];
  const form = (p.form && typeof p.form === 'object' ? p.form : {}) as Dict;
  const title = String(form.title ?? p.title ?? '').trim();
  const who = Object.keys(names).length > 1 && p.actor && names[String(p.actor)] ? ` (${names[String(p.actor)]})` : '';
  const more = list.length > 1 ? ` (+${list.length - 1} more)` : '';
  if (title === '') return `The DM is waiting for your answer${more} ›`;
  const roll = Array.isArray(form.choices) && form.choices.length > 0;
  return `${roll ? 'The DM asks you to roll' : 'The DM asks'}${who}: ${title}${more} ›`;
}
