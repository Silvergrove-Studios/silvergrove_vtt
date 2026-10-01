import { describe, expect, it } from 'vitest';
import { buttonAnswer, cardHeading, frontPrompt, pillText, secondsLeft, waitingOn, waitingText } from '../src/lib/prompts';

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

describe("a card's heading", () => {
  it("is the form's own (a hit's damage type, asked as it lands), else a reaction's or a question's", () => {
    const hit = { id: 'p2', urgent: true, form: { heading: 'Your hit', title: "Your hit with Dagger on the Goblin (17 against AC 15): Conjure Minor Elementals' extra 2d8 — Acid · Cold · Fire · Lightning" } };
    expect(cardHeading(hit)).toBe('Your hit');
    expect(cardHeading({ urgent: true, form: { title: 'x' } })).toBe('Your reaction');
    expect(cardHeading({ urgent: true, form: { title: 'x' } }, true)).toBe('A reaction');
    expect(cardHeading({ form: { title: 'x' } }, true)).toBe('The rules ask you');
    expect(cardHeading({ form: { title: 'x' } })).toBe('The DM asks');
    expect(pillText([hit])).toBe("Your hit: Your hit with Dagger on the Goblin (17 against AC 15): Conjure Minor Elementals' extra 2d8 — Acid · Cold · Fire · Lightning ›");
    // a spell's choice as it's cast: the rules', not the DM's
    const orb = { id: 'p3', form: { heading: 'Your choice', title: 'Chromatic Orb: the type of orb you create', choices: [{ id: 'fire' }, { id: 'cancel' }] } };
    expect(pillText([orb])).toBe('Your choice: Chromatic Orb: the type of orb you create ›');
  });
});

describe("a card's button answer", () => {
  it("is its fields' values and the button's id, not its default's other keys", () => {
    // a reaction's card: its default (what it answers when nobody does) says `late`
    expect(buttonAnswer([], { choice: 'none', late: true }, 'none')).toEqual({ choice: 'none' });
    expect(buttonAnswer([], { choice: 'none', late: true }, 'shield')).toEqual({ choice: 'shield' });
    // a hit's card with several choices: a field each, and its button
    const fields = [{ key: 'cme', type: 'choose' }, { key: 'divine_strike', type: 'choose' }];
    expect(buttonAnswer(fields, { choice: 'none', late: true, cme: 'cold', divine_strike: 'radiant' }, 'roll')).toEqual({ cme: 'cold', divine_strike: 'radiant', choice: 'roll' });
    // a field left as it was is still sent (Lay on Hands' amount, its default 0)
    expect(buttonAnswer([{ key: 'amount', type: 'int' }], { amount: 0 }, 'heal')).toEqual({ amount: 0, choice: 'heal' });
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
