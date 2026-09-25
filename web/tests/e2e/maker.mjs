// The character maker in a real browser against a real table (the team's
// notes on the third playtest): a druid by point buy on a phone — what
// the abilities are for, the suggestion, the background's +1/+1/+1; the
// page dropped and reloaded half way and back where it was; the skills
// from a list; the equipment or the gold; her first spells from the
// druid's list, one read as a card; her sheet's spells offering only what
// a druid 1 may learn. Then the DM plays rolled scores (a player rolls,
// the DM sees it) and the standard array. Screenshots of each step.
//
//   node tests/e2e/maker.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package with the
// character maker (srd5e with the `scores` and `choose` fields).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/maker.mjs <host.json> <out dir>');
  process.exit(2);
}
mkdirSync(out, { recursive: true });
const info = JSON.parse(readFileSync(infoPath, 'utf8'));
const browser = await chromium.launch({ channel: process.env.HEXMAP_BROWSER ?? 'chrome', headless: true });
const problems = [];
const pages = [];
let n = 0;

async function open(url, viewport, name) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, hasTouch: viewport.width < 600 });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => problems.push(`${name}: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/WebSocket/.test(m.text())) problems.push(`${name} console: ${m.text()}`);
  });
  await page.goto(url);
  pages.push([name, page]);
  return page;
}

async function shot(page, label) {
  n += 1;
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${out}/${String(n).padStart(2, '0')}_${label}.png` });
}

async function step(label, f) {
  process.stdout.write(`${label} … `);
  try {
    await f();
    console.log('ok');
  } catch (e) {
    console.log('FAILED');
    problems.push(`${label}: ${String(e.message ?? e).split('\n')[0]}`);
    for (const [name, p] of pages) await p.screenshot({ path: `${out}/failed_${label.replace(/[^a-z0-9]+/gi, '_').slice(0, 40)}_${name}.png` }).catch(() => {});
  }
}

function expect(cond, what) {
  if (!cond) throw new Error(what);
}

const row = (page, label) => page.locator('.wizard .row').filter({ hasText: label });
const next = (page) => page.locator('.wizard .nav button.accent');
const stepTitle = (page) => page.locator('.wizard .head h4').innerText();

async function choose(page, label, pick) {
  await page.waitForFunction(
    (lab) => {
      const r = [...document.querySelectorAll('.wizard .row')].find((x) => x.textContent?.includes(lab));
      const sel = r?.querySelector('select');
      return !!sel && !sel.disabled && sel.options.length > 1;
    },
    label,
    { timeout: 8000 },
  );
  await row(page, label).locator('select').selectOption({ label: pick });
}

async function who(page, name, species, background, klass) {
  await page.locator('#name').fill(name);
  await page.getByRole('button', { name: 'Join' }).click();
  await page.getByText('Make your character').waitFor({ timeout: 10000 });
  await row(page, 'Name').locator('input').fill(name);
  await choose(page, 'Species', species);
  await choose(page, 'Background', background);
  await choose(page, 'Class', klass);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const lia = await open(info.player, { width: 390, height: 844 }, 'lia');

await step('Lia starts a druid: nothing moves on until it is chosen', async () => {
  await lia.locator('#name').fill('Lia');
  await lia.getByRole('button', { name: 'Join' }).click();
  await lia.getByText('Make your character').waitFor({ timeout: 10000 });
  expect(await next(lia).isDisabled(), 'Next waits for a name and choices');
  await row(lia, 'Name').locator('input').fill('Lia');
  await choose(lia, 'Species', 'Elf');
  await choose(lia, 'Background', 'Criminal');
  await choose(lia, 'Class', 'Druid');
  await lia.waitForFunction(() => !document.querySelector('.wizard .nav button.accent')?.hasAttribute('disabled'), null, { timeout: 5000 });
  await shot(lia, 'lia_who');
  await next(lia).click();
});

await step('ability scores: what each is for, the druid’s marked, 27 points that cannot go wrong', async () => {
  await lia.getByText('Key for a Druid').first().waitFor({ timeout: 8000 });
  expect((await lia.getByText('Perceptiveness and mental fortitude.').count()) === 1, 'Wisdom says what it measures');
  await lia.getByText('All spent ✓').waitFor({ timeout: 5000 });
  await shot(lia, 'lia_scores_suggested');
  await lia.getByRole('button', { name: 'Start again' }).click();
  await lia.getByText('27 left').waitFor({ timeout: 5000 });
  expect(await next(lia).isDisabled(), 'Next waits while points are left');
  expect((await lia.locator('.wizard .problem').innerText()).includes('27 points left'), 'and says so');
  expect(await lia.getByRole('button', { name: 'Lower Wisdom' }).isDisabled(), 'no score below 8');
  for (let i = 0; i < 7; i++) await lia.getByRole('button', { name: 'Raise Wisdom' }).click();
  expect(await lia.getByRole('button', { name: 'Raise Wisdom' }).isDisabled(), 'no score above 15');
  await shot(lia, 'lia_scores_buying');
  await lia.getByRole('button', { name: 'Suggested for a Druid' }).click();
  await lia.getByText('All spent ✓').waitFor({ timeout: 5000 });
  await lia.getByRole('radio', { name: '+1 to all three' }).click();
  expect((await lia.getByRole('radio', { name: '+1 to all three' }).getAttribute('aria-checked')) === 'true', 'the background’s +1 to each of its three');
  await shot(lia, 'lia_scores_bonus');
});

await step('the connection drops (another app): she stays where she was', async () => {
  await lia.evaluate(() => window.hexmap.drop());
  await lia.waitForTimeout(300);
  expect((await lia.getByText('Your name').count()) === 0, 'not sent back to the join screen');
  await lia.waitForFunction(() => window.hexmap.game.status === 'open' && window.hexmap.game.joined, null, { timeout: 10000 });
  expect((await stepTitle(lia)) === 'Ability scores', `still on the ability scores (${await stepTitle(lia)})`);
  expect((await lia.getByRole('radio', { name: '+1 to all three' }).getAttribute('aria-checked')) === 'true', 'with her choice');
});

await step('the page reloads (the phone dropped it): back on the same step, answers kept', async () => {
  await lia.reload();
  await lia.locator('.wizard').waitFor({ timeout: 10000 });
  expect((await stepTitle(lia)) === 'Ability scores', `the same step after a reload (${await stepTitle(lia)})`);
  expect((await lia.getByRole('radio', { name: '+1 to all three' }).getAttribute('aria-checked')) === 'true', 'with her choice');
  await shot(lia, 'lia_after_reload');
  await next(lia).click();
});

await step('skills from a list: the criminal’s two locked, two of the druid’s to choose', async () => {
  await lia.getByText('Choose 2 · 2 left').waitFor({ timeout: 5000 });
  expect((await lia.getByText('From your background').count()) === 2, 'Sleight of Hand and Stealth, from the background');
  expect((await lia.getByRole('checkbox', { name: /^Athletics/ }).count()) === 0, 'Athletics is not a druid’s');
  await lia.getByRole('checkbox', { name: /^Nature/ }).click();
  await lia.getByRole('checkbox', { name: /^Perception/ }).click();
  await lia.getByText('2 chosen ✓').waitFor({ timeout: 5000 });
  await shot(lia, 'lia_skills');
  await next(lia).click();
});

await step('equipment: the druid’s package A, the gold instead of the criminal’s', async () => {
  await row(lia, 'From your class').getByRole('radio', { name: /^Package A/ }).click();
  await row(lia, 'From your background').getByRole('radio', { name: /^50 GP instead/ }).click();
  await shot(lia, 'lia_equipment');
  await next(lia).click();
});

await step('spells: the druid’s cantrips and level 1 spells, one read as a card', async () => {
  await lia.getByText('Choose 2 · 2 left').waitFor({ timeout: 8000 });
  expect((await lia.getByRole('checkbox', { name: /^Fire Bolt/ }).count()) === 0, 'no wizard’s cantrip');
  expect((await lia.getByRole('checkbox', { name: /^Moonbeam/ }).count()) === 0, 'no level 2 spell');
  for (const s of ['Druidcraft', 'Produce Flame']) await lia.getByRole('checkbox', { name: new RegExp(`^${s}`) }).click();
  await lia.getByRole('button', { name: 'Read Entangle' }).click();
  await lia.getByText('Casting time').waitFor({ timeout: 8000 });
  expect((await lia.getByText('Concentration', { exact: true }).count()) >= 1, 'the card tags concentration');
  await shot(lia, 'lia_spell_card');
  await lia.getByRole('button', { name: 'Close' }).first().click();
  for (const s of ['Cure Wounds', 'Entangle', 'Faerie Fire', 'Healing Word']) await lia.getByRole('checkbox', { name: new RegExp(`^${s}`) }).click();
  await shot(lia, 'lia_spells');
  await next(lia).click();
  await lia.getByText('Elf Druid 1').first().waitFor({ timeout: 10000 });
  await shot(lia, 'lia_sheet');
});

await step('her sheet’s spells: only what a druid 1 may learn', async () => {
  await lia.getByRole('tab', { name: 'Spells' }).click();
  await lia.getByText('Your druid spells: cantrips and spells up to level 1.').waitFor({ timeout: 5000 });
  const find = lia.locator('.picker').filter({ hasText: 'Learn a druid spell' }).locator('input[type=search]');
  await find.fill('moon');
  await lia.locator('.picker').filter({ hasText: 'Learn a druid spell' }).getByText('Nothing matches').waitFor({ timeout: 5000 });
  await find.fill('');
  expect((await lia.getByText('Give a spell (any list, any level)').count()) === 0, 'giving any spell is the DM’s');
  await shot(lia, 'lia_learn');
  await lia.getByRole('tab', { name: 'Inventory' }).click();
  await lia.getByText('Leather Armor').first().waitFor({ timeout: 5000 });
  const gold = await lia.locator('.stat').filter({ hasText: 'Gold (GP)' }).locator('input').inputValue();
  expect(gold === '59', `9 GP with the package and 50 instead of the criminal's: ${gold}`);
  await shot(lia, 'lia_inventory');
});

await step('the DM plays rolled scores: Rules settings', async () => {
  await dm.getByRole('button', { name: 'Rules settings' }).click();
  await dm.getByText('How players make their ability scores').waitFor({ timeout: 5000 });
  await dm.getByRole('combobox', { name: 'How players make their ability scores' }).selectOption({ label: 'Rolled (4d6, the highest three, six times)' });
  await dm.waitForTimeout(800);
  await shot(dm, 'dm_rules_settings');
  await dm.getByRole('button', { name: 'Close' }).first().click();
});

const rolf = await open(info.player, { width: 390, height: 844 }, 'rolf');
await step('a player rolls: the table rolls once, the DM sees it', async () => {
  await who(rolf, 'Rolf', 'Human', 'Soldier', 'Fighter');
  await next(rolf).click();
  await rolf.getByRole('button', { name: 'Roll my scores' }).click();
  await rolf.getByText('You rolled').waitFor({ timeout: 8000 });
  await rolf.getByRole('button', { name: 'Suggested for a Fighter' }).waitFor({ timeout: 5000 });
  await shot(rolf, 'rolf_rolled');
  await dm.getByText('Rolled ability scores').waitFor({ timeout: 8000 });
  await dm.getByText(/^Rolf: \d+, \d+/).first().waitFor({ timeout: 5000 });
  await shot(dm, 'dm_sees_rolls');
  await next(rolf).click();
  for (const s of ['Perception', 'Survival']) await rolf.getByRole('checkbox', { name: new RegExp(`^${s}`) }).click();
  await next(rolf).click();
  await rolf.getByRole('radio', { name: /^155 GP instead/ }).click();
  await rolf.getByRole('radio', { name: /^50 GP instead/ }).click();
  await next(rolf).click();
  await rolf.getByText('Human Fighter 1').first().waitFor({ timeout: 10000 });
});

const ari = await open(info.player, { width: 390, height: 844 }, 'ari');
await step('the standard array: each number given once', async () => {
  await dm.getByRole('button', { name: 'Rules settings' }).click();
  await dm.getByRole('combobox', { name: 'How players make their ability scores' }).selectOption({ label: 'The standard array (15, 14, 13, 12, 10, 8)' });
  await dm.waitForTimeout(800);
  await dm.getByRole('button', { name: 'Close' }).first().click();
  await who(ari, 'Ari', 'Dwarf', 'Acolyte', 'Cleric');
  await next(ari).click();
  await ari.getByText('Give each of these numbers to one ability').waitFor({ timeout: 8000 });
  // giving Strength the 15 swaps it with the ability that had it
  await ari.getByRole('combobox', { name: 'Strength' }).selectOption('15');
  const nums = await Promise.all(['Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma'].map((a) => ari.getByRole('combobox', { name: a }).inputValue()));
  expect([...nums].sort((a, b) => b - a).join() === '15,14,13,12,10,8', `each number once: ${nums.join(', ')}`);
  await shot(ari, 'ari_array');
});

for (const [, p] of pages) await p.context().close();
await browser.close();
if (problems.length) {
  console.log('\nproblems:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(`\nthe maker went through; ${n} screenshots in ${out}`);
