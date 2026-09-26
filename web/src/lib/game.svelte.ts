// The table as this screen knows it: what the host sent (the view of the
// rules, the scene snapshot, the maps and packs, the DM's campaign state)
// and the verbs to send it things. One per page.
//
// A page connects first (hello: the welcome names the players, so a
// returning one can tap their name) and joins after; a reconnect says
// hello and joins again by itself.
import { Connection, PROTOCOL, type Msg } from './net';

export type Dict = Record<string, any>;

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
  scene: {} as Dict,
  scenes: [] as Dict[],
  // the DM seeing as a player: that player's snapshot of the scene, and who
  preview: null as Dict | null,
  previewAs: '',
  // …and why each creature they don't see isn't there (token id → hidden | dark | walls | none)
  previewWhy: {} as Record<string, string>,
  clock: {} as Dict,
  maps: {} as Record<string, Dict>,
  packs: {} as Record<string, Dict>,
  dm: {} as Dict,
  notices: [] as { id: number; text: string; kind: 'info' | 'error' }[],
});

let conn: Connection | null = null;
let noticeSeq = 0;
const compWaiting = new Map<string, (reply: Dict) => void>();
let compSeq = 0;
const mapsAsked = new Set<string>();
const uploadsWaiting = new Map<string, (r: { ref?: string; why?: string }) => void>();
let uploadSeq = 0;
let joinMsg: Msg | null = null;
let byName = '';

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
  conn.greeting = [hello()];
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

/** Join: a player by name (a new name is a new player) or by id; the DM with the token.
 * By id with a name too, a table that no longer has that id is joined by the name. */
export function join(opts: { name?: string; player?: string; token?: string }): void {
  joinMsg = game.role === 'dm' ? { t: 'join', role: 'dm', token: opts.token ?? '' } : { t: 'join', role: 'player', player: opts.player ?? '', name: opts.name ?? '' };
  byName = opts.player && opts.name ? opts.name : '';
  game.joining = true;
  game.error = '';
  if (conn) {
    conn.greeting = [hello(), joinMsg];
    conn.send(joinMsg);
  }
}

export function leave(): void {
  joinMsg = null;
  if (conn) conn.greeting = [hello()];
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
      break;
    case 'scene':
      game.scene = (m.scene as Dict) ?? {};
      game.players = (m.players as Dict[]) ?? game.players;
      game.online = (m.online as string[]) ?? [];
      game.clock = (m.clock as Dict) ?? {};
      if (m.scenes) game.scenes = m.scenes as Dict[];
      game.preview = (m.preview as Dict) ?? null;
      game.previewAs = String(m.preview_as ?? '');
      game.previewWhy = (m.preview_why as Record<string, string>) ?? {};
      wantMap(String(game.scene.map ?? ''));
      break;
    case 'dm':
      game.dm = (m.state as Dict) ?? {};
      break;
    case 'map': {
      const doc = (m.doc as Dict) ?? {};
      game.maps[String(m.id)] = doc;
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
    case 'refused':
      notice(String(m.why ?? 'Refused'), 'error');
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
        joinMsg = null;
        keepSession('');
        if (conn) conn.greeting = [hello()];
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

/** For tests: the socket drops as a phone's does (in another app, a Wi-Fi blip); the page reconnects by itself. */
export function dropConnection(): void {
  conn?.ws?.close();
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

/** The chat, the rolls and what the rules said (an item given, an action taken) this viewer may read: the campaign's earlier sessions, then this one's log. */
export function chatLog(): Dict[] {
  const log = (game.view.log as Dict[]) ?? [];
  // what the live log holds goes where the log has it (a session ended but
  // still open is in both; a playtest's list put the evening above its first hour)
  const live = new Set(log.map((e) => String(e?.id ?? '')).filter((id) => id !== ''));
  const before = ((game.view.chat_history as Dict[]) ?? []).filter((h) => !live.has(String(h?.id ?? '')));
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
