// Levels in a real browser against a real table (the owner's level-12
// one-shot, whose players build their own characters): the DM gives the
// party three levels; Ben takes Brakka's on his phone — level 2 in one tap,
// then each level's choices in the level's wizard: the Champion at 3, the
// Ability Score Improvement and a weapon mastered at 4, each level's last
// step saying what it brings (the level-12 table's said "no new features of its
// own" at an Ability Score Improvement). The wizard starts over for each
// level (it kept its answers after sending them, and the next level's opened
// at its last step with the last level's answers: its feat step never
// shown). Screenshots of each step.
//
//   node tests/e2e/levels.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party (Ben's Brakka, a dwarf fighter).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/levels.mjs <host.json> <out dir>');
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
  // (How this table runs comes up as a player joins a table: read, and put away)
  await page.addInitScript(() => {
    new MutationObserver(() => {
      const d = document.querySelector('[role="dialog"][aria-label="How this table runs"]');
      const b = d ? [...d.querySelectorAll('button')].find((x) => x.textContent.trim() === 'Got it') : null;
      if (b) b.click();
    }).observe(document, { childList: true, subtree: true });
  });
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
  await page.screenshot({ path: `${out}/${String(n).padStart(2, '0')}_${label}.png`, fullPage: true });
}

async function step(label, f) {
  process.stdout.write(`${label} … `);
  try {
    await f();
    console.log('ok');
  } catch (e) {
    console.log('FAILED');
    problems.push(`${label}: ${String(e.message ?? e).split('\n')[0]}`);
    for (const [name, p] of pages) await p.screenshot({ path: `${out}/failed_${label.replace(/[^a-z0-9]+/gi, '_').slice(0, 40)}_${name}.png`, fullPage: true }).catch(() => {});
  }
}

function expect(cond, what) {
  if (!cond) throw new Error(what);
}

const wizard = (page) => page.locator('.wizard').first();
const stepTitle = (page) => wizard(page).locator('.head h4').innerText();
const next = (page) => wizard(page).locator('.nav button.accent');

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ben = await open(info.player, { width: 390, height: 844 }, 'ben');

await step('Ben joins, and his sheet has no level to take', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).click({ timeout: 10000 });
  await ben.getByText('Dwarf Fighter 1').first().waitFor({ timeout: 8000 });
  expect((await ben.getByRole('button', { name: /Gain a level/ }).count()) === 0, 'no Gain a level before the DM gives one');
});

await step('the DM gives the party three levels', async () => {
  await dm.getByRole('tab', { name: 'Party' }).click();
  const party = dm.locator('.party');
  for (let i = 0; i < 3; i++) {
    await party.getByRole('button', { name: 'Give a level', exact: true }).click();
    await party.getByText('Given: said in the chat').waitFor({ timeout: 8000 });
    await party.getByText('Given: said in the chat').waitFor({ state: 'detached', timeout: 8000 });
  }
  await dm.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => /Brakka to level 4/.test(String(e.text ?? ''))), null, { timeout: 8000 });
});

await step('level 2: one tap', async () => {
  await ben.getByRole('button', { name: 'Ready for level 2: Gain a level' }).click({ timeout: 8000 });
  await ben.getByText('Dwarf Fighter 2').first().waitFor({ timeout: 8000 });
  await shot(ben, 'level_2');
});

await step('level 3: the level’s wizard asks for his subclass', async () => {
  await ben.getByText('Ready for level 3: choose what it gives you, then Gain a level.').waitFor({ timeout: 8000 });
  expect((await stepTitle(ben)) === 'Subclass', `the wizard opens at its Subclass step: ${await stepTitle(ben)}`);
  await shot(ben, 'level_3_subclass');
  await wizard(ben).getByRole('radio', { name: /^Champion/ }).click();
  await next(ben).click();
  expect((await stepTitle(ben)) === 'The new level', `then what the level brings: ${await stepTitle(ben)}`);
  await wizard(ben).getByText('Level 3 (Fighter 3) brings your subclass, Champion, with its features.', { exact: false }).waitFor({ timeout: 5000 });
  await shot(ben, 'level_3_brings');
  await next(ben).click();
  await ben.getByText('Dwarf Fighter 3 (Champion)').first().waitFor({ timeout: 8000 });
});

await step('level 4: the wizard starts over, at its first step, with nothing chosen', async () => {
  await ben.getByText('Ready for level 4: choose what it gives you, then Gain a level.').waitFor({ timeout: 8000 });
  expect((await stepTitle(ben)) === 'Ability Score Improvement', `the wizard at its first step again, not the last level's last: ${await stepTitle(ben)}`);
  expect((await wizard(ben).getByRole('radio', { checked: true }).count()) === 0, 'nothing chosen: the last level’s answers are gone');
  await shot(ben, 'level_4_feat');
  await wizard(ben).getByRole('radio', { name: /^Ability Score Improvement/ }).click();
  await next(ben).click();
  expect((await stepTitle(ben)) === 'Ability scores', `the abilities it raises: ${await stepTitle(ben)}`);
  await wizard(ben).getByRole('checkbox', { name: /^Strength/ }).click();
  await shot(ben, 'level_4_abilities');
  await next(ben).click();
  expect((await stepTitle(ben)) === 'Class features', `and a weapon to master: ${await stepTitle(ben)}`);
  await wizard(ben).getByRole('checkbox', { name: /^Battleaxe/ }).click();
  await next(ben).click();
  expect((await stepTitle(ben)) === 'The new level', `then what it brings: ${await stepTitle(ben)}`);
  // (the level-12 table's summaries at an Ability Score Improvement said "no new features of its own")
  await wizard(ben).getByText('Level 4 (Fighter 4) brings Ability Score Improvement (Strength +2).', { exact: false }).waitFor({ timeout: 5000 });
  await shot(ben, 'level_4_brings');
  await next(ben).click();
  await ben.getByText('Dwarf Fighter 4 (Champion)').first().waitFor({ timeout: 8000 });
  await ben.getByRole('tab', { name: 'Features' }).click();
  await ben.getByText('Ability Score Improvement (Fighter 4): Strength +2').first().waitFor({ timeout: 5000 });
  await ben.getByText('Weapon Mastery: Battleaxe').first().waitFor({ timeout: 5000 });
  await shot(ben, 'level_4_features');
});

await step('no level left to take: the header says nothing more', async () => {
  await ben.getByRole('tab', { name: 'Abilities' }).click();
  await ben.getByText(/Strength 19/).first().waitFor({ timeout: 5000 });
  expect((await ben.locator('.wizard').count()) === 0, 'no wizard: level 5 is not given');
});

for (const [, p] of pages) await p.context().close();
await browser.close();
if (problems.length) {
  console.log('\nproblems:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(`\nthe levels went through; ${n} screenshots in ${out}`);
