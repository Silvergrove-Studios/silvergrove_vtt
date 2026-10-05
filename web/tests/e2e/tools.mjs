// The table's tools, in a real browser against a real table (the owner:
// "Any spells telegraph should be able to be previewed by any player in a
// way visible to everyone at any time. Map rulers should always be
// available"): the DM gives Sela Fireball; in the chapel fight, one goblin
// left hidden from the players, Ana previews Fireball on her phone off her
// turn and puts it on the goblins; Ben's screen and the DM's show it with
// its label ("Sela: Fireball, 20-ft sphere"), and each says who it would
// catch — Ben's only the creatures he can see, the DM's the hidden goblin
// too; Ben measures from Brakka with the ruler and Ana sees it ("Brakka: …
// ft"); the DM pings by a right-click and both players see it; the DM puts a
// template on the goblins and deals Damage those caught (the DM's card: a
// fire trap, DC 40): their saves are rolled, it lands, and Ben's chat says
// so without the hidden goblin; a template on Sela puts her save on a card on
// Ana's phone — nothing rolled for her — and it lands once she rolls; the DM
// clears everyone's marks. Screenshots of each step.
//
//   node tests/e2e/tools.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party --wizard (Ana's Sela, a wizard; Ben's Brakka).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/tools.mjs <host.json> <out dir>');
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

// (a step that fails stops the run: each needs the one before)
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

function expect(cond, what) {
  if (!cond) throw new Error(what);
}

async function finish() {
  for (const [, p] of pages) await p.context().close();
  await browser.close();
  if (problems.length) {
    console.log('\nproblems:\n  ' + problems.join('\n  '));
    process.exit(1);
  }
  console.log(`\nthe table's tools were everyone's, and the hidden goblin stayed hidden; ${n} screenshots in ${out}`);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

/** Where a token is on a page's map (client pixels). */
const screenOf = (page, id) =>
  page.evaluate((tid) => {
    const c = document.querySelector('canvas');
    return c?.screenOf ? c.screenOf(tid) : null;
  }, id);

/** The marks a page has been told of. */
const marksOn = (page) => page.evaluate(() => Object.values(window.hexmap.game.marks ?? {}));

/** The words of a page's list of marks (opened from the map's tools, closed again). */
async function marksList(page) {
  const toggle = page.getByRole('button', { name: /^Marks on the map/ });
  await toggle.click();
  const list = page.getByRole('region', { name: 'Marks on the map' });
  await list.waitFor({ timeout: 4000 });
  const words = await list.innerText();
  return { list, words, close: () => list.getByRole('button', { name: 'Close' }).click() };
}

let ok = await step('Ana and Ben join; the DM gives Sela Fireball', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).first().waitFor({ timeout: 10000 }).catch(() => {});
  await dm.locator('.book').getByRole('button', { name: /^Sela/ }).first().click();
  await dm.getByRole('tab', { name: 'Spells' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a spell (any list, any level)' });
  await give.locator('input[type=search]').fill('fireball');
  await give.getByRole('button', { name: 'Give Fireball' }).click({ timeout: 8000 });
  await dm.locator('.row').filter({ hasText: /Fireball \(/ }).first().waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Fireball \(/ }).first();
  await row.getByRole('button', { name: 'Preview' }).waitFor({ timeout: 8000 });
  await shot(ana, 'ana_fireball_preview_button');
});

let seen = null; // the goblin the party sees
let hidden = null; // the one the DM keeps hidden
ok = ok && (await step('the chapel fight: the goblins revealed but one, the party beside them', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click().catch(() => {});
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 });
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Reveal them all' }).click().catch(() => {});
  await dm.waitForTimeout(600);
  // two goblins near each other: one stays seen, the other the DM hides again
  const pair = await dm.evaluate(() => {
    const toks = (window.hexmap.game.scene.tokens ?? []).filter((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? ''));
    let best = null;
    for (const a of toks)
      for (const b of toks) {
        if (a === b) continue;
        const d = Math.hypot(a.pos[0] - b.pos[0], a.pos[1] - b.pos[1]);
        if (d >= 0.9 && d <= 3 && (!best || d < best.d)) best = { d, a: { id: a.id, name: a.name }, b: { id: b.id, name: b.name } };
      }
    return best;
  });
  expect(pair, 'no two goblins near each other in the chapel');
  seen = pair.a;
  hidden = pair.b;
  await dm.locator('.fightpanel').getByRole('button', { name: new RegExp(hidden.name) }).first().click();
  await dm.locator('.fightpanel .chosen').getByRole('button', { name: 'Hide' }).click();
  await dm.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id && t.hidden), hidden.id, { timeout: 5000 });
  // the party just west of the goblin they see
  const where = await dm.evaluate((id) => {
    const c = document.querySelector('canvas');
    return c?.screenOf ? { at: c.screenOf(id), px: c.pxPerHex() } : null;
  }, seen.id);
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(800);
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForFunction(() => window.hexmap.game.scene.role === 'battle' && window.hexmap.game.scene.turns?.mode === 'ordered', null, { timeout: 8000 });
  await ben.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id), seen.id, { timeout: 8000 });
  const benSees = await ben.evaluate((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id), hidden.id);
  expect(!benSees, 'Ben’s screen was sent the hidden goblin');
  // not Sela's turn: the preview is off her turn
  const bar = dm.locator('.fightbar');
  if (await bar.getByText(/Sela’s turn/).count()) {
    const was = await dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    const asks = bar.getByRole('group', { name: /End the turn anyway\?|End this turn too\?/ });
    await dm.waitForTimeout(400);
    if (await asks.count()) await asks.getByRole('button', { name: /^End/ }).first().click();
    await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was, { timeout: 5000 });
  }
  expect(!(await bar.getByText(/Sela’s turn/).count()), 'it is still Sela’s turn');
  await shot(dm, 'dm_fight_one_goblin_hidden');
}));

ok = ok && (await step('Ana previews Fireball off her turn: on the goblins, saying who it would catch', async () => {
  expect(!(await ana.locator('.turn').filter({ hasText: /Your turn/ }).count()), 'it is Ana’s turn');
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.locator('.row').filter({ hasText: /Fireball \(/ }).first().getByRole('button', { name: 'Preview' }).click();
  const banner = ana.getByRole('group', { name: 'Preview' });
  await banner.getByText('Fireball, 20-ft sphere: tap where it goes').waitFor({ timeout: 5000 });
  const at = await screenOf(ana, seen.id);
  expect(at, 'the goblin isn’t on Ana’s map');
  await ana.mouse.click(at.x, at.y);
  await banner.getByText(/catches \d+:/).waitFor({ timeout: 5000 });
  const words = await banner.innerText();
  expect(words.includes(seen.name) && !words.includes(hidden.name), `Ana's preview names the goblin she sees and not the hidden one: ${words}`);
  await shot(ana, 'ana_fireball_on_the_goblins');
}));

ok = ok && (await step('Ben’s screen and the DM’s show it, labelled; Ben’s names only the creatures he can see', async () => {
  const isFireball = (m) => m.kind === 'preview' && m.name === 'Sela' && m.label === 'Fireball, 20-ft sphere';
  await ben.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'preview' && m.name === 'Sela' && m.label === 'Fireball, 20-ft sphere'), null, { timeout: 6000 });
  await dm.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'preview' && m.name === 'Sela' && m.label === 'Fireball, 20-ft sphere'), null, { timeout: 6000 });
  expect((await marksOn(ben)).some(isFireball), 'Ben has the preview');
  const benList = await marksList(ben);
  expect(benList.words.includes('Sela: Fireball, 20-ft sphere'), `Ben's list says it: ${benList.words}`);
  expect(benList.words.includes(seen.name), `Ben's says it catches ${seen.name}: ${benList.words}`);
  expect(!benList.words.includes(hidden.name), `Ben's never names the hidden goblin: ${benList.words}`);
  await shot(ben, 'ben_sees_the_preview');
  await benList.close();
  const dmList = await marksList(dm);
  expect(dmList.words.includes('Sela: Fireball, 20-ft sphere') && dmList.words.includes(hidden.name) && dmList.words.includes(seen.name), `the DM's says both goblins: ${dmList.words}`);
  await shot(dm, 'dm_sees_the_preview');
  await dmList.close();
  // Ana pins it and puts the tool away: it stays for the table to talk over
  const banner = ana.getByRole('group', { name: 'Preview' });
  await banner.getByRole('button', { name: 'Pin' }).click();
  await banner.getByRole('button', { name: 'Done' }).click();
  await ana.getByRole('button', { name: /^Marks on the map/ }).waitFor({ timeout: 4000 });
  await ben.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'preview' && m.pinned), null, { timeout: 5000 });
}));

ok = ok && (await step('Ben measures from Brakka with the ruler, and Ana sees it', async () => {
  const brakka = await ben.evaluate(() => (window.hexmap.game.scene.tokens ?? []).find((t) => t.name === 'Brakka')?.id ?? '');
  expect(brakka, 'no Brakka on Ben’s map');
  const from = await screenOf(ben, brakka);
  const to = await screenOf(ben, seen.id);
  await ben.getByRole('button', { name: 'Ruler' }).click();
  const banner = ben.getByRole('group', { name: 'Ruler' });
  await banner.getByText('Ruler: drag, or tap where it starts').waitFor({ timeout: 4000 });
  await ben.mouse.click(from.x, from.y);
  await ben.mouse.click(to.x, to.y);
  await banner.getByText(/\d+ ft/).waitFor({ timeout: 4000 });
  const said = (await banner.locator('strong').innerText()).trim();
  // (as Ben clicks, Ana's screen follows: the ruler's last word is what Ben's says)
  await ana
    .waitForFunction((w) => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'ruler' && m.name === 'Brakka' && m.measure?.words === w), said, { timeout: 6000 })
    .catch(() => {});
  const rulers = (await marksOn(ana)).filter((m) => m.kind === 'ruler' && m.name === 'Brakka');
  expect(rulers.length === 1 && rulers[0].measure.words === said, `Ana sees Ben's ruler as Ben does: "${rulers[0]?.measure?.words}" / "${said}"`);
  const anaList = await marksList(ana);
  expect(anaList.words.includes(`Brakka: ruler: ${said}`), `Ana's list says it: ${anaList.words}`);
  await shot(ana, 'ana_sees_bens_ruler');
  await anaList.close();
  await shot(ben, 'ben_measures');
  await banner.getByRole('button', { name: 'Done' }).click();
  await ana.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'ruler' && m.name === 'Brakka' && m.live === false), null, { timeout: 5000 });
}));

ok = ok && (await step('the DM pings by a right-click: both players see it', async () => {
  // (on Brakka: ground everyone sees, with nobody hidden there)
  const brakka = await dm.evaluate(() => (window.hexmap.game.scene.tokens ?? []).find((t) => t.name === 'Brakka')?.id ?? '');
  const at = await screenOf(dm, brakka);
  await dm.mouse.click(at.x, at.y, { button: 'right' });
  for (const p of [ana, ben]) await p.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'ping' && m.name === 'DM'), null, { timeout: 5000 });
  await shot(ana, 'ana_sees_the_dms_ping');
  // and a ping on the hidden goblin reaches nobody but the DM
  const g = await screenOf(dm, hidden.id);
  await dm.mouse.click(g.x, g.y, { button: 'right' });
  await dm.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).filter((m) => m.kind === 'ping').length >= 2, null, { timeout: 5000 });
  await ben.waitForTimeout(600);
  const benPings = (await marksOn(ben)).filter((m) => m.kind === 'ping');
  expect(benPings.length === 1, `Ben hears of the one ping, not the one over the hidden goblin: ${benPings.length}`);
  await shot(dm, 'dm_pings');
}));

// A creature's hit points as a page knows them.
const hpOf = (page, id) =>
  page.evaluate((tid) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.id === tid);
    const a = t ? g.view.actors?.[t.actor] : null;
    return a?.resources?.srd5e?.hp?.current ?? null;
  }, id);

/** The DM's template put on a creature, a circle of `feet`, and its Damage those caught: the DM's card filled and rolled. */
async function damageThoseCaught(onId, feet, name, dice) {
  await dm.getByRole('button', { name: 'Template' }).click();
  const banner = dm.getByRole('group', { name: 'Template' });
  await banner.getByText('Tap where it goes').waitFor({ timeout: 4000 });
  await banner.getByRole('spinbutton', { name: 'Radius in feet' }).fill(String(feet));
  await banner.getByRole('spinbutton', { name: 'Radius in feet' }).dispatchEvent('change');
  const at = await screenOf(dm, onId);
  await dm.mouse.click(at.x, at.y);
  await banner.getByText(/catches \d+:/).waitFor({ timeout: 4000 });
  await banner.getByRole('button', { name: 'Damage those caught' }).click();
  const card = dm.getByRole('dialog', { name: 'Damage those caught' });
  await card.waitFor({ timeout: 6000 });
  await card.getByRole('textbox', { name: /^What it is/ }).fill(name);
  await card.getByRole('textbox', { name: /^Damage: dice/ }).fill(dice);
  await card.getByRole('combobox', { name: 'Damage type' }).selectOption({ label: 'Fire' });
  await card.getByRole('spinbutton', { name: 'Its DC' }).fill('40');
  await shot(dm, `dm_${name.toLowerCase().replace(/[^a-z]+/g, '_')}_card`);
  await card.getByRole('button', { name: 'Roll it' }).click();
  await card.waitFor({ state: 'detached', timeout: 8000 });
  await banner.getByRole('button', { name: 'Done' }).click();
}

ok = ok && (await step('the DM puts a template on the goblins: Damage those caught rolls their saves and it lands; Ben never reads of the hidden goblin', async () => {
  const before = await hpOf(dm, seen.id);
  expect(typeof before === 'number', 'the DM sees the goblin’s hit points');
  await damageThoseCaught(seen.id, 10, 'Fire trap', '3');
  await dm.waitForFunction(([tid, hp]) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.id === tid);
    return g.view.actors?.[t?.actor]?.resources?.srd5e?.hp?.current === hp - 3;
  }, [seen.id, before], { timeout: 8000 });
  const lineOn = (page) => page.evaluate(() => (window.hexmap.game.view.log ?? []).map((e) => String(e.text ?? '')).find((t) => t.startsWith('Fire trap (')) ?? '');
  await ben.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => String(e.text ?? '').startsWith('Fire trap (')), null, { timeout: 8000 });
  const bens = await lineOn(ben);
  expect(bens.includes('Fire trap (3 fire; a Dexterity save, DC 40, half on a success)') && bens.includes(`${seen.name}, fails the save, 3 fire damage`), `Ben reads what it did: ${bens}`);
  expect(!(await ben.evaluate(() => JSON.stringify(window.hexmap.game.view.log ?? []))).includes(hidden.name), 'Ben’s log never names the hidden goblin');
  await shot(ben, 'ben_reads_the_trap');
}));

ok = ok && (await step('on Sela: her save is Ana’s, on a card on her phone; she rolls it, and it lands', async () => {
  const sela = await dm.evaluate(() => (window.hexmap.game.scene.tokens ?? []).find((t) => t.name === 'Sela')?.id ?? '');
  expect(sela, 'no Sela on the DM’s map');
  const before = await hpOf(dm, sela);
  // (the fire trap may have caught her too: its save waits on her card as well)
  const trap = await dm.evaluate(() => (window.hexmap.game.view.log ?? []).map((e) => String(e.text ?? '')).find((t) => t.startsWith('Fire trap (')) ?? '');
  const owed = 2 + (trap.includes('Sela, rolls their own Dexterity save') ? 3 : 0);
  await damageThoseCaught(sela, 5, 'Hot coals', '2');
  // nothing rolled for her: the card is on her phone (it opens by itself, or from its pill)
  const card = ana.getByRole('dialog', { name: 'The DM asks' });
  const pill = ana.getByRole('button', { name: /^The DM asks you to roll/ });
  await card.or(pill).first().waitFor({ timeout: 8000 });
  if (!(await card.count())) await pill.click();
  await card.waitFor({ timeout: 5000 });
  await dm.waitForTimeout(400);
  expect((await hpOf(dm, sela)) === before, 'nothing landed before she rolled');
  await shot(ana, 'ana_her_save_card');
  // each card's Roll is hers (one at a time, as they come: the next from its pill)
  const cards = owed > 2 ? 2 : 1;
  for (let i = 0; i < cards; i++) {
    await card.or(pill).first().waitFor({ timeout: 8000 });
    if (!(await card.count())) await pill.click();
    await card.waitFor({ timeout: 5000 });
    await ana.waitForTimeout(700);
    const rolls = () => dm.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => /^Sela's Dexterity save against /.test(String(e.text ?? ''))).length);
    const had = await rolls();
    await card.getByRole('button', { name: /^Roll a Dexterity save/ }).click();
    await dm.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => /^Sela's Dexterity save against /.test(String(e.text ?? ''))).length > n, had, { timeout: 8000 });
  }
  await dm.waitForFunction(([tid, hp]) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.id === tid);
    return g.view.actors?.[t?.actor]?.resources?.srd5e?.hp?.current === hp;
  }, [sela, before - owed], { timeout: 8000 });
  await shot(ana, 'ana_rolled_her_save');
}));

ok = ok && (await step('the DM clears everyone’s marks', async () => {
  const list = await marksList(dm);
  await list.list.getByRole('button', { name: 'Clear everyone’s' }).click();
  for (const p of [ana, ben, dm]) await p.waitForFunction(() => Object.keys(window.hexmap.game.marks ?? {}).length === 0, null, { timeout: 5000 });
  await shot(ana, 'ana_marks_cleared');
}));

await finish();
