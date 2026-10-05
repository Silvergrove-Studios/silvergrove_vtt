// The table's shared marks drawn on a screen's map, as the Table's map draws
// them (hexmap/render/mark_draw.gd): a ruler's line through its points with
// its measure at its end ("Wren: 25 ft"), a template's cells in its owner's
// colour with its outline and the creatures it would catch ringed — of
// those this screen shows — and a ping's rings, fading. Each in its owner's
// colour, with their name.
import { Grid, keyCell, type Vec } from '../grid';
import type { Dict } from '../game.svelte';
import { straight, words, type Diagonals, type Measure } from './measure';
import { caught, knob, outline, templateCells, type Shape } from './template';
import { hexA, tokenPos, tokenRadius } from './render';

/** How long a ping's rings take to fade (ms): the Table keeps one 4 s. */
export const PING_MS = 4000;

export interface MarkLook {
  grid: Grid;
  /** css pixels per hex unit */
  scale: number;
  /** the tokens this screen shows (a mark never tells of another) */
  tokens: Dict[];
  rule: Diagonals;
  noGrid: boolean;
  /** the mark being made here, drawn with its handles */
  draft?: string;
  now: number;
  /** when each mark was first seen here (a ping fades from then) */
  born: (id: string) => number;
  /** the part of the map in view (hex units): a mark's words stay inside it */
  view?: { x0: number; y0: number; x1: number; y1: number };
}

/** A label's box on the map (hex units), so the next one drawn keeps clear of it. */
type Box = { x0: number; y0: number; x1: number; y1: number };

function pointsOf(m: Dict): Vec[] {
  return ((m.points as number[][]) ?? []).map((p) => ({ x: Number(p[0]), y: Number(p[1]) }));
}

/** Where a template mark is: its place (its creature's, for one on a token), which way, and the creature's size. */
export function placementOf(m: Dict, tokens: Dict[]): { at: Vec; direction: number; fromSize: number } {
  const tk = m.token ? tokens.find((t) => String(t.id) === String(m.token)) : undefined;
  const p = pointsOf(m)[0] ?? { x: 0, y: 0 };
  return { at: tk ? tokenPos(tk) : p, direction: Number(m.direction ?? 0), fromSize: tk ? Number(tk.size ?? 1) : m.token ? 1 : 0 };
}

/** A ruler's measure as this screen says it: the Table's (its walk round the
 *  walls with it), or — this screen's own ruler being dragged, ahead of the
 *  Table's word — counted here. `echo` is the Table's record of the mark
 *  being made here. */
export function rulerMeasure(m: Dict, look: Pick<MarkLook, 'grid' | 'rule' | 'noGrid'>, echo?: Dict): Measure {
  const own = m.measure as Measure | undefined;
  if (own) return own;
  const e = echo?.measure as Measure | undefined;
  if (e && samePoints(m, echo)) return e;
  return { straight: straight(look.grid, pointsOf(m), look.rule, look.noGrid), units: look.grid.units || 'ft' };
}

function samePoints(a: Dict, b?: Dict): boolean {
  return !!b && JSON.stringify(a.points ?? []) === JSON.stringify(b.points ?? []);
}

/** What a mark says, after its owner's name: "25 ft", "Fireball, 20-ft sphere", "" for a ping. */
export function markText(m: Dict, look: Pick<MarkLook, 'grid' | 'rule' | 'noGrid'>, echo?: Dict): string {
  switch (String(m.kind ?? '')) {
    case 'ruler':
      return words(rulerMeasure(m, look, echo));
    case 'template':
    case 'preview':
      return String(m.label ?? '');
  }
  return '';
}

/** What a mark says beside it: where (hex units), the words, the owner's colour. */
interface Label {
  at: Vec;
  text: string;
  color: string;
  pinned: boolean;
  alpha: number;
}

/** Draw the marks (world transform set: hex units): their shapes, then the
 *  words beside each, kept clear of one another and inside the view. */
export function drawMarks(ctx: CanvasRenderingContext2D, marks: Dict[], look: MarkLook, echoes: Record<string, Dict> = {}): void {
  const labels: Label[] = [];
  for (const m of marks) {
    const color = String(m.color ?? '#ffffff');
    const name = String(m.name ?? '');
    let l: Label | null = null;
    switch (String(m.kind ?? '')) {
      case 'ruler':
        l = drawRuler(ctx, m, color, name, look, echoes[String(m.id)]);
        break;
      case 'template':
      case 'preview':
        l = drawTemplate(ctx, m, color, name, look);
        break;
      case 'ping':
        l = drawPing(ctx, m, color, name, look);
        break;
    }
    if (l && l.text) labels.push(l);
  }
  const placed: Box[] = [];
  for (const l of labels) label(ctx, l, look, placed);
}

function drawRuler(ctx: CanvasRenderingContext2D, m: Dict, color: string, name: string, look: MarkLook, echo?: Dict): Label | null {
  const pts = pointsOf(m);
  if (!pts.length) return null;
  const px = 1 / look.scale;
  ctx.save();
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  if (pts.length >= 2) {
    ctx.beginPath();
    pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
    ctx.lineWidth = 6 * px;
    ctx.strokeStyle = 'rgba(0,0,0,0.6)';
    ctx.stroke();
    ctx.lineWidth = 3 * px;
    ctx.strokeStyle = color;
    if (m.live) ctx.setLineDash([10 * px, 6 * px]);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  pts.forEach((p, i) => {
    ctx.beginPath();
    ctx.arc(p.x, p.y, (i === 0 || i === pts.length - 1 ? 5 : 3.5) * px, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.lineWidth = 1.5 * px;
    ctx.strokeStyle = 'rgba(0,0,0,0.7)';
    ctx.stroke();
  });
  ctx.restore();
  const text = markText(m, look, echo);
  return { at: pts[pts.length - 1], text: text ? `${name}: ${text}` : name, color, pinned: !!m.pinned, alpha: 1 };
}

function drawTemplate(ctx: CanvasRenderingContext2D, m: Dict, color: string, name: string, look: MarkLook): Label | null {
  const shape = m.shape as Shape | undefined;
  if (!shape) return null;
  const px = 1 / look.scale;
  const pl = placementOf(m, look.tokens);
  ctx.save();
  // the cells it covers, as the rules count them
  const path = new Path2D();
  for (const key of templateCells(look.grid, shape, pl)) {
    look.grid.corners(keyCell(key)).forEach((p, i) => (i ? path.lineTo(p.x, p.y) : path.moveTo(p.x, p.y)));
    path.closePath();
  }
  ctx.fillStyle = hexA(color, 0.2);
  ctx.fill(path);
  // its own outline
  const o = outline(shape, pl);
  ctx.beginPath();
  if (o.circle) ctx.arc(o.circle.at.x, o.circle.at.y, o.circle.r, 0, Math.PI * 2);
  else if (o.poly) {
    o.poly.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
    ctx.closePath();
  }
  ctx.lineWidth = 4 * px;
  ctx.strokeStyle = 'rgba(0,0,0,0.55)';
  ctx.stroke();
  ctx.lineWidth = 2 * px;
  ctx.strokeStyle = color;
  if (m.kind === 'preview') ctx.setLineDash([8 * px, 5 * px]);
  ctx.stroke();
  ctx.setLineDash([]);
  // the creatures it would catch, of those this screen shows
  const who = caught(look.grid, shape, pl, look.tokens, String(m.token ?? ''));
  for (const t of who) {
    const c = tokenPos(t);
    ctx.beginPath();
    ctx.arc(c.x, c.y, tokenRadius(t) + 5 * px, 0, Math.PI * 2);
    ctx.lineWidth = 3 * px;
    ctx.strokeStyle = color;
    ctx.stroke();
  }
  // the one being made: where to grab it, and its knob that turns it
  if (look.draft && look.draft === String(m.id)) {
    ctx.beginPath();
    ctx.arc(pl.at.x, pl.at.y, 6 * px, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    const k = knob(shape, pl);
    if (k && !(m.kind === 'preview' && !m.token && shape.type === 'square')) {
      ctx.beginPath();
      ctx.arc(k.x, k.y, 9 * px, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fill();
      ctx.lineWidth = 3 * px;
      ctx.strokeStyle = color;
      ctx.stroke();
    }
  }
  ctx.restore();
  const text = String(m.label ?? '');
  const n = who.length;
  const words = n ? `${text}${text ? ' · ' : ''}catches ${n}` : text;
  return { at: pl.at, text: words ? `${name}: ${words}` : name, color, pinned: !!m.pinned, alpha: 1 };
}

function drawPing(ctx: CanvasRenderingContext2D, m: Dict, color: string, name: string, look: MarkLook): Label | null {
  const p = pointsOf(m)[0];
  if (!p) return null;
  const px = 1 / look.scale;
  const t = Math.max(0, Math.min(1, (look.now - look.born(String(m.id))) / PING_MS));
  const fade = 1 - t;
  ctx.save();
  for (let k = 0; k < 3; k++) {
    const r = (8 + 30 * (((t * 2 + k / 3) % 1) + 1e-6)) * px;
    ctx.beginPath();
    ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
    ctx.lineWidth = 3 * px;
    ctx.strokeStyle = hexA(color, fade * 0.9);
    ctx.stroke();
  }
  ctx.beginPath();
  ctx.arc(p.x, p.y, 5 * px, 0, Math.PI * 2);
  ctx.fillStyle = hexA(color, fade);
  ctx.fill();
  ctx.restore();
  return { at: p, text: name, color, pinned: false, alpha: fade };
}

/** Where a label goes: beside its place, up and to the right — to the left
 *  when that runs off the view's right, inside the view, and moved down clear
 *  of those already placed. The box it takes. */
export function placeLabel(at: Vec, w: number, h: number, px: number, placed: Box[], view?: Box): Box {
  let x0 = at.x + 10 * px;
  if (view && x0 + w > view.x1 - 4 * px) x0 = Math.max(view.x0 + 4 * px, at.x - 10 * px - w);
  let y0 = at.y - 10 * px - h / 2;
  if (view) y0 = Math.min(Math.max(y0, view.y0 + 4 * px), view.y1 - h - 4 * px);
  for (let tries = 0; tries < 8; tries++) {
    const box = { x0, y0, x1: x0 + w, y1: y0 + h };
    const hit = placed.find((o) => box.x0 < o.x1 && box.x1 > o.x0 && box.y0 < o.y1 && box.y1 > o.y0);
    if (!hit) break;
    y0 = hit.y1 + 2 * px;
  }
  const box = { x0, y0, x1: x0 + w, y1: y0 + h };
  placed.push(box);
  return box;
}

/** Words on the map at a steady size, on a dark ground, with the owner's colour beside them. */
function label(ctx: CanvasRenderingContext2D, l: Label, look: MarkLook, placed: Box[]): void {
  const px = 1 / look.scale;
  const fs = 13 * px;
  const shown = l.pinned ? `📌 ${l.text}` : l.text;
  ctx.save();
  ctx.globalAlpha = l.alpha;
  ctx.font = `600 ${fs}px Inter, system-ui, sans-serif`;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  const w = ctx.measureText(shown).width + 18 * px;
  const h = fs * 1.6;
  const box = placeLabel(l.at, w, h, px, placed, look.view);
  const mid = (box.y0 + box.y1) / 2;
  ctx.beginPath();
  ctx.roundRect(box.x0, box.y0, w, h, 6 * px);
  ctx.fillStyle = 'rgba(14, 16, 20, 0.86)';
  ctx.fill();
  ctx.beginPath();
  ctx.arc(box.x0 + 7 * px, mid, 3.5 * px, 0, Math.PI * 2);
  ctx.fillStyle = l.color;
  ctx.fill();
  ctx.fillStyle = '#ffffff';
  ctx.fillText(shown, box.x0 + 14 * px, mid + 0.5 * px);
  ctx.restore();
}

/** What a creature is called on a screen that doesn't know its name (the
 *  Table sends it so: Knowledge). */
export const UNKNOWN = 'a creature';

/** A creature a template would catch, by name: "a creature" where this
 *  screen doesn't know its name. */
export function catchName(t: Dict): string {
  return t.unknown ? UNKNOWN : String(t.name || t.label || UNKNOWN);
}

/** Who a template catches, in words: the creatures this screen knows by
 *  name, then those it doesn't, counted ("catches 3: Wren, 2 creatures";
 *  "catches 2 creatures"). */
export function catchWords(names: string[]): string {
  if (!names.length) return 'catches nobody you can see';
  const unknown = names.filter((n) => n === UNKNOWN).length;
  const known = names.filter((n) => n !== UNKNOWN);
  const some = unknown === 1 ? UNKNOWN : `${unknown} creatures`;
  if (!known.length) return `catches ${some}`;
  return `catches ${names.length}: ${[...known, ...(unknown ? [some] : [])].join(', ')}`;
}

/** A mark in words for a list (a screen reader's, the marks panel): whose, what, and — a template — who it would catch here. */
export function markLine(m: Dict, look: Pick<MarkLook, 'grid' | 'rule' | 'noGrid' | 'tokens'>, echo?: Dict): { who: string; what: string; catches: string[] } {
  const kind = String(m.kind ?? '');
  const who = String(m.name ?? '');
  if (kind === 'ping') return { who, what: 'a ping: look here', catches: [] };
  if (kind === 'ruler') return { who, what: `ruler: ${markText(m, look, echo)}`, catches: [] };
  const shape = m.shape as Shape | undefined;
  const names = shape ? caught(look.grid, shape, placementOf(m, look.tokens), look.tokens, String(m.token ?? '')).map(catchName) : [];
  return { who, what: String(m.label ?? (kind === 'preview' ? 'a preview' : 'a template')), catches: names };
}
