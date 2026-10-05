import { describe, expect, it } from 'vitest';
import { asksAbout, tapAction, tapIntent } from '../src/lib/tap';

// The rulesets' actions as a screen's view has them ({ plugin: { name: spec } }).
const actions = {
  srd5e: { attack: { label: 'Attack', target: 'token' }, known: { label: 'What we know', target: 'token', tap: 'creature' } },
  extras: { other: { label: 'Other', tap: 'thing' } },
};
const goblin = { id: 't_g1', name: 'a creature', actor: 'a_creature_k3f9q2', pos: [5.5, 5.5] };
const wren = { id: 't_wren', name: 'Wren', actor: 'a_wren', owner: 'pl_ana' };
const hand = { id: 't_hand', name: 'Arcane Hand', actor: 'a_hand', tags: ['object'] };
const pillar = { id: 't_pillar', name: 'Pillar' };

describe('a tap on a creature’s token', () => {
  it('asks the ruleset that answers it, by the action it registers', () => {
    expect(tapAction(actions)).toEqual({ plugin: 'srd5e', action: 'known' });
    expect(tapAction(actions, 'thing')).toEqual({ plugin: 'extras', action: 'other' });
    expect(tapAction({ srd5e: { attack: { label: 'Attack' } } })).toBeNull();
    expect(tapAction(undefined)).toBeNull();
  });
  it('about a creature no player owns, not the party’s own nor a thing', () => {
    expect(asksAbout(goblin)).toBe(true);
    expect(asksAbout(wren)).toBe(false);
    expect(asksAbout(hand)).toBe(false);
    expect(asksAbout(pillar)).toBe(false);
  });
  it('aimed at the token tapped, on the scene shown', () => {
    expect(tapIntent(actions, goblin, 'sc_1')).toEqual({ kind: 'action', plugin: 'srd5e', action: 'known', ctx: { target: 'token:t_g1', scene: 'sc_1' } });
    expect(tapIntent(actions, wren, 'sc_1')).toBeNull();
    expect(tapIntent({}, goblin, 'sc_1')).toBeNull();
  });
});
