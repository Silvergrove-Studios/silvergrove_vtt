import { describe, expect, it } from 'vitest';
import {
  badgeWords,
  changeWords,
  draftFor,
  levelChanges,
  noticeWords,
  ownAnswers,
  questionLine,
  registryOf,
  same,
  sectionReset,
  sections,
  summaryOf,
  summarySeenKey,
  valueWords,
  type Registry,
  type Setting,
} from '../src/lib/tablesettings';

// a table as the host sends it (hexmap/table/table_settings.gd `build`):
// a campaign from before levels, with one setting the DM had changed
function setting(over: Partial<Setting>): Setting {
  return {
    id: `r/${over.key}`,
    plugin: 'r',
    plugin_name: 'Rules',
    key: '',
    title: '',
    description: '',
    type: 'boolean',
    value: true,
    default: true,
    question: 'rules',
    notice: 'everyone',
    next_fight: false,
    levels: {},
    differs: false,
    ...over,
  };
}

function table(over: Partial<Registry> = {}): Registry {
  return {
    level: 'automated',
    level_set: false,
    customized: true,
    differs: 1,
    pending: false,
    space: 'maps',
    house_rules: '',
    levels: [
      { id: 'bookkeeping', title: 'Bookkeeping', tagline: 'A shared sheet and tracker', lines: ['a', 'b', 'c'] },
      { id: 'rolling', title: 'Rolling help', tagline: 'Actions roll; nothing is applied', lines: ['a', 'b', 'c'] },
      { id: 'assisted', title: 'Assisted', tagline: 'The app proposes; the DM approves', lines: ['a', 'b', 'c'] },
      { id: 'automated', title: 'Automated', tagline: 'The app runs the rules', lines: ['a', 'b', 'c'] },
    ],
    spaces: [
      { id: 'maps', title: 'On maps', words: '' },
      { id: 'mind', title: 'In the theatre of the mind', words: '' },
      { id: 'per_fight', title: 'Each fight decides', words: '' },
    ],
    questions: [
      { id: 'space', title: 'Where fights happen', description: '', settings: [], level: false },
      { id: 'dice', title: 'Dice', description: '', settings: ['r/initiative'], level: true },
      { id: 'outcomes', title: 'What a roll does', description: '', settings: ['r/damage', 'r/massive'], level: true },
      { id: 'prompting', title: 'Asking and waiting', description: '', settings: ['r/seconds'], level: true },
      { id: 'rules', title: 'Rules options', description: '', settings: ['r/edition'], level: false },
      { id: 'table', title: 'This table', description: '', settings: [], level: false },
    ],
    settings: [
      setting({ key: 'initiative', title: 'Players roll their own initiative', question: 'dice', value: false, notice: 'players', next_fight: true, levels: { bookkeeping: true, rolling: true, assisted: false, automated: false } }),
      setting({ key: 'damage', title: 'Apply damage when an attack hits', question: 'outcomes', value: true, levels: { bookkeeping: false, rolling: false, assisted: true, automated: true } }),
      // the DM had turned instant death off before levels: it differs from Automated
      setting({ key: 'massive', title: 'Instant death', question: 'outcomes', value: false, levels: { bookkeeping: false, rolling: false, assisted: true, automated: true }, level_value: true, differs: true }),
      setting({ key: 'seconds', title: 'Seconds to answer a reaction', question: 'prompting', type: 'integer', value: 30, minimum: 0, maximum: 600, levels: { bookkeeping: 0, rolling: 0, assisted: 30, automated: 30 } }),
      setting({ key: 'edition', title: 'Rules version', type: 'string', value: '2024', enum: ['2024', '2014'], labels: ['2024 (SRD 5.2.1)', '2014 (SRD 5.1)'] }),
    ],
    plugins: [{ id: 'r', name: 'Rules' }],
    undo: '',
    ...over,
  };
}

describe('how a table runs, as the DM’s screen works it out', () => {
  it('reads the model from the DM’s state, and nothing that isn’t one', () => {
    expect(registryOf({ table: table() })?.level).toBe('automated');
    expect(registryOf({})).toBeNull();
    expect(registryOf({ table: {} })).toBeNull();
    expect(registryOf({ table: { settings: [] } })).toBeNull();
  });

  it('says values in words, and takes 30 and 30.0 as one', () => {
    const t = table();
    expect(valueWords(t.settings[0], true)).toBe('On');
    expect(valueWords(t.settings[0], false)).toBe('Off');
    expect(valueWords(t.settings[4], '2014')).toBe('2014 (SRD 5.1)');
    expect(valueWords(t.settings[3], 30)).toBe('30');
    expect(same(30, 30.0)).toBe(true);
    expect(same(true, 1)).toBe(false);
    expect(same('2024', 2024)).toBe(false);
  });

  it('previews a level switch: what changes, from what to what, and whether it waits for the next fight', () => {
    const t = table();
    const to = levelChanges(t, 'bookkeeping');
    expect(to.map((c) => c.key)).toEqual(['initiative', 'damage', 'seconds']);
    expect(to[0]).toMatchObject({ fromWords: 'Off', toWords: 'On', nextFight: true, notice: 'players' });
    expect(to[2]).toMatchObject({ fromWords: '30', toWords: '0' });
    expect(changeWords(to)).toBe('3 settings change: Players roll their own initiative (Off → On); Apply damage when an attack hits (On → Off); Seconds to answer a reaction (30 → 0).');
    // to Automated: only the setting the DM had changed goes back
    const back = levelChanges(t, 'automated');
    expect(back.map((c) => c.key)).toEqual(['massive']);
    expect(changeWords(back)).toBe('1 setting changes: Instant death (Off → On).');
    expect(changeWords([])).toMatch(/^Nothing changes/);
    // a rules option follows no level
    expect(levelChanges(t, 'rolling').some((c) => c.key === 'edition')).toBe(false);
  });

  it('badges the table: Customized, as its level has it, or from before levels', () => {
    expect(badgeWords(table())).toBe('Customized: 1 setting differs from Automated');
    expect(badgeWords(table({ customized: true, differs: 3, level: 'assisted', level_set: true }))).toBe('Customized: 3 settings differ from Assisted');
    expect(badgeWords(table({ customized: false, differs: 0 }))).toBe('A campaign from before levels: Automated');
    expect(badgeWords(table({ customized: false, differs: 0, level: 'bookkeeping', level_set: true }))).toBe('As Bookkeeping has it');
  });

  it('shows the sections by question, what a search leaves, and whether each can be reset', () => {
    const t = table();
    const all = sections(t);
    expect(all.map((s) => s.question.id)).toEqual(['space', 'dice', 'outcomes', 'prompting', 'rules', 'table']);
    expect(all.find((s) => s.question.id === 'space')?.own).toBe(true);
    const death = sections(t, 'instant DEATH');
    expect(death.map((s) => s.question.id)).toEqual(['outcomes']);
    expect(death[0].settings.map((s) => s.key)).toEqual(['massive']);
    // a choice is found by its labels, a section by its title
    expect(sections(t, '5.1').map((s) => s.question.id)).toEqual(['rules']);
    expect(sections(t, 'dice')[0].settings.map((s) => s.key)).toEqual(['initiative']);
    expect(sections(t, 'house').map((s) => s.question.id)).toEqual(['table']);
    expect(sections(t, 'nothing like this')).toEqual([]);
    expect(sectionReset(t, all[2])).toEqual({ follows: true, differs: true });
    expect(sectionReset(t, all[1])).toEqual({ follows: true, differs: false });
    expect(sectionReset(t, all[4])).toEqual({ follows: false, differs: false });
  });

  it('gives each question a line of its answer, and the walkthrough’s draft and the DM’s own answers', () => {
    const t = table();
    expect(questionLine(t, 'outcomes')).toBe('Apply damage when an attack hits: On · Instant death: Off');
    const draft = draftFor(t, 'bookkeeping');
    expect(draft).toEqual({ 'r/initiative': true, 'r/damage': false, 'r/massive': false, 'r/seconds': 0, 'r/edition': '2024' });
    expect(questionLine(t, 'outcomes', draft)).toBe('Apply damage when an attack hits: Off · Instant death: Off');
    expect(ownAnswers(t, 'bookkeeping', draft)).toEqual({});
    // the DM keeps the reaction clock, and plays the 2014 rules
    const mine = { ...draft, 'r/seconds': 45, 'r/edition': '2014' };
    expect(ownAnswers(t, 'bookkeeping', mine)).toEqual({ 'r/seconds': 45, 'r/edition': '2014' });
    // a different level picked afterwards: its values over the draft, a rules option kept
    expect(draftFor(t, 'assisted', mine)).toMatchObject({ 'r/seconds': 30, 'r/damage': true, 'r/edition': '2014' });
  });

  it('reads what the players are told, and keys their having seen it by table, player and level', () => {
    expect(summaryOf({ table: { title: 'Bookkeeping', lines: ['a'], answers: [], house_rules: '' } })?.title).toBe('Bookkeeping');
    expect(summaryOf({})).toBeNull();
    expect(summaryOf({ table: { title: 'x' } })).toBeNull();
    expect(summarySeenKey('c1', 'pl_1', 'bookkeeping')).toBe('hexmap.table-runs/c1/pl_1/bookkeeping');
    expect(summarySeenKey('c1', 'pl_1', 'assisted')).not.toBe(summarySeenKey('c1', 'pl_1', 'bookkeeping'));
    expect(noticeWords('players')).toBe('players notice');
    expect(noticeWords('')).toBe('');
  });
});
