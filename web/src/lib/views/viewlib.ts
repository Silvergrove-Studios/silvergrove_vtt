// What a ruleset's view means, apart from how it looks (the host's
// ViewRenderer, hexmap/ui/views/view_renderer.gd): the value a node shows,
// JSON pointers into the data, intents with their "$/pointer" strings
// filled in and "$value"/"$values" put in, the choices a field's `from`
// names, and the generic card for a compendium entry.
import { Expr, truthy } from '../expr';

export type Dict = Record<string, any>;

/** A deep copy of JSON data (reactive proxies included, which structuredClone refuses). */
export function clone<T>(v: T): T {
  return v === undefined ? v : (JSON.parse(JSON.stringify(v)) as T);
}

/** JSON-pointer lookup: "/a/b/0" (the leading slash is optional). */
export function atPointer(doc: unknown, pointer: string): any {
  let v: any = doc;
  for (const part of String(pointer).replace(/^\//, '').split('/')) {
    if (part === '') continue;
    const key = part.replace(/~1/g, '/').replace(/~0/g, '~');
    if (v && typeof v === 'object' && !Array.isArray(v) && key in v) v = v[key];
    else if (Array.isArray(v) && /^-?\d+$/.test(key) && Number(key) >= 0 && Number(key) < v.length) v = v[Number(key)];
    else return null;
  }
  return v === undefined ? null : v;
}

/** The value a node shows: an expression, a bound pointer, or its literal `key` (or `text`). */
export function valueOf(node: Dict, ctx: Dict, key = 'value'): any {
  if ('expr' in node) return Expr.evaluate(String(node.expr), ctx);
  if ('bind' in node) return atPointer(ctx, String(node.bind));
  return node[key] ?? node.text ?? null;
}

/** Does a node's `if` let it show? */
export function shown(node: Dict, ctx: Dict): boolean {
  return !('if' in node) || truthy(Expr.evaluate(String(node.if), ctx));
}

/** An intent with its "$/pointer" strings resolved against the data. */
export function fillIntent(template: unknown, ctx: Dict): any {
  if (typeof template === 'string' && template.startsWith('$/')) return atPointer(ctx, template.slice(1));
  if (Array.isArray(template)) return template.map((t) => fillIntent(t, ctx));
  if (template && typeof template === 'object') {
    const out: Dict = {};
    for (const [k, v] of Object.entries(template)) out[k] = fillIntent(v, ctx);
    return out;
  }
  return template;
}

/** Every `token` string ("$value", "$values") in an intent, at any depth, replaced by the value. */
export function putValue(tpl: unknown, v: unknown, token = '$value'): any {
  if (tpl === token) return v;
  if (Array.isArray(tpl)) return tpl.map((t) => putValue(t, v, token));
  if (tpl && typeof tpl === 'object') {
    const out: Dict = {};
    for (const [k, x] of Object.entries(tpl)) out[k] = putValue(x, v, token);
    return out;
  }
  return tpl;
}

export function isTyped(v: unknown): v is { total: number; parts: Dict[] } {
  return !!v && typeof v === 'object' && Array.isArray((v as Dict).parts);
}

/** A number as the sheets show it: whole numbers plainly, others to one place. */
export function num(v: unknown): string {
  const f = Number(v ?? 0);
  if (!Number.isFinite(f)) return String(v);
  return Math.abs(f - Math.floor(f)) < 1e-9 ? String(Math.floor(f)) : f.toFixed(1);
}

export function textOf(v: unknown): string {
  if (v === null || v === undefined) return '';
  if (isTyped(v)) return num(v.total);
  if (typeof v === 'number') return num(v);
  if (typeof v === 'string') return v;
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return JSON.stringify(v);
}

/** A typed number's parts, one per line ("Dexterity +2"). */
export function breakdown(v: unknown): string {
  if (!isTyped(v)) return '';
  return v.parts.map((p) => `${String(p.label ?? '')} ${Number(p.value ?? 0) >= 0 ? '+' : ''}${num(p.value ?? 0)}`).join('\n');
}

export function optionLabel(it: unknown): string {
  if (it && typeof it === 'object') {
    const d = it as Dict;
    return String(d.name ?? d.label ?? d.id ?? '');
  }
  return String(it);
}

export function optionId(it: unknown): string {
  if (it && typeof it === 'object') {
    const d = it as Dict;
    return String(d.id ?? d.name ?? '');
  }
  return String(it);
}

/** The choices a `from` spec names: its `first` records, then the records at `bind` passing `if`. */
export function optionsFrom(spec: Dict, ctx: Dict): { id: string; name: string }[] {
  const out: { id: string; name: string }[] = [];
  for (const r of (spec.first as Dict[]) ?? []) if (r && typeof r === 'object') out.push({ id: String(r.id ?? ''), name: String(r.name ?? r.id ?? '') });
  let items = atPointer(ctx, String(spec.bind ?? ''));
  if (items && typeof items === 'object' && !Array.isArray(items)) items = Object.values(items);
  if (!Array.isArray(items)) return out;
  for (const it of items) {
    const sub = { ...ctx, item: it };
    if ('if' in spec && !truthy(Expr.evaluate(String(spec.if), sub))) continue;
    const id = Expr.evaluate(String(spec.id ?? '@item.id'), sub);
    const label = Expr.evaluate(String(spec.label ?? '@item.name'), sub);
    out.push({ id: id === null ? '' : String(id), name: label === null ? String(id) : String(label) });
  }
  return out;
}

/** A form field ready to draw: `from` turned into an enum over the data. */
export function withOptions(field: Dict, ctx: Dict): Dict {
  const f = clone(field);
  if (f.from && typeof f.from === 'object') {
    f.options = optionsFrom(f.from, ctx);
    f.type = 'enum';
    delete f.from;
  }
  return f;
}

/** A name's or a search's words, as the compendium's index splits them (letters and digits). */
export function wordsOf(s: string): string[] {
  return String(s ?? '').toLowerCase().match(/[a-z0-9]+/g) ?? [];
}

/** Does a name answer what was typed: every word typed is the start of a word
 * in it, in any order ("hooded lan" finds "Lantern, Hooded"; "thieves' tools"
 * finds "Thieves' Tools" — a playtest's DM found nothing for either)? */
export function matchWords(name: string, query: string): boolean {
  const have = wordsOf(name);
  return wordsOf(query).every((w) => have.some((h) => h.startsWith(w)));
}

/** The value an enum option stands for: a record's id, or the string itself. */
export function optionValue(o: unknown): string {
  if (o && typeof o === 'object') {
    const d = o as Dict;
    return String(d.id ?? d.name ?? '');
  }
  return String(o);
}

// ---------------------------------------------------------------- cards --

const SKIP = ['id', 'name', 'text', 'rules', '__pack', 'provenance'];

/** An entry's scalar fields as "key value" strings, for the generic card (EntryCard.facts). */
export function facts(e: Dict): string[] {
  const out: string[] = [];
  for (const k of Object.keys(e).sort()) {
    if (SKIP.includes(k)) continue;
    let v = e[k];
    if (v === null || v === undefined || (typeof v === 'object' && !Array.isArray(v))) continue;
    if (Array.isArray(v)) {
      if (!v.length || !v.every((x) => x === null || typeof x !== 'object')) continue;
      v = v.map((x) => textOf(x)).join(', ');
    }
    if (typeof v === 'boolean') {
      if (v) out.push(k.replace(/_/g, ' '));
      continue;
    }
    if (String(v) === '') continue;
    out.push(`${k.replace(/_/g, ' ')} ${textOf(v)}`);
  }
  return out;
}

export const GENERIC_CARD: Dict = {
  type: 'column',
  children: [
    { type: 'text', bind: '/entry/name', style: 'header' },
    { type: 'text', expr: "join(@facts, ' · ')", style: 'dim', if: 'len(@facts) > 0' },
    { type: 'text', bind: '/entry/text', rich: true, if: "(@entry.text ?? '') != ''" },
  ],
};

/** A collection's card: the ruleset's, or the generic one. */
export function cardSchema(cards: Dict, collection: string): Dict {
  const c = cards?.[collection];
  return c && typeof c === 'object' && c.schema ? c.schema : GENERIC_CARD;
}

export function cardData(entry: Dict, role = 'player', me = ''): Dict {
  const e = clone(entry ?? {});
  delete e.__pack;
  return { entry: e, role, me, facts: facts(e) };
}
