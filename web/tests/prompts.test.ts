import { describe, expect, it } from 'vitest';
import { frontPrompt, pillText, secondsLeft, waitingOn, waitingText } from '../src/lib/prompts';

describe('frontPrompt', () => {
  it("a reaction's card first, then the newest by when it opened (ids are random)", () => {
    const roll = { id: 'p_ff', opened: 10, form: { title: 'Perception check' } };
    const older = { id: 'p_zz', opened: 4, form: { title: 'Take the dare?' } };
    const shield = { id: 'p_00', opened: 7, urgent: true, form: { title: 'The goblin hits you. Your reaction?' } };
    expect(frontPrompt([roll, older])).toBe(roll);
    expect(frontPrompt([older, roll])).toBe(roll);
    expect(frontPrompt([roll, shield, older])).toBe(shield);
    expect(frontPrompt([])).toBeNull();
  });
});

describe('pillText for a reaction', () => {
  it('says it is a reaction, and what happened', () => {
    const card = { id: 'p1', urgent: true, form: { title: 'The Goblin 1 hits you (Scimitar): 14 against your AC 12. Your reaction?', choices: [{ id: 'shield' }, { id: 'none' }] } };
    expect(pillText([card])).toBe('Your reaction: The Goblin 1 hits you (Scimitar): 14 against your AC 12 ›');
    expect(pillText([{ id: 'p0', opened: 99, form: { title: 'Roll' } }, card])).toBe('Your reaction: The Goblin 1 hits you (Scimitar): 14 against your AC 12 (+1 more) ›');
  });
});

describe('secondsLeft', () => {
  it('counts down from what the table sent, as the page sees time pass', () => {
    expect(secondsLeft({ left: 30 }, 1000, 1000)).toBe(30);
    expect(secondsLeft({ left: 30 }, 1000, 8200)).toBe(23);
    expect(secondsLeft({ left: 2.5 }, 0, 0)).toBe(3);
    expect(secondsLeft({ left: 5 }, 0, 60000)).toBe(0);
  });
  it('nothing counts on a card that waits for its answer', () => {
    expect(secondsLeft({}, 0, 0)).toBeNull();
    expect(secondsLeft({ left: null }, 0, 0)).toBeNull();
    expect(secondsLeft(null, 0, 0)).toBeNull();
  });
});

describe('waitingText and waitingOn', () => {
  const ana = { id: 'p1', to: 'pl_ana', who: 'Ana', what: 'a reaction (Sela)', left: 23 };
  const dm = { id: 'p2', to: 'gm', who: 'the DM', what: 'a reaction' };
  it('says whom the table waits on, for what, and how long', () => {
    expect(waitingText(ana, 'pl_ben', 23)).toBe('Waiting on Ana: a reaction (Sela) · 23 s');
    expect(waitingText(ana, 'pl_ana', 23)).toBe('Waiting on you: a reaction (Sela) · 23 s');
    expect(waitingText(dm, 'pl_ana', null)).toBe('Waiting on the DM: a reaction');
    expect(waitingText(dm, '', null)).toBe('Waiting on the DM: a reaction');
  });
  it("leaves out a screen's own card: a player's is in front; the DM's own are asked of the DM", () => {
    expect(waitingOn([ana, dm], 'pl_ana', false)).toEqual([dm]);
    expect(waitingOn([ana, dm], 'pl_ben', false)).toEqual([ana, dm]);
    expect(waitingOn([ana, dm], '', true)).toEqual([ana]);
    expect(waitingOn(undefined, '', true)).toEqual([]);
  });
});
