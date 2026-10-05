import { describe, expect, it } from 'vitest';
import { cardDiceProblem, diceProblem, diceTotal, faceDone, faceOf, maxDigits, sidesOf, startingDice } from '../src/lib/dice';
import { fieldProblem } from '../src/lib/views/fieldcheck';

// a card's dice field, as the rules send it (srd5e's typed.lua): a box a die
const d20 = { key: 'main', type: 'dice', label: 'The d20 + 5', dice: [20], plus: 5 };
const adv = { key: 'main', type: 'dice', label: 'The d20s + 5', dice: [20, 20], plus: 5 };
const fireball = { key: 'main', type: 'dice', label: 'Fireball: 8d6', dice: [6, 6, 6, 6, 6, 6, 6, 6], plus: 0 };
const sword = { key: 'main', type: 'dice', label: 'Longsword damage: your d8 + 3', dice: [8], plus: 3 };

describe('a face as its die reads it', () => {
  it('takes a whole number from 1 to the sides', () => {
    expect(faceOf('14', 20)).toBe(14);
    expect(faceOf('1', 20)).toBe(1);
    expect(faceOf('20', 20)).toBe(20);
    expect(faceOf(' 7 ', 8)).toBe(7);
  });
  it('refuses what the die can’t show', () => {
    expect(faceOf('21', 20)).toBeNull();
    expect(faceOf('0', 20)).toBeNull();
    expect(faceOf('9', 8)).toBeNull();
    expect(faceOf('', 6)).toBeNull();
    expect(faceOf('2.5', 6)).toBeNull();
    expect(faceOf('-3', 6)).toBeNull();
    expect(faceOf('x', 6)).toBeNull();
  });
  it('reads a d10’s 0 as its 10, and a d100’s as its 100', () => {
    expect(faceOf('0', 10)).toBe(10);
    expect(faceOf('10', 10)).toBe(10);
    expect(faceOf('00', 100)).toBe(100);
    expect(faceOf('0', 6)).toBeNull();
  });
});

describe('moving on to the next box', () => {
  it('a die of one digit moves on at once', () => {
    expect(faceDone('5', 6)).toBe(true);
    expect(faceDone('8', 8)).toBe(true);
    expect(maxDigits(6)).toBe(1);
  });
  it('a d20 waits on a 1 or a 2, which may be 10 to 20', () => {
    expect(faceDone('1', 20)).toBe(false);
    expect(faceDone('2', 20)).toBe(false);
    expect(faceDone('3', 20)).toBe(true);
    expect(faceDone('17', 20)).toBe(true);
    expect(faceDone('20', 20)).toBe(true);
  });
  it('a d12 waits on a 1 only; a d10 on a 1, its 0 is done', () => {
    expect(faceDone('1', 12)).toBe(false);
    expect(faceDone('2', 12)).toBe(true);
    expect(faceDone('1', 10)).toBe(false);
    expect(faceDone('0', 10)).toBe(true);
    expect(faceDone('7', 10)).toBe(true);
  });
  it('a face typed wrong waits to be put right', () => {
    expect(faceDone('9', 8)).toBe(false);
    expect(faceDone('25', 20)).toBe(false);
  });
});

describe('the checks before the card goes', () => {
  it('each face from 1 to its die’s sides', () => {
    expect(diceProblem(d20, [14])).toBe('');
    expect(diceProblem(d20, [21])).toBe('A d20 shows 1 to 20.');
    expect(diceProblem(sword, [9])).toBe('A d8 shows 1 to 8.');
    expect(diceProblem(sword, [0])).toBe('A d8 shows 1 to 8.');
  });
  it('every die typed: both d20s with Advantage', () => {
    expect(diceProblem(adv, [12, null])).toBe('Type the die still to go.');
    expect(diceProblem(adv, [])).toBe('Type each of the 2 dice.');
    expect(diceProblem(adv, [3, 12])).toBe('');
    expect(diceProblem(fireball, [6, 3, 4, 1, null, null, 6, 2])).toBe('Type the 2 dice still to go.');
  });
  it('a total within its range, worked out as it’s typed', () => {
    expect(diceTotal(d20, [14])).toBe(19);
    expect(diceTotal(sword, [6])).toBe(9);
    expect(diceTotal(adv, [3, null])).toBeNull();
    const all = [6, 3, 4, 1, 2, 5, 6, 4];
    const total = diceTotal(fireball, all)!;
    expect(total).toBe(31);
    expect(total).toBeGreaterThanOrEqual(8);
    expect(total).toBeLessThanOrEqual(48);
    expect(diceTotal(fireball, [7, 3, 4, 1, 2, 5, 6, 4])).toBeNull();
  });
  it('a form’s field check says the same (fieldProblem)', () => {
    expect(fieldProblem(d20, [22])).toBe('A d20 shows 1 to 20.');
    expect(fieldProblem(d20, [22])).toBe(diceProblem(d20, [22]));
    expect(fieldProblem(d20, [2])).toBe('');
  });
  it('a card with several creatures’ dice names the one still to type', () => {
    const many = [
      { key: 'r1_main', type: 'dice', label: 'Goblin 1: a d20 + 2', dice: [20] },
      { key: 'r2_main', type: 'dice', label: 'Goblin 2: a d20 + 2', dice: [20] },
      { key: 'note', type: 'string', label: 'Note' },
    ];
    expect(cardDiceProblem(many, { r1_main: [4], r2_main: [null] })).toBe('Goblin 2: a d20 + 2: Type the die still to go.');
    expect(cardDiceProblem(many, { r1_main: [4], r2_main: [19] })).toBe('');
    expect(cardDiceProblem([d20], { main: [30] })).toBe('A d20 shows 1 to 20.');
  });
});

describe('a field’s dice and where it starts', () => {
  it('reads the sides it asks for', () => {
    expect(sidesOf(adv)).toEqual([20, 20]);
    expect(sidesOf({})).toEqual([]);
  });
  it('starts empty, or from what was typed before (asked again); a number its die can’t show is kept for the check to say so', () => {
    expect(startingDice(adv, undefined)).toEqual([null, null]);
    expect(startingDice({ ...adv, default: [21, 7] }, undefined)).toEqual([21, 7]);
    expect(diceProblem(adv, startingDice({ ...adv, default: [21, 7] }, undefined))).toBe('A d20 shows 1 to 20.');
    expect(startingDice(d20, [15])).toEqual([15]);
    expect(startingDice(d20, ['x'])).toEqual([null]);
    expect(startingDice(d20, [''])).toEqual([null]);
  });
});
