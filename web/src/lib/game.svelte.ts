// The table as this screen knows it: what the host sent (the view of the
// rules, the scene snapshot, the maps and packs, the DM's campaign state)
// and the verbs to send it things. One per page.
//
// A page connects first (hello: the welcome names the players, so a
// returning one can tap their name) and joins after; a reconnect says
// hello and joins again by itself.
import { Connection, PROTOCOL, type Msg } from './net';
import { Waiting } from './waiting';
import { TYPING_SHOWN_MS } from './typing';
import { KINDS, Reader } from './wire';

export type Dict = Record<string, any>;

/** What the table said to an intent sent with a `req`: done, or refused and why. */
export type Answer = { ok: boolean; why?: string };

export interface Config {
  ws_port: number;
  name: string;
  protocol?: number;
}

export const game = $state({
  status: 'starting' as 'starting' | 'connecting' | 'open' | 'closed',
  error: '',
  config: null as Config | null,
  role: 'player' as 'player' | 'dm',
  /** The table's name (the campaign's). */
  table: '',
  /** This player's id once joined ("" for the DM). */
  me: '',
  joined: false,
  joining: false,
  /** The encounter's players (from the welcome and every scene). */
  players: [] as Dict[],
  online: [] as string[],
  view: {} as Dict,
  /** When the view came (performance.now()): a card's seconds `left` count from it. */
  viewAt: 0,
  scene: {} as Dict,
  scenes: [] as Dict[],
  /** The DM's: the players whose seat a device has taken (the DM may free one). */
  seats: [] as string[],
  // the DM seeing as a player: that player's snapshot of the scene, and who
  preview: null as Dict | null,
  previewAs: '',
  // …and why each creature they don't see isn't there (token id → hidden | dark | walls | none)
  previewWhy: {} as Record<string, string>,
  /** …and the marks on the map as that player is sent them (by id): the DM's
   *  rulers and previews over what they can't see left out, a creature they
   *  don't know unnamed. null when not seeing as anyone. */
  previewMarks: null as Record<string, Dict> | null,
  clock: {} as Dict,
  maps: {} as Record<string, Dict>,
  /** Each map's key, sent with it: what its own files (a backdrop) are fetched by. */
  mapKeys: {} as Record<string, string>,
  packs: {} as Record<string, Dict>,
  dm: {} as Dict,
  notices: [] as { id: number; text: string; kind: 'info' | 'error' }[],
  /** Who is writing in the chat now (a player's id, or "gm"): the id of their
   *  newest line when they began, so the line they send ends it. */
  typing: {} as Record<string, { after: string }>,
  /** The table's shared marks this screen may see (rulers, templates,
   *  previews, pings), by id: the Table's word, its own included. */
  marks: {} as Record<string, Dict>,
  /** When each mark was first heard of here (performance.now(): a ping fades from then). */
  marksBorn: {} as Record<string, number>,
});

let conn: Connection | null = null;
let noticeSeq = 0;
const compWaiting = new Map<string, (reply: Dict) => void>();
let compSeq = 0;
const mapsAsked = new Set<string>();
const uploadsWaiting = new Map<string, (r: { ref?: string; why?: string }) => void>();
let uploadSeq = 0;
// the intents whose screens wait to hear they were done (a form clears and says
// so): ten seconds without an answer is not done
const intentsWaiting = new Waiting<Answer>('i', 10000, () => {
  notice('The table did not answer: check whether it was done before you try again', 'error');
  return { ok: false, why: 'no answer' };
});
let joinMsg: Msg | null = null;
let byName = '';
const typingTimers = new Map<string, ReturnType<typeof setTimeout>>();
// the views, scenes and DM states as they come — whole, or what changed — and
// the view schemas this page holds (lib/wire.ts); those in use are kept for a
// reload (a phone that dropped the page while in another app) in this tab
const wire = new Reader();
const KEPT_SCHEMAS = 'hexmap.schemas';
try {
  wire.restore(JSON.parse(sessionStorage.getItem(KEPT_SCHEMAS) ?? 'null'));
} catch {
  /* none kept, or private mode */
}

function keepSchemas(): void {
  try {
    const text = JSON.stringify(wire.keep());
    // (a few hundred KB; past this a reload asks for them again)
    if (text.length < 3_000_000) sessionStorage.setItem(KEPT_SCHEMAS, text);
  } catch {
    /* full, or private mode */
  }
}

/** The join, saying which schemas this page holds: the table sends none of them again. */
function joining(): Msg[] {
  return joinMsg ? [{ ...joinMsg, have: wire.have() }] : [];
}

function stopTyping(from: string): void {
  clearTimeout(typingTimers.get(from));
  typingTimers.delete(from);
  delete game.typing[from];
}

/** The id of the newest line of chat from `from` in this viewer's log ('' for none). */
function newestLineOf(from: string): string {
  const log = (game.view.log as Dict[]) ?? [];
  for (let i = log.length - 1; i >= 0; i--) {
    const e = log[i];
    if (e && e.kind === 'chat' && String(e.from ?? '') === from) return String(e.id ?? '');
  }
  return '';
}

export function notice(text: string, kind: 'info' | 'error' = 'info'): void {
  const id = ++noticeSeq;
  game.notices.push({ id, text, kind });
  setTimeout(
    () => {
      const i = game.notices.findIndex((n) => n.id === id);
      if (i >= 0) game.notices.splice(i, 1);
    },
    kind === 'error' ? 6000 : 3500,
  );
}

async function loadConfig(): Promise<Config> {
  const r = await fetch('/config.json', { cache: 'no-store' });
  if (!r.ok) throw new Error('the table did not answer');
  return (await r.json()) as Config;
}

function hello(): Msg {
  return { t: 'hello', version: PROTOCOL, name: navigator.userAgent.slice(0, 60), web: true };
}

/** Reach the table: fetch where its socket is, connect, say hello. */
export async function connect(role: 'player' | 'dm'): Promise<boolean> {
  game.role = role;
  try {
    game.config = await loadConfig();
    game.table = game.config.name ?? '';
  } catch {
    game.error = 'Could not reach the table. Is the DM’s Hexmap still running?';
    game.status = 'closed';
    return false;
  }
  const url = `ws://${location.hostname}:${game.config.ws_port}`;
  conn?.close();
  conn = new Connection(url);
  // hello, and the join once there is one (none after leaving, or a join turned down)
  conn.greeting = () => [hello(), ...joining()];
  conn.onstatus = (s) => {
    game.status = s;
    // a player who was in stays on their screen while the page reconnects
    // and joins again by itself (a phone that went to another app, a wifi
    // blip): only a join the table turns down goes back to the join screen
    if (s === 'closed' && !joinMsg) game.joined = false;
    if (s === 'open' && joinMsg) game.joining = true;
  };
  conn.onmessage = handle;
  conn.connect();
  return true;
}

/** This browser's own secret: the seat it takes at a table is its, and only it
 *  joins as that player again (until the DM frees the seat). Kept for good;
 *  made once. */
export function deviceKey(): string {
  try {
    const kept = localStorage.getItem('hexmap.device');
    if (kept && /^[0-9a-f]{32}$/.test(kept)) return kept;
  } catch {
    /* private mode: this page's own, below */
  }
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  const made = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
  try {
    localStorage.setItem('hexmap.device', made);
  } catch {
    /* private mode */
  }
  return made;
}

let pageDevice = '';

/** Join: a player by name (a new name is a new player) or by id; the DM with the token.
 * By id with a name too, a table that no longer has that id is joined by the name.
 * A player's join says which device it is (deviceKey): their seat is its. */
export function join(opts: { name?: string; player?: string; token?: string }): void {
  pageDevice ||= deviceKey();
  joinMsg = game.role === 'dm' ? { t: 'join', role: 'dm', token: opts.token ?? '' } : { t: 'join', role: 'player', player: opts.player ?? '', name: opts.name ?? '', device: pageDevice };
  byName = opts.player && opts.name ? opts.name : '';
  game.joining = true;
  game.error = '';
  for (const m of joining()) conn?.send(m);
}

export function leave(): void {
  joinMsg = null;
  game.joined = false;
  game.me = '';
  keepSession('');
  try {
    localStorage.removeItem('hexmap.name');
  } catch {
    /* private mode */
  }
  conn?.close();
  conn = null;
  if (game.role === 'player') void connect('player');
}

function handle(m: Msg): void {
  // a view, a scene or the DM's state: whole once, then what changed, each
  // schema once (lib/wire.ts) — made whole again here, as the screens read it
  if (KINDS.includes(m.t)) {
    const got = wire.read(m);
    if (got.need) conn?.send({ t: 'need', kind: m.t });
    if (got.added) keepSchemas();
    if (!got.msg) return;
    m = got.msg;
  }
  switch (m.t) {
    case 'welcome': {
      const doc = (m.encounter ?? {}) as Dict;
      game.players = (doc.players as Dict[]) ?? [];
      if (!game.table) game.table = String(doc.name ?? '');
      break;
    }
    case 'joined':
      game.me = String(m.player ?? '');
      game.joined = true;
      game.joining = false;
      game.error = '';
      conn?.send({ t: 'need', kind: 'packs' });
      if (game.role === 'player') {
        remember(String(m.name ?? ''));
        keepSession(game.me);
      }
      break;
    case 'view':
      game.view = (m.view as Dict) ?? {};
      game.viewAt = performance.now();
      // who was typing and has sent it: no longer typing
      for (const [from, t] of Object.entries(game.typing)) if (newestLineOf(from) !== t.after) stopTyping(from);
      break;
    case 'typing': {
      // someone writing in the chat, as the table relays it (never kept): shown
      // until they send it, or for a few seconds after they last said so
      const from = String(m.from ?? '');
      if (!from || from === (game.role === 'dm' ? 'gm' : game.me)) break;
      game.typing[from] = { after: game.typing[from]?.after ?? newestLineOf(from) };
      clearTimeout(typingTimers.get(from));
      typingTimers.set(from, setTimeout(() => stopTyping(from), TYPING_SHOWN_MS));
      break;
    }
    case 'scene':
      game.scene = (m.scene as Dict) ?? {};
      game.players = (m.players as Dict[]) ?? game.players;
      game.online = (m.online as string[]) ?? [];
      game.clock = (m.clock as Dict) ?? {};
      if (m.scenes) game.scenes = m.scenes as Dict[];
      // (the DM's: whose seats a device has taken)
      if (m.seats) game.seats = (m.seats as string[]).map(String);
      game.preview = (m.preview as Dict) ?? null;
      game.previewAs = String(m.preview_as ?? '');
      game.previewWhy = (m.preview_why as Record<string, string>) ?? {};
      game.previewMarks = m.preview ? marksById(m.preview_marks) : null;
      wantMap(String(game.scene.map ?? ''));
      break;
    // the DM seeing as a player: their marks again, a mark put, changed or gone
    case 'seen_marks':
      if (game.previewAs && String(m.as ?? '') === game.previewAs) game.previewMarks = marksById(m.marks);
      break;
    case 'dm':
      game.dm = (m.state as Dict) ?? {};
      break;
    // the table's shared marks: all of them on joining, then one at a time
    case 'marks': {
      const all = marksById(m.marks);
      game.marks = all;
      for (const id of Object.keys(all)) game.marksBorn[id] ??= performance.now();
      break;
    }
    case 'mark': {
      const mk = m.mark as Dict | undefined;
      if (!mk || typeof mk !== 'object' || !mk.id) break;
      game.marks[String(mk.id)] = mk;
      game.marksBorn[String(mk.id)] ??= performance.now();
      break;
    }
    case 'unmark':
      for (const id of (m.ids as string[]) ?? []) {
        delete game.marks[String(id)];
        delete game.marksBorn[String(id)];
      }
      break;
    case 'map': {
      // (sent again where what this screen may see of it changed: a door found)
      const doc = (m.doc as Dict) ?? {};
      game.maps[String(m.id)] = doc;
      game.mapKeys[String(m.id)] = String(m.key ?? '');
      // a map shown later (a fight's) may draw with packs this screen has not had yet
      if (Object.keys(doc.packs ?? {}).some((p) => !game.packs[p])) conn?.send({ t: 'need', kind: 'packs' });
      break;
    }
    case 'packs':
      for (const p of (m.packs as Dict[]) ?? []) game.packs[String(p.id)] = (p.manifest as Dict) ?? {};
      break;
    case 'comp': {
      const cb = compWaiting.get(String(m.req ?? ''));
      compWaiting.delete(String(m.req ?? ''));
      cb?.(m as Dict);
      break;
    }
    case 'done':
      intentsWaiting.answer(String(m.req ?? ''), { ok: true });
      break;
    case 'refused':
      notice(String(m.why ?? 'Refused'), 'error');
      intentsWaiting.answer(String(m.req ?? ''), { ok: false, why: String(m.why ?? 'Refused') });
      break;
    case 'uploaded':
    case 'upload_failed': {
      const done = uploadsWaiting.get(String(m.req ?? ''));
      uploadsWaiting.delete(String(m.req ?? ''));
      done?.(m.t === 'uploaded' ? { ref: String(m.ref ?? '') } : { why: String(m.why ?? 'The table did not keep it') });
      break;
    }
    case 'error':
      if ((game.joining || !game.joined) && byName) {
        // this tab's player is not at this table (another campaign now): by the name instead
        const name = byName;
        keepSession('');
        join({ name });
        break;
      }
      if (game.joining || !game.joined) {
        // a join the table turned down: back to the join screen, saying why
        game.joining = false;
        game.joined = false;
        // (and a reconnect says hello alone: the greeting has no join now)
        joinMsg = null;
        keepSession('');
      }
      game.error = String(m.why ?? 'The table refused');
      notice(game.error, 'error');
      break;
  }
}

/** Send a picture made ready (lib/pictures.ts: base64) to the table: a
 * token's (`actor`, or `clear` to take it off) or a journal's. The ref it
 * is kept as, or why not. */
export function uploadPicture(kind: 'token' | 'picture', data: string, extra: Dict = {}): Promise<{ ref?: string; why?: string }> {
  const req = `u${++uploadSeq}`;
  return new Promise((resolve) => {
    uploadsWaiting.set(req, resolve);
    if (!send({ t: 'upload', req, kind, data, ...extra })) {
      uploadsWaiting.delete(req);
      resolve({ why: 'Not connected to the table' });
      return;
    }
    setTimeout(() => {
      if (uploadsWaiting.delete(req)) resolve({ why: 'The table did not answer: try again' });
    }, 45000);
  });
}

/** A list of marks by id (what a screen is told of them). */
export function marksById(list: unknown): Record<string, Dict> {
  const out: Record<string, Dict> = {};
  for (const mk of (Array.isArray(list) ? list : []) as Dict[]) if (mk && typeof mk === 'object' && mk.id) out[String(mk.id)] = mk;
  return out;
}

/** For tests: the socket drops as a phone's does (in another app, a Wi-Fi blip); the page reconnects by itself. */
export function dropConnection(): void {
  conn?.ws?.close();
}

/** A map's own file (a backdrop), at the address its key opens (the table
 *  serves it to no one who hasn't been sent the map). */
export function mapFileUrl(mid: string, file: string): string {
  return `/mapfile/${encodeURIComponent(mid)}/${encodeURIComponent(game.mapKeys[mid] ?? '')}/${encodeURIComponent(file)}`;
}

export function wantMap(id: string): void {
  if (!id || game.maps[id] || mapsAsked.has(id)) return;
  mapsAsked.add(id);
  conn?.send({ t: 'need', kind: 'map', id });
}

export function send(m: Msg): boolean {
  return conn?.send(m) ?? false;
}

/** A rules intent: an action, an answer, a note, chat, a DM operation. */
export function intent(payload: Dict): void {
  if (!send({ t: 'intent', intent: payload })) notice('Not connected to the table', 'error');
}

/** A rules intent whose answer this page waits for (a form's): done, or refused and why. */
export function submit(payload: Dict): Promise<Answer> {
  const { req, answer } = intentsWaiting.ask();
  if (!send({ t: 'intent', intent: payload, req })) {
    notice('Not connected to the table', 'error');
    intentsWaiting.answer(req, { ok: false, why: 'Not connected to the table' });
  }
  return answer;
}

/** A scene event asked for (a move). */
export function request(ev: Dict): void {
  if (!send({ t: 'request', ev })) notice('Not connected to the table', 'error');
}

export function dmOp(op: string, fields: Dict = {}): void {
  intent({ kind: 'dm', op, ...fields });
}

export function chat(text: string, to: string[] | 'all', priv = false): void {
  intent({ kind: 'chat', text, to, private: priv });
}

/** A compendium page or entry, as this viewer may see it. */
export function comp(collection: string, req: Dict): Promise<Dict> {
  const id = `c${++compSeq}`;
  return new Promise((resolve) => {
    compWaiting.set(id, resolve);
    const msg: Msg = { t: 'need', kind: 'comp', req: id, collection };
    if (req.id) msg.id = req.id;
    else msg.query = req.query ?? {};
    if (!send(msg)) {
      compWaiting.delete(id);
      resolve({ collection, error: 'not connected' });
    }
  });
}

export function playerName(id: string): string {
  if (id === 'gm') return 'the DM';
  return String(game.players.find((p) => String(p.id) === id)?.name ?? id);
}

/** The colour each player's tokens are ringed in. */
export function playerColors(): Record<string, string> {
  const out: Record<string, string> = {};
  for (const p of game.players) out[String(p.id)] = String(p.color ?? '#ffffff');
  return out;
}

/** The characters this player owns, as the view has them. */
export function myActors(): Dict[] {
  const actors: Dict = game.view.actors ?? {};
  return Object.values(actors).filter((a: Dict) => a.mine) as Dict[];
}

/** What the DM has shown this viewer, oldest first, once per thing shown (the journal, then this session's log). */
export function handouts(): Dict[] {
  const byKey = new Map<string, Dict>();
  const all: Dict[] = [...((game.view.journal as Dict[]) ?? []), ...((game.view.log as Dict[]) ?? []).filter((h) => h?.kind === 'handout')];
  for (const h of all) {
    if (!h || typeof h !== 'object') continue;
    const key = String(h.ref || h.id || '');
    byKey.delete(key);
    byKey.set(key, h);
  }
  return [...byKey.values()];
}

/** The chat, the rolls and what the rules said (an item given, an action taken) this viewer may read: the campaign's earlier sessions, then this one's log.
 *  (`src`: another's, as the DM sees as a player: {log, chat_history}.) */
export function chatLog(src: Dict = game.view): Dict[] {
  const log = (src.log as Dict[]) ?? [];
  // what the live log holds goes where the log has it (a session ended but
  // still open is in both; a playtest's list put the evening above its first hour)
  const live = new Set(log.map((e) => String(e?.id ?? '')).filter((id) => id !== ''));
  const before = ((src.chat_history as Dict[]) ?? []).filter((h) => !live.has(String(h?.id ?? '')));
  const seen = new Set<string>();
  const out: Dict[] = [];
  for (const e of [...before, ...log]) {
    if (!e || typeof e !== 'object') continue;
    if (e.kind !== 'chat' && e.kind !== 'roll' && !(e.kind === 'note' && e.text)) continue;
    const id = String(e.id ?? '');
    if (id && seen.has(id)) continue;
    if (id) seen.add(id);
    out.push(e);
  }
  return out;
}

/** The player this browser tab joined as, so a reload (a phone that
 * dropped the page while in another app) comes straight back in. */
function keepSession(player: string): void {
  try {
    if (player) sessionStorage.setItem('hexmap.player', player);
    else sessionStorage.removeItem('hexmap.player');
  } catch {
    /* private mode */
  }
}

export function sessionPlayer(): string {
  try {
    return sessionStorage.getItem('hexmap.player') ?? '';
  } catch {
    return '';
  }
}

/** A player remembers the name they joined with, for next time. */
function remember(name: string): void {
  try {
    if (name) localStorage.setItem('hexmap.name', name);
  } catch {
    /* private mode */
  }
}

export function rememberedName(): string {
  try {
    return localStorage.getItem('hexmap.name') ?? '';
  } catch {
    return '';
  }
}
