// What a tap on a creature's token asks of the rules: the action a ruleset
// registers with `tap: "creature"` (srd5e's What we know: a card of what the
// party knows of the creature, its name, health, conditions, Armor Class and
// defences as the DM's settings let them know them — the Table puts it right
// for each screen). A player's screen sends it as the token is picked out;
// nothing taps for them where no ruleset answers.
import type { Dict } from './views/viewlib';

/** The first action (by plugin, then name) a ruleset answers a tap of `kind` with. */
export function tapAction(actions: Dict | undefined | null, kind = 'creature'): { plugin: string; action: string } | null {
  const all = actions && typeof actions === 'object' ? actions : {};
  for (const plugin of Object.keys(all).sort()) {
    const list = all[plugin];
    if (!list || typeof list !== 'object') continue;
    for (const action of Object.keys(list).sort()) {
      const a = list[action];
      if (a && typeof a === 'object' && a.tap === kind) return { plugin, action };
    }
  }
  return null;
}

/** Whether a token tapped is a creature to ask about: one with a creature
 *  behind it that no player owns (the party's own are their sheets), not a
 *  thing on the map. */
export function asksAbout(t: Dict | null | undefined): boolean {
  if (!t || typeof t !== 'object') return false;
  if (String(t.actor ?? '') === '' || String(t.owner ?? '') !== '') return false;
  const tags = Array.isArray(t.tags) ? t.tags.map(String) : [];
  return !tags.includes('object');
}

/** The intent a tap on such a token sends: the ruleset's action, aimed at it. */
export function tapIntent(actions: Dict | undefined | null, t: Dict, scene: string): Dict | null {
  if (!asksAbout(t)) return null;
  const found = tapAction(actions);
  if (!found) return null;
  return { kind: 'action', plugin: found.plugin, action: found.action, ctx: { target: `token:${String(t.id)}`, scene } };
}
