// How the table's views, scenes and DM states come (protocol 4; the host's
// side is hexmap/net/wire.gd). A view schema — a sheet's (some 290 KB), the
// status view's, an entry's card, the DM's party view — comes once per
// connection: where it was, a record has `schema_ref`, "<plugin>/<kind>@<hash
// of its contents>", and the message that first needs it has it in `schemas`.
// A view, a scene and a DM state each come whole once (with `n`), then as a
// patch on the one before ({patch, base, n}). The Reader keeps the schemas and
// the last of each, and makes every message whole again, in the shape the
// screens read it (a view's `view`, a DM state's `state`, a scene's fields,
// each schema in its place) — or says to ask for it whole (need {kind}).
//
// A patch node:
//   {v: value}                       the value, whole
//   {d: {key: node}, x: [keys]}      a dictionary: those keys changed, those gone, the rest kept
//   {k, i: {index: node}, a, s}      an array: its first k items (those under i changed),
//                                    then the items of a, then its last s items
import type { Msg } from './net';

type Dict = Record<string, any>;

export type Node = {
  v?: unknown;
  d?: Record<string, Node>;
  x?: string[];
  k?: number;
  i?: Record<string, Node>;
  a?: unknown[];
  s?: number;
};

/** The messages that come whole once, then as what changed. */
export const KINDS = ['view', 'dm', 'scene'];
/** The keys of a message that are the wire's own, not a scene's fields. */
const OWN = ['t', 'n', 'base', 'patch', 'schemas'];

const isDict = (v: unknown): v is Dict => !!v && typeof v === 'object' && !Array.isArray(v);
/** A deep copy of JSON data (as the screens copy it: a phone a few years old has no structuredClone). */
const copy = <T>(v: T): T => JSON.parse(JSON.stringify(v)) as T;

/** The records of a body that hold a schema (`schema`, or `schema_ref` as it comes). */
export function schemaRecords(kind: string, body: Dict): Dict[] {
  const out: Dict[] = [];
  const cards = (c: unknown) => {
    if (isDict(c)) for (const r of Object.values(c)) if (isDict(r)) out.push(r);
  };
  if (kind === 'view') {
    if (isDict(body.actors)) for (const a of Object.values(body.actors)) if (isDict(a) && Array.isArray(a.sheets)) for (const sh of a.sheets) if (isDict(sh)) out.push(sh);
    if (Array.isArray(body.status)) for (const st of body.status) if (isDict(st)) out.push(st);
    cards(body.cards);
  } else if (kind === 'dm') {
    if (Array.isArray(body.party_views)) for (const pv of body.party_views) if (isDict(pv)) out.push(pv);
    cards(body.cards);
  }
  return out;
}

/** A message's body: a view's projection, a DM state, a scene's fields. */
export function bodyOf(m: Msg): Dict {
  if (m.t === 'view') return isDict(m.view) ? m.view : {};
  if (m.t === 'dm') return isDict(m.state) ? m.state : {};
  const out: Dict = { ...m };
  for (const k of OWN) delete out[k];
  return out;
}

/** A body as its whole message reads. */
export function whole(kind: string, body: Dict): Msg {
  if (kind === 'view') return { t: 'view', view: body };
  if (kind === 'dm') return { t: 'dm', state: body };
  return { ...body, t: kind };
}

class Unfit extends Error {}

const count = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v) && v >= 0;

/** `node` applied to `old`, which it may change in place: the new value.
 *  Throws when the node doesn't fit what `old` is (a patch on another base). */
export function apply(old: unknown, node: Node): unknown {
  if (!isDict(node)) throw new Unfit('not a patch');
  if ('v' in node) return node.v;
  if ('k' in node) {
    const s = node.s ?? 0;
    if (!Array.isArray(old) || !count(node.k) || !count(s) || node.k + s > old.length) throw new Unfit('an array patch that does not fit');
    const out = old.slice(0, node.k);
    for (const [key, sub] of Object.entries(node.i ?? {})) {
      const idx = Number(key);
      if (!count(idx) || idx >= node.k) throw new Unfit('an item that is not there');
      out[idx] = apply(out[idx], sub);
    }
    if (Array.isArray(node.a)) out.push(...node.a);
    if (s > 0) out.push(...old.slice(old.length - s));
    return out;
  }
  if (!('d' in node) && !('x' in node)) return old; // ({}: no change)
  if (!isDict(old)) throw new Unfit('a dictionary patch on something else');
  for (const [key, sub] of Object.entries(node.d ?? {})) old[key] = apply(old[key], sub);
  for (const key of node.x ?? []) delete old[String(key)];
  return old;
}

/** What a message read to: the whole of it; `same` when nothing changed (nothing
 *  to draw again); `need` the first time one can't be read (ask for that kind
 *  whole); `added` when it brought schemas. */
export type Read = { msg?: Msg; same?: boolean; need?: boolean; added?: boolean };

export class Reader {
  /** id → schema: what this page holds. */
  schemas = new Map<string, Dict>();
  private bodies = new Map<string, Dict>();
  private n = new Map<string, number>();
  private asked = new Set<string>();

  read(m: Msg): Read {
    const kind = m.t;
    let added = false;
    if (isDict(m.schemas))
      for (const [id, s] of Object.entries(m.schemas))
        if (isDict(s)) {
          this.schemas.set(id, s);
          added = true;
        }
    let body: Dict;
    if ('patch' in m) {
      const was = this.bodies.get(kind);
      if (!was || m.base !== this.n.get(kind)) return { ...this.stale(kind), added };
      if (isDict(m.patch) && Object.keys(m.patch).length === 0) {
        this.n.set(kind, Number(m.n ?? 0));
        return { same: true, added };
      }
      try {
        const got = apply(was, m.patch as Node);
        if (!isDict(got)) throw new Unfit('not a body');
        body = got;
      } catch {
        return { ...this.stale(kind), added };
      }
    } else {
      // (a copy: the patches that follow change it in place)
      body = copy(bodyOf(m));
    }
    this.bodies.set(kind, body);
    this.n.set(kind, Number(m.n ?? 0));
    // the screens' own copy, each schema in its place (shared: nothing changes a schema)
    const out = whole(kind, copy(body));
    for (const r of schemaRecords(kind, bodyOf(out))) {
      if (!('schema_ref' in r)) continue;
      const s = this.schemas.get(String(r.schema_ref));
      if (!s) return { ...this.stale(kind), added };
      r.schema = s;
      delete r.schema_ref;
    }
    this.asked.delete(kind);
    return { msg: out, added };
  }

  /** The schema ids the last view and DM state use. */
  inUse(): Set<string> {
    const out = new Set<string>();
    for (const [kind, body] of this.bodies) for (const r of schemaRecords(kind, body)) if (typeof r.schema_ref === 'string') out.add(r.schema_ref);
    return out;
  }

  /** What to say it holds on joining (a reconnect): what the last views used,
   *  once some have come here (a page just loaded has only what it kept). */
  have(): string[] {
    if (this.bodies.has('view') || this.bodies.has('dm')) {
      const used = this.inUse();
      for (const id of [...this.schemas.keys()]) if (!used.has(id)) this.schemas.delete(id);
    }
    return [...this.schemas.keys()];
  }

  /** The schemas in use, to keep across a reload (sessionStorage); {} for none. */
  keep(): Record<string, Dict> {
    const out: Record<string, Dict> = {};
    for (const id of this.inUse()) {
      const s = this.schemas.get(id);
      if (s) out[id] = s;
    }
    return out;
  }

  /** Schemas kept from before (a reload), as keep() made them. */
  restore(kept: unknown): void {
    if (!isDict(kept)) return;
    for (const [id, s] of Object.entries(kept)) if (isDict(s) && !this.schemas.has(id)) this.schemas.set(id, s);
  }

  private stale(kind: string): Read {
    this.bodies.delete(kind);
    this.n.delete(kind);
    if (this.asked.has(kind)) return {};
    this.asked.add(kind);
    return { need: true };
  }
}
