// How a table runs, in a real browser against a real table (the owner: the
// DM, not the app, decides how much Hexmap does). A DM who has just started
// an adventure gets the walkthrough by itself: on maps; Assisted offered,
// Bookkeeping picked (its three lines on what the players will notice); the
// table's questions, each with a line of its answer, one opened with Change;
// the rules options and a house rule; a summary that says Bookkeeping and
// that any of it can change later in Table settings. Then Table settings:
// "As Bookkeeping has it"; a switch to Automated says what it would change
// before it does, and is cancelled; a setting changed by hand makes the table
// "Customized", and its section's Reset puts it back. A player joins and is
// shown How this table runs (Bookkeeping, the house rule), and finds it again
// in the ⋯ menu. Screenshots of each step.
//
//   node tests/e2e/settings.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e with
// --walkthrough (the campaign as a DM starting it has it: not yet set up).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/settings.mjs <host.json> <out dir>');
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

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const walk = dm.getByRole('dialog', { name: 'Set up this table' });
const next = () => walk.getByRole('button', { name: 'Next', exact: true }).click();

await step('a campaign never set up: the walkthrough opens by itself, maps first', async () => {
  await walk.waitFor({ timeout: 10000 });
  await walk.getByText('Step 1 of 5').waitFor({ timeout: 5000 });
  expect((await walk.getByRole('radio', { name: /^On maps/ }).getAttribute('aria-checked')) === 'true', 'maps unless the DM says otherwise');
  await shot(dm, 'dm_walkthrough_space');
  await next();
});

await step('the levels: Assisted offered, Bookkeeping picked', async () => {
  await walk.getByText('Step 2 of 5').waitFor({ timeout: 5000 });
  expect((await walk.getByRole('radio').count()) === 4, 'four levels');
  expect((await walk.getByRole('radio', { name: /^Assisted/ }).getAttribute('aria-checked')) === 'true', 'Assisted chosen until the DM says otherwise');
  const bk = walk.getByRole('radio', { name: /^Bookkeeping/ });
  expect((await bk.locator('li').count()) === 3, 'three lines on what the players will notice');
  await bk.click();
  expect((await bk.getAttribute('aria-checked')) === 'true', 'Bookkeeping chosen');
  await shot(dm, 'dm_walkthrough_level');
  await next();
});

await step('the table’s questions: a line of each answer, one opened with Change', async () => {
  await walk.getByText('Step 3 of 5').waitFor({ timeout: 5000 });
  const outcomes = walk.getByRole('region', { name: 'What a roll does' });
  expect((await outcomes.locator('.line').innerText()).includes('Apply damage to the target when an attack hits: Off'), 'Bookkeeping lands nothing by itself');
  const dice = walk.getByRole('region', { name: 'Dice' });
  expect((await dice.locator('.line').innerText()).includes('Players roll their own initiative: On'), 'players roll their own');
  await dice.getByRole('button', { name: 'Change' }).click();
  await dice.getByRole('checkbox', { name: /^Players roll their own saves/ }).waitFor({ timeout: 5000 });
  await shot(dm, 'dm_walkthrough_questions');
  await next();
});

await step('the rules options and a house rule', async () => {
  await walk.getByText('Step 4 of 5').waitFor({ timeout: 5000 });
  await walk.getByRole('combobox', { name: 'How characters gain levels' }).waitFor({ timeout: 5000 });
  await walk.getByLabel(/^House rules/).fill('Drinking a potion is a bonus action.');
  await shot(dm, 'dm_walkthrough_rules');
  await next();
});

await step('the summary, then Done: the table is set up at Bookkeeping', async () => {
  await walk.getByText('Step 5 of 5').waitFor({ timeout: 5000 });
  // (the level's own line: the sheets' setting at Bookkeeping says the word too)
  const summary = walk.getByRole('definition').filter({ hasText: /^\s*Bookkeeping — / });
  expect((await summary.count()) === 1, 'the summary says Bookkeeping');
  await walk.getByText('Drinking a potion is a bonus action.').waitFor({ timeout: 5000 });
  await walk.getByText('Change any of this later in Table settings.').waitFor({ timeout: 5000 });
  expect((await walk.getByRole('button', { name: 'See every setting' }).count()) === 1, 'and See every setting');
  await shot(dm, 'dm_walkthrough_summary');
  await walk.getByRole('button', { name: 'Done', exact: true }).click();
  await walk.waitFor({ state: 'detached', timeout: 8000 });
  await dm.getByRole('button', { name: /^Table settings Bookkeeping$/ }).waitFor({ timeout: 8000 });
  await dm.waitForFunction(() => window.hexmap.game.dm.table?.level === 'bookkeeping' && !window.hexmap.game.dm.table?.pending, null, { timeout: 8000 });
});

await step('Table settings: as Bookkeeping has it; a switch says what it would change before it does', async () => {
  await dm.getByRole('button', { name: /^Table settings/ }).click();
  const settings = dm.getByRole('dialog', { name: 'Table settings' });
  await settings.waitFor({ timeout: 5000 });
  await settings.getByText('As Bookkeeping has it').waitFor({ timeout: 5000 });
  expect((await settings.getByRole('checkbox', { name: 'Apply damage to the target when an attack hits' }).isChecked()) === false, 'nothing lands by itself');
  expect((await settings.getByText('takes effect at the next fight').count()) >= 1, 'who rolls initiative waits for the next fight');
  await settings.getByRole('group', { name: 'Level' }).getByRole('button', { name: 'Automated' }).click();
  const preview = settings.getByRole('region', { name: 'What switching changes' });
  await preview.waitFor({ timeout: 5000 });
  const count = await preview.locator('.count').innerText();
  expect(/^\d+ settings change:/.test(count), `says how many change: ${count}`);
  await preview.getByText('Apply damage to the target when an attack hits').waitFor({ timeout: 5000 });
  await shot(dm, 'dm_settings_switch_preview');
  await preview.getByRole('button', { name: 'Cancel' }).click();
  expect((await dm.evaluate(() => window.hexmap.game.dm.table.level)) === 'bookkeeping', 'cancelled: nothing changed');
});

await step('a setting changed by hand: Customized, and its section reset to Bookkeeping', async () => {
  const settings = dm.getByRole('dialog', { name: 'Table settings' });
  await settings.getByRole('checkbox', { name: 'Count movement on each creature’s turn' }).check();
  await settings.getByText(/^Customized: 1 setting differs from Bookkeeping/).waitFor({ timeout: 8000 });
  await shot(dm, 'dm_settings_customized');
  await settings.getByRole('region', { name: 'Rules checks' }).getByRole('button', { name: 'Reset to Bookkeeping' }).click();
  await settings.getByText('As Bookkeeping has it').waitFor({ timeout: 8000 });
  expect((await settings.getByRole('checkbox', { name: 'Count movement on each creature’s turn' }).isChecked()) === false, 'back as Bookkeeping has it');
  await settings.getByRole('button', { name: 'Done' }).click();
});

const pia = await open(info.player, { width: 390, height: 844 }, 'pia');
await step('a player joins and is shown how this table runs', async () => {
  await pia.locator('#name').fill('Pia');
  await pia.getByRole('button', { name: 'Join' }).click();
  const runs = pia.getByRole('dialog', { name: 'How this table runs' });
  await runs.waitFor({ timeout: 10000 });
  await runs.getByText('Bookkeeping', { exact: true }).waitFor({ timeout: 5000 });
  await runs.getByText('Drinking a potion is a bonus action.').waitFor({ timeout: 5000 });
  await runs.getByText('Players roll their own initiative').waitFor({ timeout: 5000 });
  await shot(pia, 'pia_how_this_table_runs');
  await runs.getByRole('button', { name: 'Got it' }).click();
  await runs.waitFor({ state: 'detached', timeout: 5000 });
});

await step('and finds it again in the ⋯ menu', async () => {
  await pia.getByRole('button', { name: 'More' }).click();
  await pia.getByRole('menuitem', { name: 'How this table runs' }).click();
  const runs = pia.getByRole('dialog', { name: 'How this table runs' });
  await runs.getByText('Bookkeeping', { exact: true }).waitFor({ timeout: 5000 });
  await runs.getByRole('button', { name: 'Got it' }).click();
  // (once seen, a reload doesn't show it again)
  await pia.reload();
  await pia.getByRole('button', { name: 'More' }).waitFor({ timeout: 10000 });
  await pia.waitForTimeout(1500);
  expect((await pia.getByRole('dialog', { name: 'How this table runs' }).count()) === 0, 'shown once');
});

for (const [, p] of pages) await p.context().close();
await browser.close();
if (problems.length) {
  console.log('\nproblems:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(`\nthe table's settings went through; ${n} screenshots in ${out}`);
