// A reaction at the table, in a real browser: the chapel fight; a goblin's
// hit on Ana's wizard offers Shield on her phone, at once, with its seconds
// counting down; Ben's screen and the DM's say whom the fight waits on (the
// DM's with a way to go on); she casts it, the attack misses, and her level 1
// slot and her reaction are spent. Screenshots of each step go to the output
// folder; a step that does not happen fails the run.
//
//   node tests/e2e/reactions.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, started with --party --wizard
// (Ana's character is Sela, a wizard with Shield prepared) and --seed 12 (the
// dice from a known start: the goblin's roll a hit that Shield turns aside).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/reactions.mjs <host.json> <out dir>');
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
  } catch (e) {
    console.log('FAILED');
    problems.push(`${label}: ${String(e.message ?? e).split('\n')[0]}`);
    for (const [name, p] of pages) await p.screenshot({ path: `${out}/failed_${label.replace(/[^a-z0-9]+/gi, '_').slice(0, 40)}_${name}.png` }).catch(() => {});
  }
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

// Sela's token, and what the table says of her (hit points, level 1 slots, her reaction)
const sela = () =>
  dm.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Sela');
    const a = t ? g.view.actors?.[t.actor] : null;
    const res = a?.resources?.srd5e ?? {};
    return t ? { id: t.id, actor: t.actor, pos: t.pos, hp: res.hp?.current, slot1: res.slot_1?.current, reactions: g.view.turns?.counters?.[`token:${t.id}`]?.reactions } : null;
  });

await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await shot(ana, 'ana_joined');
});

await step('the DM starts the session and the chapel fight; initiative; the goblins revealed', async () => {
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
  await shot(dm, 'dm_order');
});

let goblin = null;
await step('the DM puts the party inside and Sela beside a goblin', async () => {
  const where = await dm.evaluate(() => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gob = toks.find((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? ''));
    const c = document.querySelector('canvas');
    if (!gob || !c?.screenOf) return null;
    return { at: c.screenOf(gob.id), px: c.pxPerHex(), gob: { id: gob.id, name: gob.name, actor: gob.actor, pos: gob.pos } };
  });
  if (!where) throw new Error('no goblin on the DM’s map');
  goblin = where.gob;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(600);
  // Sela, dragged by the DM beside the goblin (the DM's hand: no move of hers)
  const s = await sela();
  if (!s) throw new Error('no Sela on the map');
  const drag = await dm.evaluate(
    ([sid, gid]) => {
      const c = document.querySelector('canvas');
      const px = c.pxPerHex();
      const from = c.screenOf(sid);
      const g = c.screenOf(gid);
      return { from, to: { x: g.x - px, y: g.y } };
    },
    [s.id, goblin.id],
  );
  await dm.mouse.move(drag.from.x, drag.from.y);
  await dm.mouse.down();
  await dm.mouse.move(drag.from.x + 10, drag.from.y, { steps: 3 });
  await dm.mouse.move(drag.to.x, drag.to.y, { steps: 8 });
  await dm.mouse.up();
  await dm.waitForFunction(
    ([sid, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === sid);
      return t && (t.pos[0] !== pos[0] || t.pos[1] !== pos[1]);
    },
    [s.id, s.pos],
    { timeout: 5000 },
  );
  await shot(dm, 'dm_sela_beside_goblin');
});

let before = null;
await step('the goblin’s scimitar hits Sela: a Shield card on Ana’s phone at once, with its seconds; Ben’s and the DM’s screens say whom the fight waits on', async () => {
  before = await sela();
  await dm.locator(`.order [data-token="${goblin.id}"]`).click();
  await dm.locator('.chosen').waitFor({ timeout: 5000 });
  const row = dm.locator('.chosen .row').filter({ hasText: /^Scimitar\./ }).first();
  await row.getByRole('button', { name: 'Use' }).click();
  const banner = dm.getByRole('group', { name: 'Choose the target' });
  await banner.waitFor({ timeout: 5000 });
  await banner.locator('.choice').filter({ hasText: /^Sela/ }).first().click();
  await banner.getByRole('button', { name: 'Done' }).click();
  // Ana's phone: her card in front, whatever tab she was on
  const card = ana.getByRole('dialog', { name: 'Your reaction' });
  await card.waitFor({ timeout: 8000 });
  const words = await card.innerText();
  if (!/hits you \(Scimitar\): \d+ against your AC \d+/.test(words)) throw new Error(`the card: ${words}`);
  if (!/\d+ s/.test(words)) throw new Error(`no seconds on the card: ${words}`);
  const shield = card.getByRole('button', { name: /^Shield \(a level 1 slot\): AC \d+ against this \d+: / });
  await shield.waitFor({ timeout: 3000 });
  const label = await shield.innerText();
  if (!/it misses$/.test(label.trim())) throw new Error(`the goblin's roll isn't one Shield turns aside (pick another --seed): ${label}`);
  await card.getByRole('button', { name: 'No reaction' }).waitFor({ timeout: 3000 });
  await shot(ana, 'ana_shield_card');
  // everyone else is told the fight waits on Ana; the DM can go on without waiting
  await ben.getByRole('status', { name: 'What the table waits on' }).getByText(/Waiting on Ana: a reaction \(Sela\) · \d+ s/).waitFor({ timeout: 5000 });
  await shot(ben, 'ben_waiting_on_ana');
  const strip = dm.getByRole('status', { name: 'What the table waits on' });
  await strip.getByText(/Waiting on Ana: a reaction \(Sela\) · \d+ s/).waitFor({ timeout: 5000 });
  await strip.getByRole('button', { name: 'Go on' }).waitFor({ timeout: 3000 });
  await shot(dm, 'dm_waiting_on_ana');
});

await step('Ana casts Shield: the attack misses; a level 1 slot and her reaction spent; nobody waits any more', async () => {
  const card = ana.getByRole('dialog', { name: 'Your reaction' });
  await card.getByRole('button', { name: /^Shield/ }).click();
  await card.waitFor({ state: 'detached', timeout: 8000 });
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText(/Sela's Shield: AC \d+ against the Goblin[^:]*: it misses\./).first().waitFor({ timeout: 8000 });
  await shot(ana, 'ana_shield_cast');
  const after = await sela();
  if (after.hp !== before.hp) throw new Error(`Sela was hurt: ${before.hp} → ${after.hp}`);
  if (after.slot1 !== before.slot1 - 1) throw new Error(`her level 1 slots: ${before.slot1} → ${after.slot1}`);
  if (after.reactions !== 0) throw new Error(`her reaction: ${after.reactions}`);
  await dm.getByRole('status', { name: 'What the table waits on' }).waitFor({ state: 'detached', timeout: 5000 });
  await ben.getByRole('status', { name: 'What the table waits on' }).waitFor({ state: 'detached', timeout: 5000 });
  await shot(dm, 'dm_after_shield');
});

const turnNow = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);
await step('the next round, her reaction back: the DM goes on without waiting for her answer', async () => {
  // round 2, Sela's turn: her reaction comes back as it starts
  for (let i = 0; i < 16; i++) {
    const r = await dm.evaluate(() => window.hexmap.game.scene.turns?.round ?? 0);
    if (r >= 2 && (await dm.locator('.fightbar').getByText(/Sela’s turn/).count())) break;
    const was = await turnNow();
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    const asks = dm.locator('.fightbar').getByRole('group', { name: /End the turn anyway\?|End this turn too\?/ });
    await dm.waitForFunction(
      (b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b || !!document.querySelector('.fightbar .buttons.ask'),
      was,
      { timeout: 5000 },
    );
    if (await asks.count()) await asks.getByRole('button', { name: /^End/ }).first().click();
    await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was, { timeout: 5000 });
  }
  const s = await sela();
  if (s.reactions !== 1) throw new Error(`her reaction isn't back: ${s.reactions}`);
  // a goblin's shortbow at her, then the next one's, until one hits (the dice are the seed's)
  const card = ana.getByRole('dialog', { name: 'Your reaction' });
  // (each by its token: every goblin is "Goblin Warrior")
  const goblins = await dm.evaluate(() => (window.hexmap.game.scene.tokens ?? []).filter((t) => /^Goblin Warrior/.test(t.name ?? '')).map((t) => t.id));
  let asked = false;
  for (const g of goblins) {
    await dm.locator(`.order [data-token="${g}"]`).click();
    await dm.locator('.chosen').waitFor({ timeout: 5000 });
    await dm.locator('.chosen .row').filter({ hasText: /^Shortbow\./ }).first().getByRole('button', { name: 'Use' }).click();
    const banner = dm.getByRole('group', { name: 'Choose the target' });
    await banner.waitFor({ timeout: 5000 });
    await banner.locator('.choice').filter({ hasText: /^Sela/ }).first().click();
    await banner.getByRole('button', { name: 'Done' }).click();
    asked = await card.waitFor({ timeout: 4000 }).then(
      () => true,
      () => false,
    );
    if (asked) break;
  }
  if (!asked) throw new Error('no goblin hit her');
  const strip = dm.getByRole('status', { name: 'What the table waits on' });
  await strip.getByRole('button', { name: 'Go on' }).click();
  await card.waitFor({ state: 'detached', timeout: 8000 });
  await strip.waitFor({ state: 'detached', timeout: 5000 });
  await ana.getByText('The DM goes on: Sela takes no reaction.').first().waitFor({ timeout: 8000 });
  const after = await sela();
  if (after.reactions !== 1) throw new Error(`going on spent her reaction: ${after.reactions}`);
  await shot(ana, 'ana_dm_went_on');
});

await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log('\nevery step went');
