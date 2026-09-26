// The DM's book: the campaign's contents in the DM's own arrangement, as
// the Table's reference pane builds it (hexmap/table/reference_panel.gd):
// sections (renamed as the DM likes), the DM's folders among and inside
// them, and what was filed into the folders. Built from the DM's state.
import type { Dict } from '../lib/game.svelte';

export const SECTIONS: [string, string][] = [
  ['notes', 'Notes for you'],
  ['party', 'The party'],
  ['places', 'Places'],
  // the campaign's fights, and the DM's own (a playtest's DM could start only the adventure's)
  ['fights', 'Fights'],
  ['people', 'People'],
  ['handouts', 'Handouts'],
  ['shown', 'Shown to the players'],
  ['from_players', 'From the players'],
  ['pictures', 'Pictures'],
  ['maps', 'Maps'],
  ['rules', 'Rules'],
];
const KINDS_PEOPLE = ['npc', 'environment', 'hazard', 'custom'];
const KINDS_PARTY = ['pc', 'companion'];

export interface Item {
  label: string;
  ref: string;
  sub?: string;
  children?: Item[];
}

export interface Node {
  node: string; // "section:places" | "folder:f_1"
  title: string;
  folders: Node[];
  items: Item[];
}

export function layout(dm: Dict): Dict {
  const lay: Dict = dm.contents && typeof dm.contents === 'object' ? dm.contents : {};
  return { titles: lay.titles ?? {}, folders: ((lay.folders as Dict[]) ?? []).filter((f) => f && typeof f === 'object'), in: lay.in ?? {}, order: (lay.order as string[]) ?? [] };
}

export function sectionTitle(dm: Dict, key: string): string {
  const t = String(layout(dm).titles[key] ?? '');
  if (t) return t;
  return SECTIONS.find((s) => s[0] === key)?.[1] ?? key;
}

/** The top of the contents in the DM's order: the sections, then the DM's top-level folders, each where it was put. */
export function topOrder(dm: Dict): string[] {
  const lay = layout(dm);
  const all = [...SECTIONS.map((s) => `section:${s[0]}`), ...lay.folders.filter((f: Dict) => !f.parent).map((f: Dict) => `folder:${f.id}`)];
  const out: string[] = [];
  for (const n of lay.order) if (all.includes(String(n)) && !out.includes(String(n))) out.push(String(n));
  // (Fights is the web screen's own section: after Places, where the Table's order doesn't say)
  if (!out.includes('section:fights') && out.includes('section:places')) out.splice(out.indexOf('section:places') + 1, 0, 'section:fights');
  for (const n of all) if (!out.includes(n)) out.push(n);
  return out;
}

function hay(...parts: unknown[]): string {
  return parts.map((p) => (Array.isArray(p) ? p.join(' ') : String(p ?? ''))).join(' ').toLowerCase();
}

export function audienceWords(dm: Dict, players: Dict[], audience: string): string {
  if (audience === 'all') return 'everyone';
  if (audience.startsWith('players:')) {
    const ids = audience.slice(8).split(',').filter(Boolean);
    return ids.map((id) => String(players.find((p) => String(p.id) === id)?.name ?? id)).join(' and ') || 'nobody';
  }
  return 'only you';
}

/** Every section's items matching `q` (all of them when it is empty). */
export function contents(dm: Dict, players: Dict[], q: string): Record<string, Item[]> {
  const people: Dict[] = (dm.people as Dict[]) ?? [];
  const places: Dict[] = (dm.places as Dict[]) ?? [];
  const placeName = (id: string) => String(places.find((p) => String(p.id) === id)?.name ?? '');
  const playerName = (id: string) => String(players.find((p) => String(p.id) === id)?.name ?? id);
  const out: Record<string, Item[]> = { notes: [], party: [], places: [], fights: [], people: [], handouts: [], shown: [], from_players: [], pictures: [], maps: [] };
  const sorted = [...people].sort((a, b) => String(a.name ?? '').localeCompare(String(b.name ?? ''), undefined, { sensitivity: 'base', numeric: true }));
  for (const a of sorted) {
    const kind = String(a.kind ?? '');
    if (q && !hay(a.name, a.notes, a.public).includes(q)) continue;
    if (KINDS_PARTY.includes(kind)) out.party.push({ label: String(a.name ?? a.id), sub: a.owner ? playerName(String(a.owner)) : '', ref: `actor:${a.id}` });
    else if (KINDS_PEOPLE.includes(kind)) out.people.push({ label: String(a.name ?? a.id), sub: placeName(String(a.place ?? '')), ref: `actor:${a.id}` });
  }
  for (const n of (dm.player_notes as Dict[]) ?? []) {
    if (q && !hay(n.title, n.text, n.folder).includes(q)) continue;
    out.from_players.push({ label: String(n.title || String(n.text ?? '').slice(0, 40)), sub: playerName(String(n.owner ?? '')), ref: `pnote:${n.id}` });
  }
  for (const p of places) {
    if (q && !hay(p.name, p.text, p.notes).includes(q)) continue;
    const here = q ? [] : sorted.filter((a) => String(a.place ?? '') === String(p.id) && !KINDS_PARTY.includes(String(a.kind ?? ''))).map((a) => ({ label: String(a.name ?? a.id), ref: `actor:${a.id}` }));
    out.places.push({ label: String(p.name ?? ''), sub: p.kind === 'encounter' ? 'a fight' : '', ref: `place:${p.id}`, children: here });
  }
  for (const n of (dm.journal as Dict[]) ?? []) {
    const kind = String(n.kind ?? 'note');
    if (q && !hay(n.title, n.text, n.tags).includes(q)) continue;
    const title = String(n.title || String(n.text ?? '').slice(0, 40));
    if (kind === 'handout' && n.ref) out.shown.unshift({ label: title, sub: `→ ${audienceWords(dm, players, String(n.audience ?? 'gm'))}`, ref: `handout:${n.id}` });
    else if (kind === 'handout') out.handouts.push({ label: title, ref: `note:${n.id}` });
    else {
      const item = { label: (kind === 'ruling' ? 'Ruling: ' : '') + title, ref: `note:${n.id}` };
      if (((n.tags as string[]) ?? []).includes('start')) out.notes.unshift(item);
      else out.notes.push(item);
    }
  }
  for (const f of (dm.encounters as Dict[]) ?? []) {
    if (q && !hay(f.name, f.notes, ((f.creatures as Dict[]) ?? []).map((c) => c.name)).includes(q)) continue;
    const n = ((f.creatures as Dict[]) ?? []).reduce((sum, c) => sum + Number(c.count ?? 1), 0);
    const live = f.live && typeof f.live === 'object' && Object.keys(f.live).length > 0;
    out.fights.push({ label: String(f.name || 'A fight'), sub: live ? 'running now' : n ? `${n} creature${n === 1 ? '' : 's'}` : 'no creatures yet', ref: `fight:${f.id}` });
  }
  for (const pic of (dm.pictures as Dict[]) ?? []) {
    if (q && !hay(pic.name, pic.tags).includes(q)) continue;
    out.pictures.push({ label: String(pic.name ?? ''), ref: `picture:${pic.ref}` });
  }
  for (const m of (dm.maps as Dict[]) ?? []) {
    if (q && !hay(m.name).includes(q)) continue;
    out.maps.push({ label: String(m.name ?? ''), sub: m.role === 'regional' ? 'the region' : 'a battle map', ref: `map:${m.id}` });
  }
  return out;
}

/** The whole book: sections and the DM's folders, what is filed where. Empty sections are left out; an empty folder shows unless searching. */
export function book(dm: Dict, players: Dict[], query: string): Node[] {
  const q = query.trim().toLowerCase();
  const lay = layout(dm);
  const groups = contents(dm, players, q);
  const filed: Record<string, Item[]> = {};
  for (const key of Object.keys(groups)) {
    groups[key] = groups[key].filter((it) => {
      const f = String(lay.in[it.ref] ?? '');
      if (f && lay.folders.some((x: Dict) => x.id === f)) {
        (filed[f] ??= []).push(it);
        return false;
      }
      return true;
    });
  }
  const build = (node: string): Node | null => {
    const [kind, ...rest] = node.split(':');
    const key = rest.join(':');
    if (node === 'section:rules') return null;
    const title = kind === 'section' ? sectionTitle(dm, key) : String(lay.folders.find((f: Dict) => f.id === key)?.title ?? '');
    const folders = lay.folders
      .filter((f: Dict) => String(f.parent ?? '') === node)
      .map((f: Dict) => build(`folder:${f.id}`))
      .filter((n: Node | null): n is Node => n !== null);
    const items = kind === 'section' ? (groups[key] ?? []) : (filed[key] ?? []);
    const empty = folders.length === 0 && items.length === 0;
    // (Fights shows empty too: it is where a new fight is made)
    if (empty && (q || (kind === 'section' && key !== 'fights'))) return null;
    return { node, title, folders, items };
  };
  return topOrder(dm)
    .map(build)
    .filter((n): n is Node => n !== null);
}

/** Every folder, as "Place › Folder" paths, for a "file it in" choice. */
export function folderChoices(dm: Dict): { id: string; path: string }[] {
  const lay = layout(dm);
  const pathOf = (f: Dict, depth = 0): string => {
    const parent = String(f.parent ?? '');
    if (depth > 12) return String(f.title ?? '');
    if (parent.startsWith('folder:')) {
      const up = lay.folders.find((x: Dict) => x.id === parent.slice(7));
      if (up) return `${pathOf(up, depth + 1)} › ${f.title}`;
    }
    if (parent.startsWith('section:')) return `${sectionTitle(dm, parent.slice(8))} › ${f.title}`;
    return String(f.title ?? '');
  };
  return lay.folders.map((f: Dict) => ({ id: String(f.id), path: pathOf(f) })).sort((a: { path: string }, b: { path: string }) => a.path.localeCompare(b.path));
}
