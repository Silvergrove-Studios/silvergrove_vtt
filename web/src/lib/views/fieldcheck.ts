// What a form field's value must be before a wizard moves on, and the
// arithmetic of the two fields that do more than hold a value:
//
// - `scores`: numbers for named stats (a character's abilities), made by
//   the method the table plays — a point buy, a fixed array or rolled
//   values, each assigned once — or typed (`manual`), with an optional
//   bonus on some of them (+2/+1 or +1/+1/+1 among a background's three).
// - `choose`: some of a list of described options (skills, spells, an
//   equipment package), a set number of them, some perhaps granted already.
//
// A field's properties may be `{expr = "…"}`: worked out against the form's
// data (`@values`, the answers so far; `@chosen`, the record each answer
// picked; and the view's own data) before the field is drawn or checked.
import { Expr } from '../expr';
import type { Dict } from './viewlib';

/** Every `{expr}` in a field's properties, worked out against the context. */
export function resolve(v: unknown, ctx: Dict): any {
  if (Array.isArray(v)) return v.map((x) => resolve(x, ctx));
  if (v && typeof v === 'object') {
    const o = v as Dict;
    if ('expr' in o && typeof o.expr === 'string' && Object.keys(o).every((k) => k === 'expr' || k === 'default')) {
      const r = Expr.evaluate(o.expr, ctx);
      return r === null || r === undefined ? (o.default ?? null) : r;
    }
    const out: Dict = {};
    for (const [k, x] of Object.entries(o)) out[k] = k === 'if' ? x : resolve(x, ctx);
    return out;
  }
  return v;
}

// --------------------------------------------------------------- scores --

export interface Stat {
  id: string;
  name: string;
  short?: string;
  text?: string;
  uses?: string;
}

export interface ScoresValue {
  method: string;
  /** a stat's score, or null while it has none (an array's or the rolls' numbers not given yet) */
  base: Record<string, number | null>;
  bonus: Record<string, number>;
  final: Record<string, number | null>;
}

export const STANDARD_COST: Record<string, number> = { 8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9 };

export function stats(f: Dict): Stat[] {
  return ((f.stats as Stat[]) ?? []).filter((s) => s && typeof s === 'object' && s.id);
}

export function modifier(score: number): number {
  return Math.floor((score - 10) / 2);
}

export function signed(n: number): string {
  return n >= 0 ? `+${n}` : `−${Math.abs(n)}`;
}

export interface PointBuy {
  budget: number;
  min: number;
  max: number;
  cost: Record<string, number>;
}

export function pointBuy(f: Dict): PointBuy {
  const p = (f.point_buy as Dict) ?? {};
  return { budget: Number(p.budget ?? 27), min: Number(p.min ?? 8), max: Number(p.max ?? 15), cost: (p.cost as Record<string, number>) ?? STANDARD_COST };
}

export function costOf(score: number, pb: PointBuy): number {
  const c = pb.cost[String(score)];
  return c === undefined ? Infinity : Number(c);
}

export function spent(base: Record<string, number | null>, pb: PointBuy): number {
  return Object.values(base).reduce((t: number, v) => t + costOf(Number(v), pb), 0);
}

/** Can this stat go up one within the budget? */
export function canRaise(id: string, base: Record<string, number | null>, pb: PointBuy): boolean {
  const v = Number(base[id] ?? pb.min);
  if (v >= pb.max) return false;
  return spent(base, pb) - costOf(v, pb) + costOf(v + 1, pb) <= pb.budget;
}

export function canLower(id: string, base: Record<string, number | null>, pb: PointBuy): boolean {
  return Number(base[id] ?? pb.min) > pb.min;
}

/** The numbers a method hands out to assign (the array, or the rolls), or null. */
export function pool(f: Dict): number[] | null {
  if (f.method === 'array') return ((f.array as number[]) ?? []).map(Number);
  if (f.method === 'rolled') {
    const v = (f.rolled as Dict)?.values;
    return Array.isArray(v) && v.length ? v.map(Number) : null;
  }
  return null;
}

function sameNumbers(a: number[], b: number[]): boolean {
  if (a.length !== b.length) return false;
  const x = [...a].sort((p, q) => p - q);
  const y = [...b].sort((p, q) => p - q);
  return x.every((v, i) => v === y[i]);
}

/** A fresh start, the player's to fill (the team: a suggestion taken
 * unasked takes the fun out of it): a point buy's minimums, an array's or
 * the rolls' numbers not given to anything yet, typed scores at 10. */
export function startingBase(f: Dict): Record<string, number | null> {
  const ids = stats(f).map((s) => s.id);
  const out: Record<string, number | null> = {};
  if (f.method === 'point_buy') {
    const pb = pointBuy(f);
    for (const id of ids) out[id] = pb.min;
  } else if (f.method === 'array' || f.method === 'rolled') {
    for (const id of ids) out[id] = null;
  } else {
    const m = (f.manual as Dict) ?? {};
    for (const id of ids) out[id] = Number(m.default ?? 10);
  }
  return out;
}

/** The class's suggestion, when the player asks for it: the numbers the
 * method gives, highest where the suggestion is highest (a point buy: the
 * suggestion itself, which is a valid buy), else the method's plain start. */
export function suggestedBase(f: Dict): Record<string, number | null> {
  const ids = stats(f).map((s) => s.id);
  const sug = (f.suggest && typeof f.suggest === 'object' ? f.suggest : null) as Record<string, number> | null;
  const out: Record<string, number | null> = {};
  if (f.method === 'point_buy') {
    const pb = pointBuy(f);
    for (const id of ids) out[id] = pb.min;
    if (sug && ids.every((id) => typeof sug[id] === 'number' && sug[id] >= pb.min && sug[id] <= pb.max)) {
      const try_: Record<string, number> = {};
      for (const id of ids) try_[id] = Number(sug[id]);
      if (spent(try_, pb) <= pb.budget) return try_;
    }
    return out;
  }
  const nums = pool(f);
  if (nums) {
    const sorted = [...nums].sort((a, b) => b - a);
    const order = sug ? [...ids].sort((a, b) => Number(sug[b] ?? 0) - Number(sug[a] ?? 0)) : ids;
    order.forEach((id, i) => (out[id] = sorted[i] ?? 10));
    return out;
  }
  const m = (f.manual as Dict) ?? {};
  for (const id of ids) out[id] = Number(sug?.[id] ?? m.default ?? 10);
  return out;
}

/** The bonus a background gives by default: +2 on the class's key
 * ability when it is offered, else the first offered; +1 on the next. */
export function startingBonus(f: Dict): Record<string, number> {
  const b = f.bonus as Dict | null;
  const among = ((b?.among as string[]) ?? []).filter(Boolean);
  if (!b || among.length < 2) return {};
  const primary = ((f.primary as string[]) ?? []).filter((p) => among.includes(p));
  const two = primary[0] ?? among[0];
  const one = primary.find((p) => p !== two) ?? among.find((a) => a !== two)!;
  return { [two]: 2, [one]: 1 };
}

export function finalScores(f: Dict, base: Record<string, number | null>, bonus: Record<string, number>): Record<string, number | null> {
  const cap = Number((f.bonus as Dict)?.cap ?? 20);
  const out: Record<string, number | null> = {};
  for (const s of stats(f)) {
    const v = base[s.id];
    if (v === null || v === undefined) {
      out[s.id] = null;
      continue;
    }
    const b = Number(v);
    const plus = Number(bonus[s.id] ?? 0);
    out[s.id] = plus > 0 ? Math.min(cap, b + plus) : b;
  }
  return out;
}

export function scoresValue(f: Dict, base: Record<string, number | null>, bonus: Record<string, number>): ScoresValue {
  return { method: String(f.method ?? 'manual'), base: { ...base }, bonus: { ...bonus }, final: finalScores(f, base, bonus) };
}

/** Does the bonus follow one of the patterns, on the abilities offered? */
export function bonusProblem(f: Dict, bonus: Record<string, number>): string {
  const b = f.bonus as Dict | null;
  const among = ((b?.among as string[]) ?? []).filter(Boolean);
  if (!b || among.length < 2) return '';
  const given = Object.entries(bonus ?? {}).filter(([, v]) => Number(v) > 0);
  if (given.some(([k]) => !among.includes(k))) return 'Your background’s increases go on its own three abilities.';
  const patterns = ((b.patterns as number[][]) ?? [[2, 1], [1, 1, 1]]).map((p) => [...p].map(Number).sort((x, y) => y - x));
  const have = given.map(([, v]) => Number(v)).sort((x, y) => y - x);
  if (!patterns.some((p) => p.length === have.length && p.every((v, i) => v === have[i]))) return 'Choose where your background’s increases go: +2 and +1, or +1 to all three.';
  return '';
}

/** What is wrong with a scores value, or "". */
export function scoresProblem(f: Dict, value: unknown): string {
  const v = value as ScoresValue | null;
  const ids = stats(f).map((s) => s.id);
  if (f.method === 'rolled' && !pool(f)) return 'Roll your scores first.';
  if (!v || !v.base || ids.some((id) => v.base[id] === null || v.base[id] === undefined || !Number.isInteger(Number(v.base[id])))) {
    const left = ids.filter((id) => v?.base?.[id] === null || v?.base?.[id] === undefined).length;
    return left > 0 && (f.method === 'array' || f.method === 'rolled') ? `Give a number to each ability (${left} to go).` : 'Give every ability a score.';
  }
  const base = ids.map((id) => Number(v.base[id]));
  if (f.method === 'point_buy') {
    const pb = pointBuy(f);
    if (base.some((x) => x < pb.min || x > pb.max)) return `Scores bought with points run from ${pb.min} to ${pb.max}.`;
    const left = pb.budget - spent(v.base, pb);
    if (left < 0) return `That costs ${-left} more ${Math.abs(left) === 1 ? 'point' : 'points'} than you have.`;
    if (left > 0 && ids.some((id) => canRaise(id, v.base, pb))) return `You have ${left} ${left === 1 ? 'point' : 'points'} left: tap + on an ability to spend ${left === 1 ? 'it' : 'them'}.`;
  } else if (f.method === 'array' || f.method === 'rolled') {
    const nums = pool(f)!;
    if (!sameNumbers(base, nums)) return `Use each of ${nums.join(', ')} once.`;
  } else {
    const m = (f.manual as Dict) ?? {};
    const lo = Number(m.min ?? 1);
    const hi = Number(m.max ?? 30);
    if (base.some((x) => x < lo || x > hi)) return `Scores run from ${lo} to ${hi}.`;
  }
  return bonusProblem(f, v.bonus ?? {});
}

// --------------------------------------------------------------- choose --

export interface Choice {
  id: string;
  name: string;
  text?: string;
  tag?: string;
  sub?: string;
  [k: string]: any;
}

export function choiceList(v: unknown): Choice[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((o) => o !== null && o !== undefined)
    .map((o) => (o && typeof o === 'object' ? ({ ...(o as Dict), id: String((o as Dict).id ?? (o as Dict).name ?? ''), name: String((o as Dict).name ?? (o as Dict).id ?? '') } as Choice) : { id: String(o), name: String(o) }));
}

/** The picks a choose field needs: [least, most]. */
export function chooseBounds(f: Dict): [number, number] {
  if (f.single) return [1, 1];
  if (f.count !== undefined && f.count !== null) {
    const n = Math.max(0, Number(f.count) || 0);
    return [n, n];
  }
  return [Math.max(0, Number(f.min ?? 0) || 0), f.max === undefined || f.max === null ? Infinity : Number(f.max)];
}

export function allowedIds(f: Dict): string[] | null {
  return Array.isArray(f.allowed) ? f.allowed.map(String) : null;
}

export function fixedIds(f: Dict): string[] {
  return Array.isArray(f.fixed) ? f.fixed.map(String) : [];
}

export function picked(f: Dict, value: unknown): string[] {
  if (f.single) return value ? [String(value)] : [];
  return Array.isArray(value) ? value.map(String) : [];
}

/** What is wrong with a choose value, given the options there are (null: not known yet). */
export function chooseProblem(f: Dict, value: unknown, options: Choice[] | null = null): string {
  const [lo, hi] = chooseBounds(f);
  const ids = picked(f, value);
  const fixed = fixedIds(f);
  const allowed = allowedIds(f);
  const known = options ? new Set(options.map((o) => o.id)) : null;
  if (ids.some((id) => fixed.includes(id))) return 'That one is yours already.';
  if (ids.some((id) => (allowed && !allowed.includes(id)) || (known && !known.has(id)))) return 'That choice is not on offer.';
  if (f.single) return ids.length === 1 ? '' : `Choose ${String(f.what ?? 'one')}.`;
  const what = String(f.what ?? (lo === 1 && hi === 1 ? 'one' : ''));
  if (ids.length < lo) {
    const n = lo - ids.length;
    return `Choose ${n} more${what && what !== 'one' ? ' ' + what : ''}.`;
  }
  if (ids.length > hi) return `That is ${ids.length - hi} too many: choose ${hi}.`;
  return '';
}

/** Tapping an option: in (or the only one, for a single choice), or out; nothing past the limit. */
export function toggle(f: Dict, value: unknown, id: string): string | string[] {
  if (f.single) return id;
  const ids = picked(f, value);
  if (ids.includes(id)) return ids.filter((x) => x !== id);
  const [, hi] = chooseBounds(f);
  if (ids.length >= hi) return ids;
  return [...ids, id];
}

// ---------------------------------------------------------------- field --

/** What is wrong with any field's value before moving on, or "". */
export function fieldProblem(f: Dict, value: unknown, options: Choice[] | null = null): string {
  switch (String(f.type ?? 'string')) {
    case 'scores':
      return scoresProblem(f, value);
    case 'choose':
      return chooseProblem(f, value, options);
    default:
      if (f.required && (value === undefined || value === null || String(value).trim() === '')) return String(f.required_text ?? `${f.label ?? f.key}: fill this in.`);
      return '';
  }
}
