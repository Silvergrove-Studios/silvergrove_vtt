// Real dice typed in: a card's `dice` field (the rules ask what came up where
// a player rolls their own dice, or the DM the creatures'). A box a die: each
// face a whole number from 1 to its die's sides (a d10's 0 is its 10, as the
// die shows it), the total worked out as it's typed, and the next box taken
// as soon as a face can't grow another digit (a d6's one digit; a d20's 1 or
// 2 waits, it may be 10 or 20). Pure: DiceField draws it.
type Dict = Record<string, any>;

/** One value per die: its face, or null while it's empty or typed wrong. */
export type DiceValue = (number | null)[];

/** The sides of each die a field asks for ([20, 20]: two d20s). */
export function sidesOf(field: Dict): number[] {
  const d = field?.dice;
  return Array.isArray(d) ? d.map((n) => Math.max(1, Math.trunc(Number(n) || 0))) : [];
}

/** How many digits a die's faces can have (a d20's two, a d100's three). */
export function maxDigits(sides: number): number {
  return String(Math.max(1, Math.trunc(sides))).length;
}

/** A typed face as its die reads it: a whole number from 1 to its sides (a
 *  d10's or a d100's 0 is its 10 or 100), or null. */
export function faceOf(text: string, sides: number): number | null {
  const t = String(text ?? '').trim();
  if (!/^\d+$/.test(t)) return null;
  let n = Number(t);
  if (n === 0 && (sides === 10 || sides === 100)) n = sides;
  return n >= 1 && n <= sides ? n : null;
}

/** Whether a box holds a whole face already, so the next box takes the next
 *  keys: no digit could follow it (a d8's 5; a d20's 3, or its 20), or it's
 *  as long as the die's faces get. A face typed wrong isn't done: it waits to
 *  be put right. */
export function faceDone(text: string, sides: number): boolean {
  const t = String(text ?? '').trim();
  if (faceOf(t, sides) === null) return false;
  if (t.length >= maxDigits(sides)) return true;
  if (t === '0' && sides === 10) return true;
  return Number(t) * 10 > sides;
}

/** What's wrong with a dice field's value, or '': a die not typed yet, or a
 *  face its die can't show. */
export function diceProblem(field: Dict, value: unknown): string {
  const sides = sidesOf(field);
  const v = Array.isArray(value) ? value : [];
  const missing = sides.filter((_, i) => v[i] === null || v[i] === undefined || v[i] === '').length;
  for (let i = 0; i < sides.length; i++) {
    const f = v[i];
    if (f === null || f === undefined || f === '') continue;
    const n = Number(f);
    if (!Number.isInteger(n) || n < 1 || n > sides[i]) return `A d${sides[i]} shows 1 to ${sides[i]}.`;
  }
  if (missing > 0) return missing === sides.length && sides.length > 1 ? `Type each of the ${sides.length} dice.` : `Type ${missing === 1 ? 'the die' : `the ${missing} dice`} still to go.`;
  return '';
}

/** The total so far: the faces typed and the roll's own number (`plus`), or
 *  null while a die is still to type. */
export function diceTotal(field: Dict, value: unknown): number | null {
  const sides = sidesOf(field);
  const v = Array.isArray(value) ? value : [];
  let sum = Number(field?.plus ?? 0) || 0;
  for (let i = 0; i < sides.length; i++) {
    const n = Number(v[i]);
    if (v[i] === null || v[i] === undefined || !Number.isInteger(n) || n < 1 || n > sides[i]) return null;
    sum += n;
  }
  return sides.length ? sum : null;
}

/** A field's value as its boxes hold it: what the card gives (a face typed
 *  before, asked again) or what's been typed — a whole number each, kept even
 *  where its die can't show it, for the check to say so — else empty boxes. */
export function startingDice(field: Dict, v: unknown): DiceValue {
  const sides = sidesOf(field);
  const given = Array.isArray(v) ? v : Array.isArray(field?.default) ? field.default : [];
  return sides.map((_, i) => {
    const n = Number(given[i]);
    return given[i] !== null && given[i] !== undefined && given[i] !== '' && Number.isInteger(n) && n >= 0 ? n : null;
  });
}

/** Whether a card's dice are all typed (its fields of type dice): '' or the first problem. */
export function cardDiceProblem(fields: Dict[], values: Dict): string {
  for (const f of fields ?? []) {
    if (!f || typeof f !== 'object' || f.type !== 'dice') continue;
    const p = diceProblem(f, values?.[f.key]);
    if (p) return Array.isArray(fields) && fields.filter((x) => x?.type === 'dice').length > 1 ? `${f.label ?? f.key}: ${p}` : p;
  }
  return '';
}
