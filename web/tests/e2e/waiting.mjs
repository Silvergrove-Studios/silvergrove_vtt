// A turn that waits on a roll, in a real browser. The table rolls real dice
// (the players type what came up); in the chapel fight the DM drops Wren to 0
// from her sheet, and Next turn goes on until hers: it starts with her death
// saving throw, asked on Ana's phone for its d20, and the turn waits on it —
// the DM's fight bar says the turn is waiting on Ana and holds Next and Back,
// Ben's header says so too. Ana types her d20: the save is made, the waiting
// goes from every screen, and Next goes on. Then the DM's fire trap catches
// Brakka: a save owed on someone else's doing holds the turn too, until Ben
// presses Roll and types his d20. Screenshots of each step go to the output
// folder; a step that does not happen fails the run.
//
//   node tests/e2e/waiting.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, started with --party (Ana plays
// Wren; Ben, Brakka) on a package built on rules whose turn hooks ask.
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/waiting.mjs <host.json> <out dir>');
  process.exit(2);
}
mkdirSync(out, { recursive: true });
const info = JSON.parse(readFileSync(infoPath, 'utf8'));
const browser = await chromium.launch({ channel: process.env.HEXMAP_BROWSER ?? 'chrome', headless: true });
const problems = [];
let n = 0;
const pages = [];

async function open(url, viewport, name) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, hasTouch: viewport.width < 600 });
  const page = await ctx.newPage();
  page.on('pageerror', (e) => problems.push(`${name}: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`${name} console: ${m.text()}`);
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
    return true;
  } catch (e) {
    console.log('FAILED');
    problems.push(`${label}: ${String(e.message ?? e).split('\n')[0]}`);
    for (const [name, p] of pages) await p.screenshot({ path: `${out}/failed_${label.replace(/[^a-z0-9]+/gi, '_').slice(0, 40)}_${name}.png` }).catch(() => {});
    return false;
  }
}

function expect(cond, why) {
  if (!cond) throw new Error(why);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

// A ruleset's setting, from the DM's Table settings: its select, by its title.
async function setRule(title, option) {
  await dm.getByRole('button', { name: /^(Rules|Table) settings/ }).first().click();
  const dialog = dm.getByRole('dialog', { name: /^(Rules|Table) settings$/ });
  await dialog.waitFor({ timeout: 5000 });
  await dialog.getByRole('combobox', { name: title, exact: true }).selectOption({ label: option });
  await dm.waitForTimeout(900);
  await dialog.getByRole('button', { name: 'Done' }).click();
  await dialog.waitFor({ state: 'detached', timeout: 5000 });
}

// Wren as the DM's screen has her: her token, her actor, her hit points and death saves.
const wren = () =>
  dm.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    const a = t ? g.view.actors?.[t.actor] : null;
    const r = a?.resources?.srd5e ?? {};
    return t ? { id: t.id, actor: t.actor, hp: r.hp?.current, saves: (r.death_success?.current ?? 0) + (r.death_fail?.current ?? 0) } : null;
  });

// Where a token is on the DM's map (client pixels).
const screenOf = (page, id) => page.evaluate((tid) => document.querySelector('.mapholder canvas')?.screenOf?.(tid) ?? null, id);

// Whose turn it is, by the token up now.
const upNow = () =>
  dm.evaluate(() => {
    const t = window.hexmap.game.scene.turns ?? {};
    const e = (t.order ?? [])[t.turn ?? 0];
    return { entry: String(e ?? ''), at: `${t.round}/${t.turn}` };
  });

let ok = await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
});

ok = ok && (await step('the DM starts the session and the chapel fight; initiative; the goblins revealed', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click();
  await dm.getByText(/Session 1/).first().waitFor({ timeout: 5000 });
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 });
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Reveal them all' }).click().catch(() => {});
  await dm.waitForTimeout(800);
}));

ok = ok && (await step('the table rolls real dice; the DM drops Wren to 0 from her sheet: she is dying', async () => {
  await setRule("Players' dice", 'Real dice: each player rolls and types what came up');
  await dm.locator('.book').getByRole('button', { name: /^Wren/ }).first().click();
  const w = await wren();
  expect(w && w.hp > 0, `Wren's hit points: ${JSON.stringify(w)}`);
  const amount = dm.getByRole('spinbutton', { name: 'Damage (or healing)' }).first();
  await amount.fill(String(w.hp));
  await dm.locator('.form-box').filter({ has: amount }).first().getByRole('button', { name: 'Apply' }).click();
  await dm.waitForFunction((aid) => (window.hexmap.game.view.actors?.[aid]?.resources?.srd5e?.hp?.current ?? 1) === 0, w.actor, { timeout: 8000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
  await shot(dm, 'dm_wren_dying');
}));

ok = ok && (await step('Next turn until Wren’s: her turn starts with her death save, asked on Ana’s phone for its d20, and the turn waits on it — the DM’s fight bar says so and holds Next, Ben’s header too', async () => {
  const w = await wren();
  const card = ana.getByRole('dialog', { name: 'Your roll' });
  for (let i = 0; i < 16; i++) {
    if (await card.isVisible().catch(() => false)) break;
    const was = await upNow();
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    const asks = dm.locator('.fightbar').getByRole('group', { name: /End the turn anyway\?|End this turn too\?/ });
    await dm.waitForFunction(
      (b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b || !!document.querySelector('.fightbar .buttons.ask'),
      was.at,
      { timeout: 5000 },
    );
    if (await asks.count()) await asks.getByRole('button', { name: /^End/ }).first().click();
    await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was.at, { timeout: 5000 });
    await dm.waitForTimeout(500);
  }
  await card.waitFor({ timeout: 8000 });
  await card.getByText(/Death saving throw/).first().waitFor({ timeout: 5000 });
  expect((await upNow()).entry === w.id, 'it is Wren’s turn');
  await shot(ana, 'ana_death_save_d20');
  // the DM's fight bar: the turn waits on Ana, Next and Back held
  const bar = dm.locator('.fightbar');
  await bar.locator('.waits').filter({ hasText: /the turn is waiting on Ana: a roll \(Wren\)/ }).waitFor({ timeout: 8000 });
  expect(await bar.getByRole('button', { name: 'Next turn ›' }).isDisabled(), 'Next waits on it');
  expect(await bar.getByRole('button', { name: '‹ Back' }).isDisabled(), 'and Back');
  await shot(dm, 'dm_turn_waits_on_ana');
  // Ben's header
  await ben.locator('.turn .turnnote').filter({ hasText: /The turn is waiting on Ana: a roll \(Wren\)/ }).waitFor({ timeout: 8000 });
  await shot(ben, 'ben_turn_waits_on_ana');
  expect((await wren()).saves === w.saves, 'nothing rolled for her');
}));

ok = ok && (await step('Ana types her d20: the death save is made, the waiting goes from every screen, and Next goes on', async () => {
  const w = await wren();
  const card = ana.getByRole('dialog', { name: 'Your roll' });
  const box = card.locator('input.die').first();
  await box.waitFor({ timeout: 8000 });
  await ana.waitForTimeout(700);
  await box.click();
  await box.pressSequentially('15', { delay: 40 });
  await card.getByRole('button', { name: /^Done/ }).click();
  await card.waitFor({ state: 'detached', timeout: 8000 });
  await dm.waitForFunction((aid) => (window.hexmap.game.view.actors?.[aid]?.resources?.srd5e?.death_success?.current ?? 0) >= 1, w.actor, { timeout: 8000 });
  await dm.locator('.fightbar .waits').waitFor({ state: 'detached', timeout: 8000 });
  await ben.locator('.turn .turnnote').filter({ hasText: /waiting/ }).waitFor({ state: 'detached', timeout: 8000 });
  expect(!(await dm.locator('.fightbar').getByRole('button', { name: 'Next turn ›' }).isDisabled()), 'Next is the DM’s again');
  const roll = await dm.evaluate(() => {
    const log = window.hexmap.game.view.log ?? [];
    for (let i = log.length - 1; i >= 0; i--) if (log[i].kind === 'roll' && /Death saving throw/.test(String(log[i].label ?? ''))) return log[i];
    return null;
  });
  expect(roll && roll.spec?.typed_by && roll.result?.dice?.[0]?.face === 15, `her death save, as she typed it: ${JSON.stringify(roll?.spec)}`);
  await shot(dm, 'dm_the_turn_goes_on');
}));

// (the owner: a save owed on someone else's action "should also make the turn wait")
ok = ok && (await step('the DM’s fire trap catches Brakka: his Dexterity save holds the turn — the fight bar says it waits on Ben and holds Next — until Ben presses Roll and types his d20', async () => {
  const brakka = await dm.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Brakka');
    return t ? { id: t.id, actor: t.actor, hp: g.view.actors?.[t.actor]?.resources?.srd5e?.hp?.current } : null;
  });
  expect(brakka && brakka.hp > 3, `Brakka on the map: ${JSON.stringify(brakka)}`);
  // the DM's template on Brakka, and its Damage those caught: a Dexterity save, DC 40
  await dm.getByRole('button', { name: 'Template' }).click();
  const banner = dm.getByRole('group', { name: 'Template' });
  await banner.getByText('Tap where it goes').waitFor({ timeout: 4000 });
  await banner.getByRole('spinbutton', { name: 'Radius in feet' }).fill('5');
  await banner.getByRole('spinbutton', { name: 'Radius in feet' }).dispatchEvent('change');
  const at = await screenOf(dm, brakka.id);
  expect(at, 'Brakka isn’t on the DM’s map');
  await dm.mouse.click(at.x, at.y);
  await banner.getByText(/catches \d+:/).waitFor({ timeout: 4000 });
  await banner.getByRole('button', { name: 'Damage those caught' }).click();
  const trap = dm.getByRole('dialog', { name: 'Damage those caught' });
  await trap.waitFor({ timeout: 6000 });
  await trap.getByRole('textbox', { name: /^What it is/ }).fill('Fire trap');
  await trap.getByRole('textbox', { name: /^Damage: dice/ }).fill('3');
  await trap.getByRole('combobox', { name: 'Damage type' }).selectOption({ label: 'Fire' });
  await trap.getByRole('spinbutton', { name: 'Its DC' }).fill('40');
  await trap.getByRole('button', { name: 'Roll it' }).click();
  await trap.waitFor({ state: 'detached', timeout: 8000 });
  await banner.getByRole('button', { name: 'Done' }).click();
  // Ben's card: his save, his to roll; the turn waits on it (Wren, dying, fails hers by
  // herself: nobody is asked for it)
  const bar = dm.locator('.fightbar');
  await bar.locator('.waits').filter({ hasText: /waiting on .*Ben: a save \(Brakka\)/ }).waitFor({ timeout: 8000 });
  expect(await bar.getByRole('button', { name: 'Next turn ›' }).isDisabled(), 'Next waits on his save');
  await shot(dm, 'dm_turn_waits_on_bens_save');
  expect((await dm.evaluate((aid) => window.hexmap.game.view.actors?.[aid]?.resources?.srd5e?.hp?.current, brakka.actor)) === brakka.hp, 'nothing rolled for him yet');
  const anaAsked = await ana.evaluate(() => (window.hexmap.game.view.prompts ?? []).some((p) => /Fire trap/.test(JSON.stringify(p))));
  expect(!anaAsked, 'Ana was asked for Wren’s save, which fails by itself');
  // (her roll says why it failed, whatever it came to)
  await dm.locator('.line.roll').filter({ hasText: /Wren/ }).filter({ hasText: /Fire trap/ }).filter({ hasText: /automatic: Dying/ }).first().waitFor({ timeout: 5000 });
  // (a card the table's settings brought, "How this table runs", put away first)
  await ben.getByRole('dialog', { name: 'How this table runs' }).getByRole('button', { name: 'Got it' }).click({ timeout: 3000 }).catch(() => {});
  // he opens his card from its pill and presses Roll, then types his d20 (real dice):
  // the turn waits on that too, then goes on
  const ask = ben.getByRole('dialog').filter({ hasText: /Fire trap/ }).first();
  if (!(await ask.isVisible().catch(() => false))) await ben.getByRole('button', { name: /Fire trap/ }).first().click({ timeout: 8000 });
  await ask.waitFor({ timeout: 8000 });
  await shot(ben, 'ben_save_against_the_trap');
  await ask.getByRole('button', { name: /^Roll a Dexterity save/ }).click();
  const card = ben.getByRole('dialog', { name: 'Your roll' });
  const box = card.locator('input.die').first();
  await box.waitFor({ timeout: 8000 });
  await ben.waitForTimeout(700);
  await box.click();
  await box.pressSequentially('4', { delay: 40 });
  await card.getByRole('button', { name: /^Done/ }).click();
  await card.waitFor({ state: 'detached', timeout: 8000 });
  await dm.waitForFunction(([aid, hp]) => (window.hexmap.game.view.actors?.[aid]?.resources?.srd5e?.hp?.current ?? hp) < hp, [brakka.actor, brakka.hp], { timeout: 8000 });
  await bar.locator('.waits').waitFor({ state: 'detached', timeout: 8000 });
  expect(!(await bar.getByRole('button', { name: 'Next turn ›' }).isDisabled()), 'Next is the DM’s again');
  await shot(dm, 'dm_the_turn_goes_on_after_the_trap');
}));

await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log(`\nthe turn waited on Ana's death save and on Ben's save against the trap, and went on when they rolled; ${n} screenshots in ${out}`);
