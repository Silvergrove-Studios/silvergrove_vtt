// How a table runs, as the DM's screen draws it: the model the host sends
// in the DM's state (`table`: hexmap/table/table_settings.gd), and what the
// screens work out from it — a level switch's preview, the sections a search
// leaves, a question's line, the walkthrough's draft and what in it is the
// DM's own. Pure: the components send the changes (lib/game.svelte.ts).

type Dict = Record<string, any>;

export type Level = 'bookkeeping' | 'rolling' | 'assisted' | 'automated';
export const LEVELS: Level[] = ['bookkeeping', 'rolling', 'assisted', 'automated'];

export interface LevelInfo {
  id: Level;
  title: string;
  tagline: string;
  lines: string[];
}

export interface Question {
  id: string;
  title: string;
  description: string;
  settings: string[];
  /** A level answers it (the walkthrough's questions). */
  level: boolean;
}

export interface Setting {
  id: string;
  plugin: string;
  plugin_name: string;
  key: string;
  title: string;
  description: string;
  type: 'string' | 'boolean' | 'integer' | 'number';
  enum?: unknown[];
  labels?: string[];
  minimum?: number;
  maximum?: number;
  value: unknown;
  default: unknown;
  question: string;
  notice: '' | 'dm' | 'players' | 'everyone';
  next_fight: boolean;
  levels: Partial<Record<Level, unknown>>;
  level_value?: unknown;
  differs: boolean;
}

/** What a player may choose for themselves (a ruleset's `preferences`), as the
 *  table offers it: hexmap/rules/player_prefs.gd's items. */
export interface Pref {
  id: string;
  plugin: string;
  plugin_name: string;
  key: string;
  title: string;
  description: string;
  type: 'string' | 'boolean' | 'integer' | 'number';
  enum?: unknown[];
  labels?: string[];
  minimum?: number;
  maximum?: number;
  default: unknown;
  /** The table lets players choose it now (its `x-when` holds). */
  offered: boolean;
  /** The settings that would offer it, in words. */
  when: { key: string; title: string; value: string }[];
}

/** One player's preferences, as the DM's Table settings lists them. */
export interface PlayerPrefs {
  id: string;
  name: string;
  /** "<plugin>/<key>" → the value in force. */
  values: Record<string, unknown>;
  /** "<plugin>/<key>" → true where the player chose it themselves. */
  own: Record<string, boolean>;
}

export interface Registry {
  level: Level;
  level_set: boolean;
  customized: boolean;
  differs: number;
  pending: boolean;
  space: string;
  house_rules: string;
  levels: LevelInfo[];
  spaces: { id: string; title: string; words: string }[];
  questions: Question[];
  settings: Setting[];
  plugins: { id: string; name: string }[];
  fight?: boolean;
  undo?: string;
  new_level?: Level;
  existing_level?: Level;
  /** What players may choose for themselves, and each player's choices. */
  prefs?: Pref[];
  players?: PlayerPrefs[];
}

export interface Change {
  id: string;
  plugin: string;
  key: string;
  title: string;
  question: string;
  from: unknown;
  to: unknown;
  fromWords: string;
  toWords: string;
  notice: string;
  nextFight: boolean;
}

/** The model from the DM's state, or null before the table sent one. */
export function registryOf(dm: Dict): Registry | null {
  const t = dm?.table;
  return t && typeof t === 'object' && Array.isArray(t.settings) && Array.isArray(t.levels) ? (t as Registry) : null;
}

/** Two values the same, as the host's JSON has them (30 and 30.0 alike). */
export function same(a: unknown, b: unknown): boolean {
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b) < 1e-9;
  if (a === b) return true;
  if (a && b && typeof a === 'object' && typeof b === 'object') return JSON.stringify(a) === JSON.stringify(b);
  return false;
}

export function levelTitle(reg: Registry | null, id: string): string {
  return reg?.levels.find((l) => l.id === id)?.title ?? id;
}

export function questionTitle(reg: Registry | null, id: string): string {
  return reg?.questions.find((q) => q.id === id)?.title ?? id;
}

/** A value as the screens say it: a choice's label, On or Off, a number. */
export function valueWords(s: { enum?: unknown[]; labels?: string[]; type: string }, v: unknown): string {
  if (Array.isArray(s.enum)) {
    const i = s.enum.findIndex((c) => same(c, v));
    if (i >= 0) return String((s.labels ?? s.enum)[i] ?? v);
  }
  if (s.type === 'boolean') return v === true ? 'On' : 'Off';
  if (typeof v === 'number') return Number.isInteger(v) ? String(v) : String(Math.round(v * 100) / 100);
  return String(v ?? '');
}

/** What switching to `level` changes: each setting whose value would. */
export function levelChanges(reg: Registry, level: Level, values: Record<string, unknown> = {}): Change[] {
  const out: Change[] = [];
  for (const s of reg.settings) {
    if (!(level in (s.levels ?? {}))) continue;
    const from = s.id in values ? values[s.id] : s.value;
    const to = s.levels[level];
    if (same(from, to)) continue;
    out.push({ id: s.id, plugin: s.plugin, key: s.key, title: s.title, question: s.question, from, to, fromWords: valueWords(s, from), toWords: valueWords(s, to), notice: s.notice, nextFight: !!s.next_fight });
  }
  return out;
}

/** "12 settings change: …" — the preview of a level switch in a line. */
export function changeWords(changes: Change[]): string {
  if (!changes.length) return 'Nothing changes: every setting already is as that level has it.';
  const n = changes.length;
  return `${n} setting${n === 1 ? '' : 's'} change${n === 1 ? 's' : ''}: ${changes.map((c) => `${c.title} (${c.fromWords} → ${c.toWords})`).join('; ')}.`;
}

/** The badge's words: as the level has it, Customized, or a campaign from before levels. */
export function badgeWords(reg: Registry): string {
  const lv = levelTitle(reg, reg.level);
  if (reg.customized) return `Customized: ${reg.differs} setting${reg.differs === 1 ? '' : 's'} differ${reg.differs === 1 ? 's' : ''} from ${lv}`;
  if (!reg.level_set) return `A campaign from before levels: ${lv}`;
  return `As ${lv} has it`;
}

function haystack(reg: Registry, s: Setting): string {
  return [s.title, s.description, s.key, questionTitle(reg, s.question), ...(s.labels ?? [])].join(' ').toLowerCase();
}

function matches(words: string[], hay: string): boolean {
  return words.every((w) => hay.includes(w));
}

export interface Section {
  question: Question;
  settings: Setting[];
  /** The table's own field shows in it (where fights happen; the house rules). */
  own: boolean;
}

/** The sections Table settings shows, in the questions' order, with what a search leaves in each. */
export function sections(reg: Registry, search = ''): Section[] {
  const words = search.toLowerCase().split(/\s+/).filter(Boolean);
  const byId = new Map(reg.settings.map((s) => [s.id, s]));
  const out: Section[] = [];
  for (const q of reg.questions) {
    const settings = q.settings.map((id) => byId.get(id)).filter((s): s is Setting => !!s && matches(words, haystack(reg, s)));
    const ownWords = q.id === 'space' ? `${q.title} maps theatre mind fight` : q.id === 'table' ? `${q.title} house rules` : '';
    const own = ownWords !== '' && matches(words, ownWords.toLowerCase());
    if (settings.length || own) out.push({ question: q, settings, own });
  }
  return out;
}

/** Whether a section has settings the level sets, and whether any differ (for its Reset). */
export function sectionReset(reg: Registry, section: Section): { follows: boolean; differs: boolean } {
  const follows = section.settings.filter((s) => reg.level in (s.levels ?? {}));
  return { follows: follows.length > 0, differs: follows.some((s) => s.differs) };
}

/** A question's settings in a line: "Title: value · Title: value", with `values` over the ones in force. */
export function questionLine(reg: Registry, question: string, values: Record<string, unknown> = {}): string {
  return reg.settings
    .filter((s) => s.question === question)
    .map((s) => `${s.title}: ${valueWords(s, s.id in values ? values[s.id] : s.value)}`)
    .join(' · ');
}

/** The walkthrough's values: the ones in force, with the level's over them. */
export function draftFor(reg: Registry, level: Level, values: Record<string, unknown> = {}): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const s of reg.settings) out[s.id] = s.id in values ? values[s.id] : s.value;
  for (const s of reg.settings) if (level in (s.levels ?? {})) out[s.id] = s.levels[level];
  return out;
}

/** What in the walkthrough's values is the DM's own: what differs from the level's value (or, where the level says nothing, from the value in force). */
export function ownAnswers(reg: Registry, level: Level, values: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const s of reg.settings) {
    if (!(s.id in values)) continue;
    const base = level in (s.levels ?? {}) ? s.levels[level] : s.value;
    if (!same(values[s.id], base)) out[s.id] = values[s.id];
  }
  return out;
}

/** Who notices a change, in words ("" when the ruleset doesn't say). */
export function noticeWords(notice: string): string {
  return ({ dm: 'you notice', players: 'players notice', everyone: 'everyone notices' } as Record<string, string>)[notice] ?? '';
}

/** What the players are told (the view's `table`), or null when the table sent none. */
export interface PlayerSummary {
  level: Level;
  title: string;
  tagline: string;
  lines: string[];
  set: boolean;
  space: string;
  space_title: string;
  space_words: string;
  answers: { question: string; title: string; items: { title: string; value: string }[] }[];
  house_rules: string;
  /** The campaign's id (what a browser remembers having shown it for). */
  campaign?: string;
  /** What the table lets each player choose for themselves now. */
  prefs?: Pref[];
}

export function summaryOf(view: Dict): PlayerSummary | null {
  const t = view?.table;
  return t && typeof t === 'object' && typeof t.title === 'string' && Array.isArray(t.lines) ? (t as PlayerSummary) : null;
}

/** The key a browser keeps once a player has been shown how a table runs (shown again when the level changes). */
export function summarySeenKey(table: string, player: string, level: string): string {
  return `hexmap.table-runs/${table}/${player}/${level}`;
}

/** A player's preference in force, from their record (the scene's
 *  `players`: `prefs` by plugin id): their own choice, else its default. */
export function prefValue(players: Dict[], me: string, p: Pref): unknown {
  const rec = (players ?? []).find((x) => x && String(x.id) === me);
  const mine = rec?.prefs?.[p.plugin];
  if (mine && typeof mine === 'object' && !Array.isArray(mine) && p.key in mine) return mine[p.key];
  return p.default;
}

/** Whether a player chose a preference themselves (rather than the table's default). */
export function prefOwn(players: Dict[], me: string, p: Pref): boolean {
  const rec = (players ?? []).find((x) => x && String(x.id) === me);
  const mine = rec?.prefs?.[p.plugin];
  return !!mine && typeof mine === 'object' && !Array.isArray(mine) && p.key in mine;
}

/** What would let players choose a preference the table keeps for now: "Players' dice: Each player chooses". */
export function prefWhenWords(p: Pref): string {
  return (p.when ?? []).map((w) => `${w.title}: ${w.value}`).join(', ');
}
