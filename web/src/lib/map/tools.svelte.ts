// The map's table tools on a screen — a ruler, a template, a spell's preview,
// a ping: this screen's own marks, made here and sent to the Table, which
// shares them with everyone allowed to see them (the host's Marks). Made by
// taps on a phone (tap to start, tap for each point, Done) or by drags with
// a mouse; drawn from here while they are being made, and as the Table sends
// them back (a ruler's walk round the walls is the Table's to say).
//
// The messages ({t: "mark", op: set | remove | clear}) and their limits are
// the host's: a held mark is sent at most every SEND_MS; a screen has eight
// at most (one more takes the place of its oldest unpinned).
import { game, notice, send, submit, type Dict } from '../game.svelte';
import { Grid, type Vec } from '../grid';
import { feetToUnits, gridless, snapPoint } from './measure';
import { castCell, caught, inShape, knob, placeAt, shapeWords, type Shape, type ShapeType } from './template';
import { tokenPos } from './render';
import { withNoTarget, withTarget } from './pick';

export type Mode = '' | 'ruler' | 'template' | 'ping' | 'preview';

/** What the tools need of the map they are used on: its grid, the scene and
 *  map shown, the tokens this screen shows, and its pixels per hex unit. */
export interface Where {
  grid: Grid;
  scene: Dict;
  map: Dict | null;
  tokens: Dict[];
  scale: number;
}

/** Where the tools work on a page's scene and map (null with no map shown). */
export function whereOf(scene: Dict, map: Dict | null, scale = 40): Where | null {
  if (!map || !scene?.id) return null;
  return { grid: new Grid(map.grid ?? {}), scene, map, tokens: (scene.tokens as Dict[]) ?? [], scale };
}

/** A held mark is sent at most this often (the Table relays at most every 66 ms). */
export const SEND_MS = 100;
/** A ruler's points, both ends and its waypoints (the host's Marks.MAX_POINTS). */
export const MAX_POINTS = 16;
/** A turn button's step, in degrees. */
export const TURN_STEP = 15;

export const tools = $state({
  mode: '' as Mode,
  /** the mark being made or moved, drawn from here and sent as it changes */
  draft: null as Dict | null,
  /** a ruler made a tap at a time (it stays open for more points until Done) */
  tapping: false,
  /** the template's form: its shape, size (and a line's width) in feet */
  shape: 'circle' as ShapeType,
  feet: 20,
  widthFeet: 5,
  /** a spell's preview: its shape and words, the cast it can turn into, its caster */
  preview: null as { shape: Shape; from: 'self' | 'point'; label: string; cast: Dict | null; actor: string } | null,
  /** the DM's marks seen by the DMs alone */
  private: false,
  /** the list of marks open */
  list: false,
});

// a ruler's fixed points and where its end is
let fixed: Vec[] = [];
let cursor: Vec | null = null;
let firstPress = false;
let pressed = false;
// a template being moved or turned, and from where it was grabbed
let grab: '' | 'move' | 'turn' = '';
let grabOffset: Vec = { x: 0, y: 0 };
// what is waiting to be sent, and when the last went
let sentAt = 0;
let timer: ReturnType<typeof setTimeout> | null = null;
let queued: Dict | null = null;
let seq = 0;

/** Whose this screen's marks are: "gm" for the DM's screen, else the player's id. */
export function myOwner(): string {
  return game.role === 'dm' ? 'gm' : game.me;
}

/** A new mark's id (the host takes 4 to 40 letters, digits, - and _). */
export function newId(kind: string): string {
  seq += 1;
  const rand = Math.random().toString(36).slice(2, 8);
  return `${kind.slice(0, 2)}-${Date.now().toString(36)}-${seq}-${rand}`;
}

/** The fields of a mark the Table takes from a screen. */
function wire(m: Dict): Dict {
  const out: Dict = {};
  for (const k of ['id', 'kind', 'scene', 'points', 'shape', 'direction', 'token', 'label', 'pinned', 'live', 'private', 'actor']) if (m[k] !== undefined && m[k] !== null) out[k] = m[k];
  if (game.role === 'dm' && tools.private) out.private = true;
  return out;
}

/** Send a mark: at once when it is let go (`now`), else at most every SEND_MS (the newest waits). */
export function sendMark(m: Dict, now = false): void {
  const msg = wire($state.snapshot(m) as Dict);
  if (timer) {
    clearTimeout(timer);
    timer = null;
  }
  const since = performance.now() - sentAt;
  if (now || since >= SEND_MS) {
    queued = null;
    sentAt = performance.now();
    send({ t: 'mark', op: 'set', mark: msg });
    return;
  }
  queued = msg;
  timer = setTimeout(() => {
    timer = null;
    if (!queued) return;
    sentAt = performance.now();
    send({ t: 'mark', op: 'set', mark: queued });
    queued = null;
  }, SEND_MS - since);
}

function forget(): void {
  if (timer) clearTimeout(timer);
  timer = null;
  queued = null;
}

function pts(list: Vec[]): number[][] {
  return list.map((p) => [Math.round(p.x * 1000) / 1000, Math.round(p.y * 1000) / 1000]);
}

// ------------------------------------------------------------- modes --

export function startRuler(): void {
  stop();
  tools.mode = 'ruler';
}

export function startTemplate(): void {
  stop();
  tools.mode = 'template';
}

export function startPing(): void {
  stop();
  tools.mode = 'ping';
}

/** Leave the tool: what was made stays as a mark (it lingers and goes, or stays pinned). */
export function stop(): void {
  if (tools.draft && tools.draft.live) sendMark({ ...tools.draft, live: false }, true);
  tools.mode = '';
  tools.draft = null;
  tools.tapping = false;
  tools.preview = null;
  fixed = [];
  cursor = null;
  pressed = false;
  grab = '';
}

/** Take the mark being made off the map, and leave the tool. */
export function cancel(): void {
  const id = String(tools.draft?.id ?? '');
  forget();
  if (id) send({ t: 'mark', op: 'remove', id });
  tools.draft = null;
  stop();
}

/** A spell's or a power's Preview (a sheet's `{kind: "preview", area, actor,
 *  cast}`): its shape at once round or out from its caster, or — one put down
 *  within range — where the next tap puts it. */
export function startPreview(intent: Dict, w: Where | null): void {
  const area: Dict = intent.area && typeof intent.area === 'object' ? intent.area : {};
  const shape = previewShape(area);
  if (!shape) {
    notice('Nothing to show on the map', 'error');
    return;
  }
  stop();
  const cast = intent.cast && typeof intent.cast === 'object' ? (intent.cast as Dict) : null;
  const actor = String(intent.actor ?? '');
  const label = String(area.label ?? '');
  const from = String(area.from ?? 'point') === 'self' ? 'self' : 'point';
  tools.preview = { shape, from, label, cast, actor };
  tools.mode = 'preview';
  if (from === 'self' && w) {
    const tk = w.tokens.find((t) => actor !== '' && String(t.actor ?? '') === actor);
    if (!tk) {
      notice(`${actorName(actor)} isn’t on this map: the preview goes out from them`, 'error');
      stop();
      return;
    }
    const at = tokenPos(tk);
    tools.draft = { id: newId('preview'), kind: 'preview', scene: String(w.scene.id ?? ''), points: pts([at]), token: String(tk.id), shape, direction: facing(w, tk), label, actor };
    sendMark(tools.draft, true);
  }
}

/** A ruleset's preview as a mark's shape (hex units), or null. */
export function previewShape(area: Dict): Shape | null {
  const type = String(area.type ?? '');
  const size = Number(area.size);
  if (!['circle', 'cone', 'line', 'square'].includes(type) || !(size > 0)) return null;
  const s: Shape = { type: type as ShapeType, size, origin: area.origin === 'edge' ? 'edge' : 'center', include_self: area.include_self !== false };
  if (type === 'line') s.width = Number(area.width ?? 1) || 1;
  if (type === 'cone') s.angle = Number(area.angle ?? 53) || 53;
  return s;
}

function actorName(id: string): string {
  const a = (game.view.actors as Dict | undefined)?.[id] as Dict | undefined;
  return String(a?.name ?? 'The caster');
}

/** Which way a preview from a creature starts: toward the nearest creature
 *  not of the party that this screen shows, else east. */
function facing(w: Where, from: Dict): number {
  const o = tokenPos(from);
  let best: Dict | null = null;
  let bestD = Infinity;
  for (const t of w.tokens) {
    if (t === from || String(t.owner ?? '') !== '' || !t.actor) continue;
    const p = tokenPos(t);
    const d = Math.hypot(p.x - o.x, p.y - o.y);
    if (d > 0.01 && d < bestD) {
      best = t;
      bestD = d;
    }
  }
  if (!best) return 0;
  const p = tokenPos(best);
  return Math.round((Math.atan2(p.y - o.y, p.x - o.x) * 180) / Math.PI);
}

// -------------------------------------------------------------- ruler --

function rulerDraft(w: Where, live: boolean): Dict {
  // (a point on the one before it is no point: a double click's second)
  const list: Vec[] = [];
  for (const p of cursor && live ? [...fixed, cursor] : fixed) {
    const last = list[list.length - 1];
    if (!last || Math.hypot(last.x - p.x, last.y - p.y) > 1e-6) list.push(p);
  }
  if (list.length === 1) list.push(list[0]);
  const had = tools.draft;
  return { id: String(had?.id ?? newId('ruler')), kind: 'ruler', scene: String(w.scene.id ?? ''), points: pts(list.slice(0, MAX_POINTS)), live, pinned: !!had?.pinned };
}

function snapHere(w: Where, p: Vec): Vec {
  return snapPoint(w.grid, p, gridless(w.map), w.tokens, 10 / Math.max(w.scale, 1e-3));
}

/** A ruler's end, let go: it lingers and goes (unless pinned); the ruler stays ready for another. */
function letGoRuler(w: Where): void {
  if (!tools.draft) return;
  tools.draft = rulerDraft(w, false);
  sendMark(tools.draft, true);
  tools.draft = null;
  fixed = [];
  cursor = null;
  tools.tapping = false;
}

/** Done: the ruler (or the template, the preview) is left on the map, and the tool closes. */
export function done(w: Where | null): void {
  if (tools.mode === 'ruler' && tools.draft && w) letGoRuler(w);
  stop();
}

/** The last point taken back (the ruler goes when it has none left). */
export function undoPoint(w: Where): void {
  if (fixed.length > 1) {
    fixed.pop();
    tools.draft = rulerDraft(w, true);
    sendMark(tools.draft);
  } else cancelRuler();
}

function cancelRuler(): void {
  const id = String(tools.draft?.id ?? '');
  forget();
  if (id) send({ t: 'mark', op: 'remove', id });
  tools.draft = null;
  tools.tapping = false;
  fixed = [];
  cursor = null;
}

// ---------------------------------------------------------- templates --

/** The template the form says, in hex units on this map. */
export function formShape(grid: Grid): Shape {
  const size = Math.max(0.2, feetToUnits(Math.max(1, Number(tools.feet) || 5), grid));
  const s: Shape = { type: tools.shape, size, origin: 'center', include_self: true };
  if (tools.shape === 'line') s.width = Math.max(0.2, feetToUnits(Math.max(1, Number(tools.widthFeet) || 5), grid));
  if (tools.shape === 'cone') s.angle = 53;
  return s;
}

/** The form changed: the template on the map changes with it. */
export function reshape(w: Where): void {
  if (tools.mode !== 'template' || !tools.draft) return;
  const shape = formShape(w.grid);
  tools.draft = { ...tools.draft, shape, label: shapeWords(tools.shape, Number(tools.feet) || 5) };
  sendMark(tools.draft, true);
}

/** Turn the template being made (a cone, a line, a square) by `deg`. */
export function turn(deg: number): void {
  if (!tools.draft || !turnable()) return;
  const d = Number(tools.draft.direction ?? 0) + deg;
  tools.draft = { ...tools.draft, direction: ((((d + 180) % 360) + 360) % 360) - 180 };
  sendMark(tools.draft, true);
}

/** Whether the mark being made turns: not a circle, nor a square a preview puts at a point (its cast squares it to the grid). */
export function turnable(): boolean {
  const shape = tools.draft?.shape as Shape | undefined;
  if (!shape || shape.type === 'circle') return false;
  return !(tools.mode === 'preview' && tools.preview?.from === 'point');
}

/** Whether the mark being made moves: a template, a preview put at a point (not one from its caster). */
function movable(): boolean {
  return tools.mode === 'template' || (tools.mode === 'preview' && tools.preview?.from === 'point');
}

/** Pin or unpin the mark being made (a pinned mark stays till taken off). */
export function togglePin(): void {
  if (!tools.draft) return;
  tools.draft = { ...tools.draft, pinned: !tools.draft.pinned };
  sendMark(tools.draft, true);
}

/** Where the mark being made is. */
function placement(m: Dict, w: Where): { at: Vec; direction: number; fromSize: number } {
  const p = (m.points as number[][])?.[0] ?? [0, 0];
  const tk = m.token ? w.tokens.find((t) => String(t.id) === String(m.token)) : undefined;
  return { at: tk ? tokenPos(tk) : { x: Number(p[0]), y: Number(p[1]) }, direction: Number(m.direction ?? 0), fromSize: tk ? Number(tk.size ?? 1) : 0 };
}

/** The creatures this screen shows that a template or a preview would catch. */
export function catches(m: Dict, w: Where): Dict[] {
  const shape = m.shape as Shape | undefined;
  if (!shape) return [];
  return caught(w.grid, shape, placement(m, w), w.tokens, String(m.token ?? ''));
}

/** Cast here: the preview's spell (or power) cast where it is and as it faces,
 *  through the cast's own path and checks. Once taken, the preview goes. */
export async function castHere(w: Where): Promise<void> {
  const pv = tools.preview;
  const m = tools.draft;
  if (!pv?.cast || !m) return;
  const sceneId = String(w.scene.id ?? '');
  const pick = String(pv.cast.pick ?? '');
  let intent: Dict;
  if (pick === 'area') {
    const target = m.token ? { at: `token:${m.token}`, direction: Number(m.direction ?? 0) } : { at: castCell(w.grid, m.shape as Shape, placement(m, w).at), direction: 0 };
    intent = withTarget(pv.cast, target, sceneId);
  } else if (pick === '') {
    // (round its caster: nothing to aim)
    intent = withTarget(pv.cast, '', sceneId);
    delete intent.ctx.target;
  } else intent = withNoTarget(pv.cast, sceneId);
  const r = await submit(intent);
  if (r.ok) cancel();
}

// ------------------------------------------------------------- pointer --

/** A press on the map while a tool is out: whether the tool takes it (else the map pans). */
export function press(w: Where, p: Vec): boolean {
  const reach = 18 / Math.max(w.scale, 1e-3);
  switch (tools.mode) {
    case 'ping':
      ping(w, p);
      tools.mode = '';
      return true;
    case 'ruler': {
      const q = snapHere(w, p);
      if (!tools.draft) {
        fixed = [q];
        cursor = q;
        firstPress = true;
      } else {
        if (fixed.length >= MAX_POINTS) {
          notice(`A ruler has ${MAX_POINTS} points at most: Done, then another`, 'error');
          return true;
        }
        cursor = q;
        firstPress = false;
      }
      pressed = true;
      tools.draft = rulerDraft(w, true);
      sendMark(tools.draft);
      return true;
    }
    case 'template':
    case 'preview': {
      if (!tools.draft) {
        if (tools.mode === 'preview' && tools.preview?.from === 'self') return false;
        const shape = tools.mode === 'template' ? formShape(w.grid) : tools.preview!.shape;
        const at = placeAt(w.grid, shape, p, gridless(w.map));
        const label = tools.mode === 'template' ? shapeWords(tools.shape, Number(tools.feet) || 5) : String(tools.preview?.label ?? '');
        tools.draft = { id: newId(tools.mode), kind: tools.mode, scene: String(w.scene.id ?? ''), points: pts([at]), shape, direction: 0, label };
        if (tools.mode === 'preview' && tools.preview?.actor) tools.draft.actor = tools.preview.actor;
        sendMark(tools.draft, true);
        return true;
      }
      const pl = placement(tools.draft, w);
      const k = turnable() ? knob(tools.draft.shape as Shape, pl) : null;
      if (k && Math.hypot(k.x - p.x, k.y - p.y) <= reach) {
        grab = 'turn';
        return true;
      }
      if (movable() && (Math.hypot(pl.at.x - p.x, pl.at.y - p.y) <= Math.max(reach, 0.5) || inShape(tools.draft.shape as Shape, pl, p))) {
        grab = 'move';
        grabOffset = { x: pl.at.x - p.x, y: pl.at.y - p.y };
        return true;
      }
      return false;
    }
  }
  return false;
}

/** The pointer moved, pressed: a ruler's end follows it; a template being moved or turned too. */
export function drag(w: Where, p: Vec): void {
  if (tools.mode === 'ruler' && pressed && tools.draft) {
    cursor = snapHere(w, p);
    tools.draft = rulerDraft(w, true);
    sendMark(tools.draft);
    return;
  }
  if (!tools.draft || !grab) return;
  if (grab === 'turn') {
    const pl = placement(tools.draft, w);
    const d = Math.round((Math.atan2(p.y - pl.at.y, p.x - pl.at.x) * 180) / Math.PI);
    tools.draft = { ...tools.draft, direction: d, live: true };
  } else {
    const shape = tools.draft.shape as Shape;
    const at = placeAt(w.grid, shape, { x: p.x + grabOffset.x, y: p.y + grabOffset.y }, gridless(w.map));
    tools.draft = { ...tools.draft, points: pts([at]), live: true };
  }
  sendMark(tools.draft);
}

/** Let go: a ruler drawn by a drag is measured and let go (it lingers); a tap
 *  fixes a point and the ruler stays open for more; a template put where it
 *  was moved or turned. */
export function release(w: Where, p: Vec, moved: boolean): void {
  if (tools.mode === 'ruler' && pressed && tools.draft) {
    pressed = false;
    if (moved) cursor = snapHere(w, p);
    if (firstPress) {
      if (moved && cursor) {
        fixed.push(cursor);
        letGoRuler(w);
        return;
      }
      tools.tapping = true;
    } else if (cursor) {
      const last = fixed[fixed.length - 1];
      if (!last || Math.hypot(last.x - cursor.x, last.y - cursor.y) > 1e-6) fixed.push(cursor);
    }
    tools.draft = rulerDraft(w, true);
    sendMark(tools.draft, true);
    return;
  }
  if (grab && tools.draft) {
    grab = '';
    tools.draft = { ...tools.draft, live: false };
    sendMark(tools.draft, true);
  }
}

/** A press the map takes back (a second finger came down: a pinch, not a
 *  point): a ruler it started goes, a point it was adding isn't added, a
 *  template stays where it was. */
export function abort(w: Where): void {
  if (tools.mode === 'ruler' && pressed) {
    pressed = false;
    if (firstPress) {
      cancelRuler();
      return;
    }
    cursor = fixed[fixed.length - 1] ?? null;
    if (tools.draft) {
      tools.draft = rulerDraft(w, true);
      sendMark(tools.draft);
    }
    return;
  }
  grab = '';
}

/** The mouse moved, not pressed: a ruler being tapped out follows it from its last point. */
export function hover(w: Where, p: Vec): void {
  if (tools.mode !== 'ruler' || !tools.tapping || pressed || !tools.draft) return;
  const q = snapHere(w, p);
  if (cursor && Math.hypot(cursor.x - q.x, cursor.y - q.y) < 1e-6) return;
  cursor = q;
  tools.draft = rulerDraft(w, true);
  sendMark(tools.draft);
}

/** "Look here": a ping where the press was, fading in a moment. */
export function ping(w: Where, p: Vec): void {
  if (!w.scene?.id) return;
  sendMark({ id: newId('ping'), kind: 'ping', scene: String(w.scene.id), points: pts([p]) }, true);
}

// ---------------------------------------------------------------- list --

/** Take every mark of mine off (pinned too). */
export function clearMine(): void {
  cancel();
  send({ t: 'mark', op: 'clear' });
}

/** The DM: take everyone's marks off. */
export function clearEveryone(): void {
  cancel();
  send({ t: 'mark', op: 'clear', whose: 'all' });
}

/** Take one mark off: mine, or (the DM) anyone's. */
export function removeMark(id: string): void {
  if (tools.draft && String(tools.draft.id) === id) cancel();
  else send({ t: 'mark', op: 'remove', id });
}

/** Pin or unpin a mark of mine already on the map. */
export function pinMark(m: Dict): void {
  if (tools.draft && String(tools.draft.id) === String(m.id)) {
    togglePin();
    return;
  }
  sendMark({ ...m, pinned: !m.pinned, live: false }, true);
}
