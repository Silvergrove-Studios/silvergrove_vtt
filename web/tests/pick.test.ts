import { describe, expect, it } from 'vitest';
import { Grid } from '../src/lib/grid';
import {
  DEAD_WORDS,
  NOTHING_IN_SIGHT,
  moveTo,
  moveWords,
  offersNoTarget,
  onBattleMap,
  pickChoices,
  pickCount,
  pickEach,
  pickTarget,
  pickWords,
  pickables,
  pickedWords,
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
    // Brakka is behind a wall: on Wren's map (the party always is), not in her sight
    const sees = (p: { x: number; y: number }) => p.x < 7;
    const list = pickChoices(toks, attack, { sees });
    expect(list.map((c) => c.target)).toEqual(['token:g1', 'token:g2']);
    expect(list[0]).toEqual({ target: 'token:g1', name: 'Goblin Warrior', label: 'GW1', party: false, hidden: false });
    // in sight, a friend is listed and says so; the DM's list has the hidden too
    expect(pickChoices(toks, attack).find((c) => c.target === 'token:br')?.party).toBe(true);
    expect(pickChoices(toks, attack, { gm: true }).map((c) => c.target)).toEqual(['token:g1', 'token:gb', 'token:g2', 'token:br']);
    // no creature in sight but a friend behind a wall: nothing in sight (a playtest's cleric, outside the chapel)
    expect(pickWords(attack, [wren, brakka], sees)).toBe(NOTHING_IN_SIGHT);
    expect(pickWords(attack, [wren, brakka])).toBe('Attack: tap a creature on the map');
    // a pick of a space or an area lists no creatures
    expect(pickChoices(toks, { pick: 'area', ctx: { actor: 'wren' } })).toEqual([]);
    // the one chosen, in words
    const name = (t: string) => toks.find((x) => `token:${x.id}` === t)?.name ?? '?';
    expect(pickedWords(attack, ['token:g1'], name)).toBe('Attack → Goblin Warrior');
    expect(pickedWords(attack, [], name)).toBe('');
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
