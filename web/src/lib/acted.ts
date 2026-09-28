// What a player is told of an action the table has done when nothing else
// on their screen shows it: "Cast Minor Illusion", "Used Arcane Recovery".
// A playtest's bard cast a cantrip, saw nothing change, and couldn't tell
// whether the tap had gone; its wizard pressed Use on Arcane Recovery and
// saw only a 1 turn to a 0.

// the verbs a sheet's buttons start with, as what was done
const DONE: Record<string, string> = {
  cast: 'Cast',
  use: 'Used',
  prepare: 'Prepared',
  unprepare: 'Unprepared',
  equip: 'Equipped',
  unequip: 'Unequipped',
  drop: 'Dropped',
  gain: 'Gained',
  learn: 'Learned',
  forget: 'Forgot',
  buy: 'Bought',
  sell: 'Sold',
  give: 'Gave',
  take: 'Took',
  put: 'Put',
  end: 'Ended',
  start: 'Started',
  set: 'Set',
  clear: 'Cleared',
  withdraw: 'Withdrew',
  track: 'Tracked',
};

// whole labels that read better said another way
const PHRASES: Record<string, string> = { 'end turn': 'Ended your turn' };

const BEFORE = ['on', 'onto', 'to', 'at', 'for', 'from', 'with', 'in', 'into', 'off', 'as'];

/** What a toast says of a button's action done: its label as something
 *  done, with the name of the thing it was done to (the row it is on). A
 *  label that isn't a verb is itself, ticked ("Short rest ✓"). */
export function actedWords(label: string, name = ''): string {
  // "Cast — Careful Spell": the Metamagic armed is the button's, not the spell's
  let words = String(label ?? '').split(' — ')[0].trim();
  // "Ready for level 2: Gain a level": what it does is after the colon
  const colon = words.lastIndexOf(': ');
  if (colon >= 0) words = words.slice(colon + 2).trim();
  // "Dash [1 action]": what it costs is not what it did
  words = words.replace(/\s*\[[^\]]*\]$/, '').trim();
  if (!words) return '';
  const phrase = PHRASES[words.toLowerCase()];
  if (phrase) return phrase;
  const thing = String(name ?? '').trim();
  const named = thing !== '' && !words.toLowerCase().includes(thing.toLowerCase());
  const [first, ...rest] = words.split(/\s+/);
  const done = DONE[first.toLowerCase()];
  if (!done) return named ? `${words}: ${thing} ✓` : `${words} ✓`;
  if (!named) return [done, ...rest].join(' ');
  // "Take it off": the thing is "it"; "Cast on yourself": before the rest;
  // "Drop one": after it
  const it = rest.findIndex((w) => w.toLowerCase() === 'it');
  if (it >= 0) return [done, ...rest.slice(0, it), thing, ...rest.slice(it + 1)].join(' ');
  if (rest.length === 0 || BEFORE.includes(rest[0].toLowerCase())) return [done, thing, ...rest].join(' ');
  return `${[done, ...rest].join(' ')}: ${thing}`;
}
