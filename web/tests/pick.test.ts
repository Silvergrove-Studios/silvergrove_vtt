import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import {
  DEAD_WORDS,
  NONE_TO_CHOOSE,
  NOTHING_IN_SIGHT,
  WHY_DARK,
  WHY_DEAD,
  WHY_WALL,
  blocksMove,
  feetBetween,
  followedToken,
  moveTo,
  moveWords,
  offersNoTarget,
  onBattleMap,
  pickChoices,
  pickCount,
  pickEach,
  pickNeedsSight,
  pickRange,
  pickStoppedByWalls,
  pickTarget,
  pickWords,
  pickables,
  pickedWords,
  sightOf,
  tappedTheDead,
  togglePicked,
  unpick,
  withNoTarget,
  withTarget,
} from '../src/lib/map/pick';
import { FAN_SIZE, layout, tokenAt } from '../src/lib/map/render';

describe('picking a target', () => {
  const grid = new Grid({ columns: 10, rows: 8 });
  const tokens = [
    { id: 'a', pos: [grid.center({ q: 1, r: 1 }).x, grid.center({ q: 1, r: 1 }).y], actor: 'hero' },
    { id: 'g', pos: [grid.center({ q: 4, r: 2 }).x, grid.center({ q: 4, r: 2 }).y], hidden: true },
  ];
  it('picks a token under the point, but a player never picks a hidden one', () => {
    const at = { x: tokens[0].pos[0] + 0.1, y: tokens[0].pos[1] };
    expect(pickTarget(grid, tokens, { pick: 'token' }, at, false)).toBe('token:a');
    const g = { x: tokens[1].pos[0], y: tokens[1].pos[1] };
    expect(pickTarget(grid, tokens, { pick: 'token' }, g, false)).toBeNull();
    expect(pickTarget(grid, tokens, { pick: 'token' }, g, true)).toBe('token:g');
  });
  it('picks cells in bounds and aims areas from the actor’s token', () => {
    expect(pickTarget(grid, tokens, { pick: 'cell' }, grid.center({ q: 3, r: 3 }), false)).toBe('3,3');
    expect(pickTarget(grid, tokens, { pick: 'cell' }, { x: -5, y: -5 }, false)).toBeNull();
    const cone = pickTarget(grid, tokens, { pick: 'area', area: { shape: 'cone', length: 3 }, ctx: { actor: 'hero' } }, { x: tokens[0].pos[0] + 2, y: tokens[0].pos[1] }, false) as Record<string, unknown>;
    expect(cone.at).toBe('token:a');
    expect(Math.round(Number(cone.direction))).toBe(0);
  });
  it('sends the intent with its target', () => {
    const sent = withTarget({ kind: 'action', pick: 'token', label: 'Attack', ctx: { actor: 'hero' } }, 'token:g', 's1');
    expect(sent).toEqual({ kind: 'action', ctx: { actor: 'hero', target: 'token:g', scene: 's1' } });
  });
  it('fans out tokens on one cell, and a tap on each picks that one', () => {
    const c = grid.center({ q: 5, r: 5 });
    const stack = [
      { id: 'ada', pos: [c.x, c.y], owner: 'pl_a' },
      { id: 'gob', pos: [c.x, c.y], actor: 'a_g' },
    ];
    const placed = layout(stack, grid);
    const a = placed.get('ada')!;
    const b = placed.get('gob')!;
    expect(a.k).toBe(FAN_SIZE);
    expect(Math.hypot(a.pos.x - b.pos.x, a.pos.y - b.pos.y)).toBeCloseTo(0.44);
    for (const t of stack) {
      // where it is drawn, with a finger's reach
      const hit = tokenAt(stack, placed.get(t.id)!.pos, 0.3, placed);
      expect(hit?.id).toBe(t.id);
      // (the pick was re-found by position: the last one on the cell, whichever was tapped)
      expect(pickTarget(grid, stack, { pick: 'token' }, { x: c.x, y: c.y }, false, hit)).toBe(`token:${t.id}`);
    }
    // three or four round a circle; one alone, or a large one, stays where it stands
    const lone = grid.center({ q: 1, r: 1 });
    const more = [...stack, { id: 'jin', pos: [c.x, c.y], owner: 'pl_j' }, { id: 'lone', pos: [lone.x, lone.y] }, { id: 'ogre', pos: [c.x, c.y], size: 2 }];
    const p3 = layout(more, grid);
    const three = ['ada', 'gob', 'jin'].map((id) => p3.get(id)!.pos);
    for (let i = 0; i < 3; i++) for (let j = i + 1; j < 3; j++) expect(Math.hypot(three[i].x - three[j].x, three[i].y - three[j].y)).toBeGreaterThan(0.3);
    expect(p3.get('lone')).toEqual({ pos: lone, k: 1 });
    expect(p3.get('ogre')).toEqual({ pos: c, k: 1 });
    for (const id of ['ada', 'gob', 'jin']) expect(tokenAt(more.filter((t) => t.id !== 'ogre'), p3.get(id)!.pos, 0.25, p3)?.id).toBe(id);
    // a token being dragged is drawn where the pointer is: the others close up
    expect(layout(stack, grid, 'gob').get('ada')).toEqual({ pos: c, k: 1 });
  });

  it('moves a token armed with a tap to the centre of the cell tapped next', () => {
    const grace = { id: 'g', name: 'Grace', pos: [grid.center({ q: 1, r: 1 }).x, grid.center({ q: 1, r: 1 }).y] };
    expect(moveWords(grace)).toBe('Move Grace: tap where to go');
    const target = grid.center({ q: 5, r: 1 });
    // anywhere in the cell: its centre, four spaces off
    expect(moveTo(grid, grace, { x: target.x + 0.2, y: target.y - 0.1 })).toEqual({ pos: [target.x, target.y], spaces: 4 });
    // on a map drawn with no grid, where it was tapped
    expect(moveTo(grid, grace, { x: target.x + 0.2, y: target.y }, false)?.pos).toEqual([target.x + 0.2, target.y]);
    // off the map: nowhere
    expect(moveTo(grid, grace, { x: -3, y: -3 })).toBeNull();
    // on squares, a diagonal is a step
    const squares = new Grid({ shape: 'square', columns: 10, rows: 8 });
    expect(moveTo(squares, { pos: [0.5, 0.5] }, { x: 3.5, y: 2.5 })).toEqual({ pos: [3.5, 2.5], spaces: 3 });
  });

  // (the owner: her dancing lights "should be able to be on the same square as a player")
  it('moves a thing onto anyone\'s space, and a creature onto a thing\'s: only a creature stops a creature', () => {
    const wren = { id: 'w', name: 'Wren', pos: [1, 1], owner: 'pl_1', actor: 'a_w' };
    const light = { id: 'l', name: 'Light 1', pos: [2, 1], owner: 'pl_1', tags: ['object'] };
    const gob = { id: 'g', pos: [3, 1], actor: 'a_g' };
    expect(blocksMove(light, wren)).toBe(false);
    expect(blocksMove(light, gob)).toBe(false);
    expect(blocksMove(wren, light)).toBe(false);
    expect(blocksMove(wren, gob)).toBe(true);
    expect(blocksMove(gob, wren)).toBe(true);
    // a thing the DM put down with no stat block, and a marker, stop nobody
    expect(blocksMove(wren, { id: 'cart', pos: [4, 1], tags: ['thing'] })).toBe(false);
    // the map keeps her character in view, not a light she sent off
    expect(followedToken([light, wren, gob], 'pl_1')).toBe('w');
    expect(followedToken([light, gob], 'pl_1')).toBe('l');
    expect(followedToken([gob, { id: 'star', pos: [0, 0], tags: ['party'] }], 'pl_1')).toBe('star');
    expect(followedToken([light], '')).toBe('');
  });

  it('never picks a thing on the map: the creature under it, or nothing', () => {
    const c = grid.center({ q: 6, r: 4 });
    const gob = { id: 'g', name: 'Goblin', pos: [c.x, c.y], actor: 'a_g' };
    const sphere = { id: 's', name: 'Flaming Sphere', pos: [c.x, c.y], size: 1, owner: 'pl_1', tags: ['object'] };
    const stack = [gob, sphere];
    const placed = layout(stack, grid);
    const hit = tokenAt(stack, placed.get('s')!.pos, 0, placed);
    expect(hit?.id).toBe('s');
    // a tap on the sphere over the goblin picks the goblin
    expect(pickTarget(grid, stack, { pick: 'token' }, placed.get('s')!.pos, false, hit)).toBe('token:g');
    // a sphere alone picks nothing
    expect(pickTarget(grid, [sphere], { pick: 'token' }, c, false, sphere)).toBeNull();
    // nor is it listed to choose by name
    const choices = pickChoices(stack, { pick: 'token', ctx: {} });
    expect(choices.map((x) => x.target)).toEqual(['token:g']);
    expect(pickables(stack, { pick: 'token', ctx: {} }, true).map((t) => t.id)).toEqual(['g']);
  });

  // (the owner: "things with hit points ... need to become full tokens with accessible stat blocks")
  it('picks a thing with statistics of its own: an Arcane Hand, an Unseen Servant', () => {
    const c = grid.center({ q: 6, r: 4 });
    const hand = { id: 'h', name: 'Arcane Hand', pos: [c.x, c.y], size: 2, owner: 'pl_1', actor: 'a_hand', tags: ['object'] };
    const light = { id: 'l', name: 'Light 1', pos: [c.x + 2, c.y], owner: 'pl_1', tags: ['object'] };
    expect(pickTarget(grid, [hand, light], { pick: 'token' }, c, false, hand)).toBe('token:h');
    expect(pickables([hand, light], { pick: 'token', ctx: {} }, true).map((t) => t.id)).toEqual(['h']);
    expect(pickChoices([hand, light], { pick: 'token', ctx: {} }).map((x) => x.target)).toEqual(['token:h']);
    // it still shares a space with anyone, as a thing does
    expect(blocksMove(hand, { id: 'w', pos: [c.x, c.y], actor: 'a_w' })).toBe(false);
  });

  it('never picks a hidden creature for a player, whatever was hit', () => {
    const g = { id: 'g', pos: tokens[1].pos, hidden: true };
    expect(pickTarget(grid, tokens, { pick: 'token' }, { x: g.pos[0], y: g.pos[1] }, false, g)).toBeNull();
    expect(pickTarget(grid, tokens, { pick: 'token' }, { x: g.pos[0], y: g.pos[1] }, true, g)).toBe('token:g');
  });

  it('picks several creatures for a spell that takes them (Bless: up to three)', () => {
    const bless = { kind: 'action', pick: 'token', picks: 3, label: 'Cast', ctx: { actor: 'hero' } };
    expect(pickCount(bless)).toBe(3);
    expect(pickCount({ pick: 'cell', picks: 3 })).toBe(1);
    expect(pickCount({ pick: 'token', picks: '' })).toBe(1);
    expect(pickWords(bless)).toBe('Cast: tap up to 3 creatures on the map, then Done');
    let picked = togglePicked([], 'token:a', 3);
    picked = togglePicked(picked, 'token:b', 3);
    picked = togglePicked(picked, 'token:c', 3);
    expect(togglePicked(picked, 'token:d', 3)).toEqual(['token:a', 'token:b', 'token:c']);
    expect(togglePicked(picked, 'token:b', 3)).toEqual(['token:a', 'token:c']);
    expect(withTarget(bless, picked, 's1')).toEqual({ kind: 'action', ctx: { actor: 'hero', target: ['token:a', 'token:b', 'token:c'], scene: 's1' } });
  });
  it('says so when there is nothing in sight to pick (a playtest asked players to tap a creature on a black map)', () => {
    const hero = { id: 'h', actor: 'hero' };
    const marker = { id: 'party', tags: ['party'] };
    const place = { id: 'inn', tags: ['place'] };
    const lurker = { id: 'g', hidden: true };
    const attack = { kind: 'action', pick: 'token', label: 'Attack', ctx: { actor: 'hero' } };
    expect(pickables([hero, marker, place, lurker], attack)).toEqual([]);
    expect(pickables([hero, marker, place, lurker], attack, true).map((t) => t.id)).toEqual(['g']);
    expect(pickWords(attack, [hero, marker, place])).toBe(NOTHING_IN_SIGHT);
    expect(NOTHING_IN_SIGHT).toBe('Nothing in sight: walls or darkness block your view. Move, or ask the DM.');
    // a creature in sight (a friend's token counts), or a pick that isn't of a creature
    expect(pickWords(attack, [hero, { id: 'ally', owner: 'pl_2' }])).toBe('Attack: tap a creature on the map');
    expect(pickWords({ pick: 'cell', label: 'Move' }, [hero])).toBe('Move: tap a space on the map');
    // the DM's banner, with no tokens given, is as it was
    expect(pickWords(attack)).toBe('Attack: tap a creature on the map');
  });

  // (a playtest's Sacred Flame went to a dead goblin whose X sat beside the living Warden)
  it('never picks the dead, unless the pick brings them back', () => {
    const at = (q: number, r: number) => [grid.center({ q, r }).x, grid.center({ q, r }).y];
    const nadia = { id: 'n', actor: 'nadia', owner: 'pl_n', pos: at(1, 1) };
    const warden = { id: 'w', name: 'Chapel Warden', label: 'CW', actor: 'a_w', pos: at(4, 2) };
    const corpse = { id: 'g', name: 'Goblin Warrior', label: 'GW1', actor: 'a_g', pos: at(4, 2), tags: ['fey', 'dead'] };
    const toks = [nadia, warden, corpse];
    const flame = { kind: 'action', pick: 'token', label: 'Cast', ctx: { actor: 'nadia' } };
    expect(pickables(toks, flame).map((t) => t.id)).toEqual(['w']);
    // the corpse tapped, the Warden under the tap too: the Warden
    const p = { x: warden.pos[0] + 0.1, y: warden.pos[1] };
    expect(pickTarget(grid, toks, flame, p, false, corpse)).toBe('token:w');
    // the corpse alone under the tap: nothing, and the page says it's dead
    const alone = [nadia, { ...corpse, pos: at(7, 5) }];
    expect(pickTarget(grid, alone, flame, { x: alone[1].pos[0], y: alone[1].pos[1] }, false, alone[1])).toBeNull();
    expect(tappedTheDead(alone[1], flame) && !tappedTheDead(warden, flame)).toBe(true);
    expect(DEAD_WORDS).toBe('That one’s dead');
    // Revivify's pick says it takes the dead
    const revivify = { ...flame, dead: true };
    expect(pickables(toks, revivify).map((t) => t.id)).toEqual(['w', 'g']);
    expect(pickTarget(grid, alone, revivify, { x: alone[1].pos[0], y: alone[1].pos[1] }, false, alone[1])).toBe('token:g');
    expect(tappedTheDead(corpse, revivify)).toBe(false);
    // a thing the DM put down with no stat block (a cart) is no one's target either
    const cart = { id: 'c', name: 'Vask’s cart', label: 'VC', pos: at(5, 5), tags: ['thing'] };
    expect(pickables([...toks, cart], flame).map((t) => t.id)).toEqual(['w']);
  });

  // (a screen reader can't tap a canvas, and a playtest's agents fought line of sight far harder than people)
  it('lists the creatures in the picker’s sight by name and map label, nearest first', () => {
    const wren = { id: 'wr', name: 'Wren', label: 'WR', actor: 'wren', owner: 'pl_a', pos: [1, 1] };
    const brakka = { id: 'br', name: 'Brakka', label: 'BR', actor: 'brakka', owner: 'pl_b', pos: [10, 6] };
    const far = { id: 'g2', name: 'Goblin Warrior 2', label: 'GW2', actor: 'a_g2', pos: [5, 1] };
    const near = { id: 'g1', name: 'Goblin Warrior', label: 'GW1', actor: 'a_g1', pos: [2, 1] };
    const boss = { id: 'gb', name: 'Goblin Boss', label: 'GB', actor: 'a_gb', pos: [3, 3], hidden: true };
    const attack = { kind: 'action', pick: 'token', label: 'Attack', ctx: { actor: 'wren' } };
    const toks = [wren, brakka, far, near, boss];
    // Brakka is behind a wall: on Wren's map (the party always is), not in her
    // sight: listed after those she may take, with why (the boss is the DM's hidden)
    const sees = (p: { x: number; y: number }) => p.x < 7;
    const list = pickChoices(toks, attack, { sees });
    expect(list.map((c) => [c.target, c.why])).toEqual([
      ['token:g1', ''],
      ['token:g2', ''],
      ['token:br', WHY_WALL],
    ]);
    expect(list[0]).toEqual({ target: 'token:g1', name: 'Goblin Warrior', label: 'GW1', party: false, hidden: false, why: '' });
    // in sight, a friend is listed and says so, after the rest however near; the DM's list has the hidden too
    const close = { ...brakka, pos: [1.5, 1] };
    expect(pickChoices([wren, close, far, near], attack).map((c) => [c.target, c.party])).toEqual([
      ['token:g1', false],
      ['token:g2', false],
      ['token:br', true],
    ]);
    expect(pickChoices(toks, attack, { gm: true }).map((c) => c.target)).toEqual(['token:g1', 'token:gb', 'token:g2', 'token:br']);
    // no creature in sight but a friend behind a wall: none to choose, why beside
    // him; nobody at all: nothing in sight (a playtest's cleric, outside the chapel)
    expect(pickWords(attack, [wren, brakka], sees)).toBe(NONE_TO_CHOOSE);
    expect(pickWords(attack, [wren], sees)).toBe(NOTHING_IN_SIGHT);
    expect(pickWords(attack, [wren, brakka])).toBe('Attack: tap a creature on the map');
    // a pick of a space or an area lists no creatures
    expect(pickChoices(toks, { pick: 'area', ctx: { actor: 'wren' } })).toEqual([]);
    // the one chosen, in words
    const name = (t: string) => toks.find((x) => `token:${x.id}` === t)?.name ?? '?';
    expect(pickedWords(attack, ['token:g1'], name)).toBe('Attack → Goblin Warrior');
    expect(pickedWords(attack, [], name)).toBe('');
  });

  // (a playtest's Haste listed the Gargoyle, the Mage and Yuki, and not Marcus: a
  // spell for the party lists the party first, its caster among them)
  it('lists the party first, the caster too, for a spell that is for them', () => {
    const wren = { id: 'wr', name: 'Wren', label: 'WR', actor: 'wren', owner: 'pl_a', pos: [1, 1] };
    const brakka = { id: 'br', name: 'Brakka', label: 'BR', actor: 'brakka', owner: 'pl_b', pos: [4, 1] };
    const near = { id: 'g1', name: 'Goblin Warrior', label: 'GW1', actor: 'a_g1', pos: [2, 1] };
    const haste = { kind: 'action', pick: 'token', friendly: true, label: 'Cast', ctx: { actor: 'wren', spell: 'haste' } };
    expect(pickChoices([wren, brakka, near], haste).map((c) => c.target)).toEqual(['token:wr', 'token:br', 'token:g1']);
    // out of the caster's sight (a wall between), a friend isn't one "that you can
    // see": listed last, saying so; the caster always may be
    const sees = (p: { x: number; y: number }) => p.x < 3;
    expect(pickChoices([wren, brakka, near], haste, { sees }).map((c) => [c.target, c.why])).toEqual([
      ['token:wr', ''],
      ['token:g1', ''],
      ['token:br', WHY_WALL],
    ]);
    // an attack still lists the foes first, never its attacker
    const attack = { kind: 'action', pick: 'token', label: 'Attack', ctx: { actor: 'wren' } };
    expect(pickChoices([wren, brakka, near], attack).map((c) => c.target)).toEqual(['token:g1', 'token:br']);
    // and the flag doesn't go to the table
    expect(withTarget(haste, 'token:br', 's1')).toEqual({ kind: 'action', ctx: { actor: 'wren', spell: 'haste', target: 'token:br', scene: 's1' } });
  });

  // (the level-12 playtest's Haste: the party's fighter, drawn on the map, was
  // behind a wall from the caster and not in the list, and nothing said why)
  it('lists those it can’t take after those it can, each with why: a wall, too dark to see, out of range, dead', () => {
    const sq = new Grid({ shape: 'square', columns: 30, rows: 30, distance: 5, units: 'ft' });
    const at = (q: number, r: number) => [sq.center({ q, r }).x, sq.center({ q, r }).y];
    const yuki = { id: 'yu', name: 'Yuki', label: 'YU', actor: 'yuki', owner: 'pl_a', pos: at(1, 1) };
    const marcus = { id: 'mv', name: 'Marcus Vell', label: 'MV', actor: 'marcus', owner: 'pl_b', pos: at(4, 1) };
    const priya = { id: 'pr', name: 'Priya', label: 'PR', actor: 'priya', owner: 'pl_c', pos: at(1, 3) };
    const far = { id: 'sam', name: 'Sam', label: 'SA', actor: 'sam', owner: 'pl_d', pos: at(1, 29) };
    const fallen = { id: 'g1', name: 'Goblin Warrior', label: 'GW1', actor: 'a_g1', pos: at(2, 1), tags: ['dead'] };
    const toks = [yuki, marcus, priya, far, fallen];
    // Marcus behind a wall (black), Priya in the dark (navy), the rest in sight
    const sight = (p: { x: number; y: number }) => (p.x > 3 && p.y < 3 ? 'walls' : p.y > 3 && p.y < 5 ? 'dark' : 'seen') as 'seen' | 'dark' | 'walls';
    const haste = { kind: 'action', pick: 'token', friendly: true, label: 'Cast', range: 30, sight: true, ctx: { actor: 'yuki', spell: 'haste' } };
    const list = pickChoices(toks, haste, { sight, grid: sq });
    // (the party first, the caster among them, nearest first; then those it can't take, as near)
    expect(list.map((c) => [c.name, c.why])).toEqual([
      ['Yuki', ''],
      ['Priya', WHY_DARK],
      ['Marcus Vell', WHY_WALL],
      ['Sam', 'out of range (140 ft)'],
      ['Goblin Warrior', WHY_DEAD],
    ]);
    expect(WHY_WALL).toBe('can’t see: a wall is in the way');
    expect(WHY_DARK).toBe('too dark to see');
    // one that may go at a creature unseen (an attack: at Disadvantage; a touch):
    // the dark is no bar, a wall still is (total cover: "can't be targeted directly")
    const touch = { ...haste, range: 5, sight: false };
    expect(pickChoices(toks, touch, { sight, grid: sq }).map((c) => [c.name, c.why])).toEqual([
      ['Yuki', ''],
      ['Priya', 'out of range (10 ft)'],
      ['Marcus Vell', WHY_WALL],
      ['Sam', 'out of range (140 ft)'],
      ['Goblin Warrior', WHY_DEAD],
    ]);
    // in reach, the dark is no bar to it
    const beside = { ...priya, pos: at(1, 2) };
    const dark = (p: { x: number; y: number }) => (p.y > 2 && p.y < 3 ? 'dark' : 'seen') as 'seen' | 'dark' | 'walls';
    expect(pickChoices([yuki, beside], touch, { sight: dark, grid: sq }).map((c) => c.why)).toEqual(['', '']);
    expect(pickChoices([yuki, beside], haste, { sight: dark, grid: sq }).map((c) => c.why)).toEqual(['', WHY_DARK]);
    // a weapon's reach, range and long range: the farthest counts
    expect(pickRange({ range: [5, 80, 320] })).toBe(320);
    expect(pickRange({ range: [5, null, 0] })).toBe(5);
    expect(pickRange({ range: 30 })).toBe(30);
    expect(pickRange({})).toBe(0);
    expect(pickNeedsSight({})).toBe(true);
    expect(pickNeedsSight({ sight: false })).toBe(false);
    // a pick that takes the dead (Revivify's) doesn't call them dead
    const revivify = { ...touch, dead: true, range: 0 };
    expect(pickChoices([yuki, fallen], revivify, { sight, grid: sq }).map((c) => c.why)).toEqual(['', '']);
    // how far, as the rules count it: steps of a square (diagonals too), and a big one's edge
    expect(feetBetween(sq, yuki, marcus)).toBe(15);
    expect(feetBetween(sq, yuki, { pos: at(4, 4) })).toBe(15);
    const ogre = { pos: [sq.center({ q: 6, r: 1 }).x + 0.5, sq.center({ q: 6, r: 1 }).y + 0.5], size: 2 };
    expect(feetBetween(sq, yuki, ogre)).toBe(25);
    // with none it may take, the words say to look beside each name
    expect(pickWords(haste, [yuki, marcus], { sight, grid: sq })).toBe('Cast: tap a creature on the map');
    expect(pickWords({ ...haste, friendly: false }, [yuki, marcus], { sight, grid: sq })).toBe(NONE_TO_CHOOSE);
  });

  // (the DM's checks: a table that doesn't check line of sight or range sends
  // picks with `sight: false, walls: false` and no `range`: nothing is barred
  // for them, and what's dead still is)
  it('bars nothing for a wall, the dark or the distance where the table checks neither', () => {
    const sq = new Grid({ shape: 'square', columns: 30, rows: 30, distance: 5, units: 'ft' });
    const at = (q: number, r: number) => [sq.center({ q, r }).x, sq.center({ q, r }).y];
    const yuki = { id: 'yu', name: 'Yuki', label: 'YU', actor: 'yuki', owner: 'pl_a', pos: at(1, 1) };
    const marcus = { id: 'mv', name: 'Marcus Vell', label: 'MV', actor: 'marcus', owner: 'pl_b', pos: at(4, 1) };
    const priya = { id: 'pr', name: 'Priya', label: 'PR', actor: 'priya', owner: 'pl_c', pos: at(1, 3) };
    const far = { id: 'sam', name: 'Sam', label: 'SA', actor: 'sam', owner: 'pl_d', pos: at(1, 29) };
    const fallen = { id: 'g1', name: 'Goblin Warrior', label: 'GW1', actor: 'a_g1', pos: at(2, 1), tags: ['dead'] };
    const sight = (p: { x: number; y: number }) => (p.x > 3 && p.y < 3 ? 'walls' : p.y > 3 && p.y < 5 ? 'dark' : 'seen') as 'seen' | 'dark' | 'walls';
    const haste = { kind: 'action', pick: 'token', friendly: true, label: 'Cast', sight: false, walls: false, ctx: { actor: 'yuki', spell: 'haste' } };
    expect(pickStoppedByWalls(haste)).toBe(false);
    expect(pickStoppedByWalls({})).toBe(true);
    expect(pickChoices([yuki, marcus, priya, far, fallen], haste, { sight, grid: sq }).map((c) => [c.name, c.why])).toEqual([
      ['Yuki', ''],
      ['Priya', ''],
      ['Marcus Vell', ''],
      ['Sam', ''],
      ['Goblin Warrior', WHY_DEAD],
    ]);
    // and the flag goes no further than the pick
    expect(withTarget(haste, 'token:mv', 's1')).toEqual({ kind: 'action', ctx: { actor: 'yuki', spell: 'haste', target: 'token:mv', scene: 's1' } });
  });

  // the fog as the table sent it: in sight; in the line of sight but dark (navy); out of it (black)
  it('reads where a place stands for a player’s eyes from the scene’s fog', () => {
    const square = (x: number, y: number, s = 2) => [
      [x, y],
      [x + s, y],
      [x + s, y + s],
      [x, y + s],
    ];
    const scene = { fog: true, visible: [square(0, 0)], los: [square(0, 0, 4)] };
    const s = sightOf(scene)!;
    expect([s({ x: 1, y: 1 }), s({ x: 3, y: 3 }), s({ x: 6, y: 6 })]).toEqual(['seen', 'dark', 'walls']);
    expect(sightOf({ fog: false })).toBeUndefined();
    // by day there is no line of sight sent: out of sight is walls
    expect(sightOf({ fog: true, visible: [square(0, 0)], los: [] })!({ x: 3, y: 3 })).toBe('walls');
  });

  // (the owner: people play theatre of the mind with no tokens all the time, and still need to see the rolls)
  it('sends an intent with no target, to be rolled and nothing applied', () => {
    const cast = { kind: 'action', plugin: 'srd5e', action: 'cast', pick: 'token', picks: 3, each: 'dart', label: 'Cast', ctx: { actor: 'hero', spell: 'magic-missile' } };
    expect(withNoTarget(cast, 's1')).toEqual({ kind: 'action', plugin: 'srd5e', action: 'cast', ctx: { actor: 'hero', spell: 'magic-missile', no_target: true, scene: 's1' } });
    // no scene on the screen: none said
    expect(withNoTarget({ kind: 'action', pick: 'token', ctx: { actor: 'hero', target: 'token:x' } }, '')).toEqual({ kind: 'action', ctx: { actor: 'hero', no_target: true } });
    // offered for a creature or an area; a space to put something on needs the map
    expect([offersNoTarget({ pick: 'token' }), offersNoTarget({ pick: 'area' }), offersNoTarget({ pick: 'cell' })]).toEqual([true, true, false]);
    // a battle map is somewhere to pick; the region, or nothing on the table, is not
    expect(onBattleMap({ id: 's1', role: 'battle' }) && onBattleMap({ id: 's1' })).toBe(true);
    expect(onBattleMap({ id: 's2', role: 'regional' }) || onBattleMap({})).toBe(false);
  });

  // (a playtest's player read "(1 of up to 3)" as tapping the same goblin three times)
  it('picks Magic Missile’s darts as darts: the same creature again for another', () => {
    const mm = { kind: 'action', pick: 'token', picks: 3, each: 'dart', label: 'Cast', ctx: { actor: 'hero' } };
    expect(pickEach(mm)).toBe('dart');
    expect(pickEach({ pick: 'token', picks: 3, label: 'Cast' })).toBe('');
    expect(pickEach({ pick: 'token', each: 'dart' })).toBe('');
    expect(pickWords(mm)).toBe('3 darts: tap a creature for each dart (the same one again for another), then Done');
    let darts = togglePicked([], 'token:g', 3, true);
    darts = togglePicked(darts, 'token:g', 3, true);
    darts = togglePicked(darts, 'token:b', 3, true);
    expect(darts).toEqual(['token:g', 'token:g', 'token:b']);
    expect(togglePicked(darts, 'token:b', 3, true)).toEqual(darts);
    const name = (t: string) => ({ 'token:g': 'Goblin', 'token:b': 'Boss' })[t] ?? '?';
    expect(pickedWords(mm, darts, name)).toBe('Goblin ×2, Boss: 3 of 3 darts');
    darts = unpick(darts, 'token:g');
    expect(darts).toEqual(['token:g', 'token:b']);
    expect(pickedWords(mm, darts, name)).toBe('Goblin, Boss: 2 of 3 darts; the rest go to those chosen');
    expect(withTarget(mm, darts, 's1')).toEqual({ kind: 'action', ctx: { actor: 'hero', target: ['token:g', 'token:b'], scene: 's1' } });
    // Bless: each a creature of its own, counted as before
    const bless = { pick: 'token', picks: 3, label: 'Cast' };
    expect(pickedWords(bless, ['token:g'], name)).toBe('Cast → Goblin (1 of up to 3)');
  });
});
