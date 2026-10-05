import { describe, expect, it } from 'vitest';
import { actorHp, caughtWords, effectsOf, inMind, marksOf, mindPick, mindPickWords, mindRows, namesCaught } from '../src/lib/mind';
import { offersNoTarget, onBattleMap, pickChoices, pickCount, withTarget } from '../src/lib/map/pick';
import { fightSettings, fightWhyWords, suggestedDraft, suggestionWords, thisFightWords, type Registry, type Setting } from '../src/lib/tablesettings';

// a fight in the theatre of the mind as the host sends it (WebScene.build: `space`, no map)
function scene(over: Record<string, unknown> = {}) {
  return {
    id: 's_mind',
    name: 'On the bridge',
    map: '',
    space: 'mind',
    tokens: [
      { id: 't_sela', name: 'Sela', label: 'SE', actor: 'a_sela', owner: 'pl_ana', pos: [1000, 0], tags: [] },
      { id: 't_brak', name: 'Brakka', label: 'BR', actor: 'a_brak', owner: 'pl_ben', pos: [2000, 0], tags: [] },
      { id: 't_g1', name: 'Goblin Warrior', label: 'GW1', actor: 'a_g1', pos: [3000, 0], tags: ['humanoid', 'bloodied'] },
      { id: 't_g2', name: 'Goblin Warrior', label: 'GW2', actor: 'a_g2', pos: [4000, 0], tags: ['humanoid'], hp: [7, 10] },
      { id: 't_g3', name: 'Goblin Warrior', label: 'GW3', actor: 'a_g3', pos: [5000, 0], tags: ['dead'], hidden: true },
      { id: 't_light', name: 'Light', label: 'L', pos: [5500, 0], tags: ['object'] },
    ],
    turns: { running: true, mode: 'ordered', order: ['t_g2', 't_sela', 't_g1', 't_brak'], turn: 1, round: 2, data: { labels: { t_g2: '18', t_sela: '15' } } },
    ...over,
  };
}

describe('a fight in the theatre of the mind', () => {
  it('knows one when it sees one, and it is no battle map to pick on', () => {
    expect(inMind(scene())).toBe(true);
    expect(inMind({ id: 's', map: 'm1' })).toBe(false);
    expect(inMind(null)).toBe(false);
    expect(onBattleMap(scene())).toBe(false);
    expect(onBattleMap({ id: 's', map: 'm1', role: 'battle' })).toBe(true);
  });

  it('lists who is in it: in the order, what the screen may know of each one’s health, its conditions, whose turn it is', () => {
    const actors = {
      a_sela: { id: 'a_sela', name: 'Sela', effects: [{ key: 'concentrating', label: 'Concentrating: Web' }, { key: 'prone', label: 'Prone' }, { key: 'prone', label: 'Prone' }], resources: { r: { hp: { current: 9, max: 12 } } } },
    };
    const rows = mindRows(scene(), actors, { me: 'pl_ana' });
    expect(rows.map((r) => r.id)).toEqual(['t_g2', 't_sela', 't_g1', 't_brak', 't_g3']);
    const sela = rows[1];
    expect(sela).toMatchObject({ name: 'Sela', label: 'SE', party: true, mine: true, current: true, order: 1, init: '15', target: 'token:t_sela' });
    expect(sela.effects).toEqual(['Concentrating: Web', 'Prone']);
    expect(sela.hp).toBe('');
    expect(rows[0]).toMatchObject({ marks: '', hp: '7/10', init: '18', party: false });
    expect(rows[2]).toMatchObject({ marks: 'Bloodied', hp: '' });
    expect(rows[4]).toMatchObject({ marks: 'Dead', dead: true, hidden: true, order: -1 });
    expect(rows.some((r) => r.id === 't_light')).toBe(false);
    // the DM's: a stat block's hit points where no token says them
    const dm = mindRows(scene(), { a_g1: { resources: { srd: { hp: { current: 4, max: 10 } } } } }, { gm: true });
    expect(dm.find((r) => r.id === 't_g1')?.hp).toBe('4/10');
  });

  it('reads health and effects as the host sends them', () => {
    expect(marksOf({ tags: ['down', 'bloodied'] })).toBe('Down');
    expect(marksOf({})).toBe('');
    expect(actorHp({ resources: { a: { hp: { current: -3, max: 10 } } } })).toBe('0/10');
    expect(actorHp(undefined)).toBe('');
    expect(effectsOf({ effects: [{ label: 'Exhaustion', value: 2 }, { key: 'blessed' }] })).toEqual(['Exhaustion 2', 'blessed']);
  });

  it('a target is a creature from the list: no distance, no sight, only the dead are barred', () => {
    const tokens = scene().tokens;
    const pick = { kind: 'action', plugin: 'r', action: 'attack', ctx: { actor: 'a_sela' }, pick: 'token', label: 'Fire Bolt', range: 120 };
    const list = pickChoices(tokens, pick, { gm: false });
    expect(list.map((c) => c.target)).toEqual(['token:t_g1', 'token:t_g2', 'token:t_brak']);
    expect(list.every((c) => c.why === '')).toBe(true);
    const dm = pickChoices(tokens, pick, { gm: true });
    expect(dm.find((c) => c.target === 'token:t_g3')?.why).toBe('dead');
    expect(mindPick(pick, 6)).toBe(pick);
    expect(offersNoTarget(pick)).toBe(true);
    expect(mindPickWords(pick)).toBe('Fire Bolt: choose a creature below, then Done.');
  });

  it('an area becomes the creatures it catches, named from the list, sent as a list with caught', () => {
    const area = { kind: 'action', plugin: 'r', action: 'cast', ctx: { actor: 'a_sela', spell: 'burning-hands' }, pick: 'area', area: { shape: 'cone', length: 3 }, label: 'Cast', what: 'Burning Hands' };
    const p = mindPick(area, 6);
    expect(p).toMatchObject({ pick: 'token', picks: 6, caught: true, label: 'Who does your Burning Hands catch?' });
    expect(p.area).toBeUndefined();
    expect(p.ctx).toEqual({ actor: 'a_sela', spell: 'burning-hands', caught: true });
    expect(area.pick).toBe('area');
    expect(namesCaught(p)).toBe(true);
    expect(pickCount(p)).toBe(6);
    expect(offersNoTarget(p)).toBe(true);
    expect(mindPickWords(p)).toBe('Who does your Burning Hands catch? Choose each creature it catches below, then Done.');
    expect(mindPick({ ...area, what: '' }, 3, true).label).toBe('Who does Cast catch?');
    const names: Record<string, string> = { 'token:t_g1': 'Goblin Warrior (GW1)', 'token:t_g2': 'Goblin Warrior (GW2)' };
    expect(caughtWords(p, ['token:t_g1', 'token:t_g2'], (t) => names[t])).toBe('Burning Hands catches Goblin Warrior (GW1), Goblin Warrior (GW2)');
    expect(caughtWords(p, [], (t) => t)).toBe('Nobody chosen yet.');
    const sent = withTarget(p, ['token:t_g1', 'token:t_g2'], 's_mind');
    expect(sent).toEqual({ kind: 'action', plugin: 'r', action: 'cast', ctx: { actor: 'a_sela', spell: 'burning-hands', caught: true, target: ['token:t_g1', 'token:t_g2'], scene: 's_mind' } });
  });
});

// Table settings for a fight: a fight's own settings, the theatre of the mind's, an author's suggestion
function setting(over: Partial<Setting>): Setting {
  return { id: `r/${over.key}`, plugin: 'r', plugin_name: 'Rules', key: '', title: '', description: '', type: 'boolean', value: true, default: true, question: 'checks',
    notice: 'everyone', next_fight: false, levels: {}, differs: false, ...over };
}

function reg(over: Partial<Registry> = {}): Registry {
  return {
    level: 'automated', level_set: true, customized: false, differs: 0, pending: true, space: 'maps', house_rules: '',
    levels: ['bookkeeping', 'rolling', 'assisted', 'automated'].map((id) => ({ id: id as Registry['level'], title: id[0].toUpperCase() + id.slice(1), tagline: '', lines: [] })),
    spaces: [{ id: 'maps', title: 'On maps', words: '' }, { id: 'mind', title: 'In the theatre of the mind', words: '' }, { id: 'per_fight', title: 'Each fight decides', words: '' }],
    questions: [],
    settings: [
      setting({ key: 'range', title: 'Check range and reach', per_fight: true, mind: false, levels: { bookkeeping: false, assisted: true, automated: true } }),
      setting({ key: 'approve', title: 'Approve outcomes', question: 'outcomes', value: false, per_fight: true, levels: { assisted: true, automated: false } }),
      setting({ key: 'edition', title: 'Rules version', type: 'string', value: '2024', enum: ['2024', '2014'], question: 'rules' }),
    ],
    plugins: [{ id: 'r', name: 'Rules' }],
    ...over,
  };
}

describe('a fight’s own settings, and an author’s suggestion', () => {
  it('lists what a fight may have of its own, and says what differs in this one', () => {
    expect(fightSettings(reg()).map((s) => s.key)).toEqual(['range', 'approve']);
    expect(fightSettings(null)).toEqual([]);
    expect(thisFightWords(reg())).toBe('');
    const mind = reg({ this_fight: { id: 'enc_1', name: 'On the bridge', space: 'mind', space_title: 'In the theatre of the mind', settings: {}, differs: 1 } });
    expect(thisFightWords(mind)).toBe('This fight (On the bridge, in the theatre of the mind) runs otherwise: 1 setting differs for it, and only while it runs.');
    expect(thisFightWords(reg({ this_fight: { id: 'e', name: 'Nave', space: 'maps', space_title: '', settings: {}, differs: 0 } }))).toBe('');
    expect(thisFightWords(reg({ this_fight: { id: 'e', name: 'Nave', space: 'mind', space_title: '', settings: {}, differs: 0 } }))).toBe('This fight (Nave) is in the theatre of the mind.');
    expect(fightWhyWords(setting({ fight_value: false, fight_words: 'Off', fight_why: 'mind' }))).toBe('This fight: Off (the theatre of the mind: yours to judge)');
    expect(fightWhyWords(setting({ fight_value: true, fight_words: 'On', fight_why: 'fight' }))).toBe('This fight: On (its own)');
    expect(fightWhyWords(setting({}))).toBe('');
  });

  it('the walkthrough starts from the author’s suggestion, and says it is only that', () => {
    expect(suggestedDraft(reg())).toBeNull();
    expect(suggestionWords(reg())).toBe('');
    const r = reg({ new_level: 'assisted', recommended: { level: 'bookkeeping', space: 'per_fight', answers: { 'r/approve': true, 'r/nope': 1 }, note: 'Short fights.', by: 'The Hall', words: 'The author suggests Bookkeeping, each fight decides, 1 setting of their own.' } });
    const d = suggestedDraft(r);
    expect(d?.level).toBe('bookkeeping');
    expect(d?.space).toBe('per_fight');
    expect(d?.values['r/range']).toBe(false);
    expect(d?.values['r/approve']).toBe(true);
    expect('r/nope' in (d?.values ?? {})).toBe(false);
    expect(suggestionWords(r)).toBe('The author suggests Bookkeeping, each fight decides, 1 setting of their own for The Hall. Short fights. It’s only a suggestion: choose what suits your table.'.replace('It’s', "It's"));
    expect(suggestedDraft(reg({ recommended: { space: 'the moon', answers: {}, note: '', by: '', words: '' } }))).toMatchObject({ level: 'assisted', space: 'maps' });
  });
});
