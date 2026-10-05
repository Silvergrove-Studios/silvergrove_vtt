// The DM's hand on anything, in a real browser against a real table (the
// owner: "even in the high automation mode, the DM should be able to
// override anything at any time in combat or on a sheet"): in the chapel
// fight the DM opens a goblin's Adjust tab and sets its AC to 17 — the tab
// and the stat block say "AC 17 · 15 computed, set by the DM", the log says
// so to the DM alone — and a player's attack meets 17; a goblin's hit on Ana's
// wizard puts a Shield card on her phone, she casts it and her reaction is
// spent, and the DM gives it back from her Adjust tab. Screenshots of each step
// go to the output folder; a step that does not happen fails the run.
//
//   node tests/e2e/overrides.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, started with --party --wizard
// (Ana's character is Sela, a wizard with Shield and Fire Bolt) and --seed 12
// (the dice from a known start: the goblin's roll a hit that Shield turns aside).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/overrides.mjs <host.json> <out dir>');
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

function expect(cond, what) {
  if (!cond) throw new Error(what);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

// A token's creature as a page knows it: its derived numbers, its pools, its turn's counters.
const creature = (page, name) =>
  page.evaluate((who) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === who);
    const a = t ? g.view.actors?.[t.actor] : null;
    if (!t) return null;
    return {
      id: t.id,
      actor: t.actor,
      pos: t.pos,
      ac: a?.derived?.srd5e?.ac?.total,
      hp: a?.resources?.srd5e?.hp?.current,
      slot1: a?.resources?.srd5e?.slot_1?.current,
      reactions: g.view.turns?.counters?.[`token:${t.id}`]?.reactions,
    };
  }, name);

// What a page's log holds: each entry's words (a line's text, a roll's label).
const logWords = (page) => page.evaluate(() => (window.hexmap.game.view.log ?? []).map((e) => `${e.kind ?? ''}|${e.label ?? ''}|${e.text ?? ''}`));

const turnNow = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);

// The DM's Next turn until the fight bar says it's `who`'s turn.
async function nextUntil(who) {
  const bar = dm.locator('.fightbar');
  for (let i = 0; i < 16; i++) {
    if (await bar.getByText(new RegExp(`${who}’s turn`)).count()) return;
    const was = await turnNow();
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    const asks = bar.getByRole('group', { name: /End the turn anyway\?|End this turn too\?/ });
    await dm.waitForFunction(
      (b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b || !!document.querySelector('.fightbar .buttons.ask'),
      was,
      { timeout: 5000 },
    );
    if (await asks.count()) await asks.getByRole('button', { name: /^End/ }).first().click();
    await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was, { timeout: 5000 });
  }
  await bar.getByText(new RegExp(`${who}’s turn`)).waitFor({ timeout: 2000 });
}

// A creature chosen in the DM's turn order, on one of its tabs.
async function choose(name, tab) {
  await dm.locator('.order .row').filter({ hasText: name }).first().click();
  const chosen = dm.locator('.chosen');
  await chosen.waitFor({ timeout: 5000 });
  if (tab) await chosen.getByRole('tab', { name: tab, exact: true }).click({ timeout: 5000 });
  return chosen;
}

let ok = await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  // a player's own sheet has no Adjust tab (the table's setting is off)
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).waitFor({ timeout: 8000 });
  expect((await ana.getByRole('tab', { name: 'Adjust', exact: true }).count()) === 0, 'Ana’s sheet has an Adjust tab: the DM’s alone');
  await shot(ana, 'ana_joined');
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
  await shot(dm, 'dm_order');
}));

let goblin = null;
ok = ok && (await step('the DM puts the party inside and Sela beside a goblin', async () => {
  const where = await dm.evaluate(() => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gob = toks.find((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? ''));
    const c = document.querySelector('canvas');
    if (!gob || !c?.screenOf) return null;
    return { at: c.screenOf(gob.id), px: c.pxPerHex(), gob: { id: gob.id, name: gob.name, actor: gob.actor } };
  });
  expect(where, 'no goblin on the DM’s map');
  goblin = where.gob;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(600);
  const s = await creature(dm, 'Sela');
  expect(s, 'no Sela on the map');
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
}));

ok = ok && (await step('the DM opens the goblin’s Adjust tab and sets its AC to 17: “AC 17 · 15 computed, set by the DM”', async () => {
  const before = await creature(dm, goblin.name);
  expect(before.ac === 15, `the goblin's AC before: ${before.ac}`);
  const chosen = await choose(goblin.name, 'Adjust');
  await chosen.getByRole('combobox', { name: 'Number' }).selectOption({ label: 'AC' });
  await chosen.getByRole('combobox', { name: 'How' }).first().selectOption({ label: 'Set it to' });
  await chosen.getByRole('spinbutton', { name: 'Value' }).fill('17');
  await chosen.getByRole('textbox', { name: 'Why (said in the log)' }).first().fill('a shield from the chapel');
  await chosen.getByRole('button', { name: 'Change it' }).first().click();
  await chosen.getByText('AC 17 · 15 computed, set by the DM').first().waitFor({ timeout: 8000 });
  const after = await creature(dm, goblin.name);
  expect(after.ac === 17, `its AC now: ${after.ac}`);
  await shot(dm, 'dm_goblin_adjust_ac');
  // the log says so, to the DM alone (a monster's AC isn't the players' to know)
  const said = `The DM sets the ${goblin.name}'s AC to 17 (15 computed): a shield from the chapel.`;
  await dm.waitForFunction((w) => (window.hexmap.game.view.log ?? []).some((e) => e.text === w), said, { timeout: 5000 });
  expect(!(await logWords(ana)).some((w) => w.includes('AC to 17')), 'Ana’s log says the goblin’s AC');
  // its stat block says it beside its AC, and its badge
  await chosen.getByRole('tab', { name: 'Stat block', exact: true }).click();
  await chosen.getByText('AC 17 · 15 computed, set by the DM').first().waitFor({ timeout: 5000 });
  await chosen.locator('.badge').filter({ hasText: 'AC set to 17 (the DM)' }).first().waitFor({ timeout: 5000 });
  await shot(dm, 'dm_goblin_stat_block');
  // the other goblins are as they were
  const others = await dm.evaluate((id) => {
    const g = window.hexmap.game;
    return (g.scene.tokens ?? []).filter((t) => /^Goblin Warrior/.test(t.name ?? '') && t.id !== id).map((t) => g.view.actors?.[t.actor]?.derived?.srd5e?.ac?.total);
  }, goblin.id);
  expect(others.length > 0 && others.every((ac) => ac === 15), `the other goblins' AC: ${others}`);
}));

let before = null;
ok = ok && (await step('the goblin’s scimitar hits Sela; Ana casts Shield on her phone: the attack misses, her reaction is spent', async () => {
  before = await creature(dm, 'Sela');
  const chosen = await choose(goblin.name, 'Stat block');
  const row = chosen.locator('.row').filter({ hasText: /^Scimitar\./ }).first();
  await row.getByRole('button', { name: 'Use' }).click();
  const banner = dm.getByRole('group', { name: 'Choose the target' });
  await banner.waitFor({ timeout: 5000 });
  await banner.locator('.choice').filter({ hasText: /^Sela/ }).first().click();
  await banner.getByRole('button', { name: 'Done' }).click();
  const card = ana.getByRole('dialog', { name: 'Your reaction' });
  await card.waitFor({ timeout: 8000 });
  const shield = card.getByRole('button', { name: /^Shield \(a level 1 slot\): AC \d+ against this \d+: / });
  await shield.waitFor({ timeout: 3000 });
  expect(/it misses$/.test((await shield.innerText()).trim()), 'the goblin’s roll isn’t one Shield turns aside (pick another --seed)');
  await ana.waitForTimeout(700);
  await shield.click();
  await card.waitFor({ state: 'detached', timeout: 8000 });
  await dm.waitForFunction((sid) => (window.hexmap.game.view.turns?.counters?.[`token:${sid}`]?.reactions ?? 1) === 0, before.id, { timeout: 8000 });
  const after = await creature(dm, 'Sela');
  expect(after.hp === before.hp, `Sela was hurt: ${before.hp} → ${after.hp}`);
  expect(after.reactions === 0, `her reaction: ${after.reactions}`);
  await shot(ana, 'ana_shield_cast');
}));

ok = ok && (await step('the DM gives Sela back her reaction from her Adjust tab', async () => {
  const chosen = await choose('Sela', 'Adjust');
  const turn = chosen.locator('section').filter({ has: dm.getByRole('heading', { name: 'Turn' }) });
  await turn.getByText(/· this turn: \d+ action, \d+ bonus action, 0 reaction/).waitFor({ timeout: 5000 });
  await shot(dm, 'dm_sela_adjust_turn');
  await turn.getByRole('button', { name: 'Give a reaction' }).click();
  await dm.waitForFunction((sid) => window.hexmap.game.view.turns?.counters?.[`token:${sid}`]?.reactions === 1, before.id, { timeout: 8000 });
  await turn.getByText(/· this turn: \d+ action, \d+ bonus action, 1 reaction/).waitFor({ timeout: 5000 });
  await shot(dm, 'dm_sela_reaction_back');
  // said for everyone: her own phone too
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText("The DM gives Sela's reaction back (1 now).").first().waitFor({ timeout: 8000 });
  await shot(ana, 'ana_reaction_back');
}));

ok = ok && (await step('on Sela’s turn Ana’s Fire Bolt at the goblin is rolled against AC 17', async () => {
  await nextUntil('Sela');
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Fire Bolt \(/ }).first();
  await row.getByRole('button', { name: 'Cast', exact: true }).click();
  await ana.getByText(/tap a creature/).waitFor({ timeout: 5000 });
  const at = await ana.evaluate((id) => {
    const c = document.querySelector('canvas');
    return c?.screenOf ? c.screenOf(id) : null;
  }, goblin.id);
  expect(at, 'the goblin isn’t on Ana’s screen');
  await ana.mouse.click(at.x, at.y);
  await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Do it' }).click();
  // the attack roll met the AC the DM set: the DM's log says so (the goblin's AC is the DM's to know)
  const note = /^Fire Bolt → Goblin Warrior: \d+ against AC 17 \(set by the DM; 15 computed\): (it hits|it misses|a critical hit)\.$/;
  await dm.waitForFunction((src) => (window.hexmap.game.view.log ?? []).some((e) => new RegExp(src).test(String(e.text ?? ''))), note.source, { timeout: 10000 });
  await dm.getByRole('tab', { name: 'Chat & rolls' }).click().catch(() => {});
  await dm.getByText(note).first().waitFor({ timeout: 5000 }).catch(() => {});
  await shot(dm, 'dm_fire_bolt_against_17');
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText(/Sela casts Fire Bolt at/).first().waitFor({ timeout: 8000 });
  expect(!(await logWords(ana)).some((w) => /against AC 17/.test(w)), 'Ana’s log says the goblin’s AC');
  await shot(ana, 'ana_fire_bolt');
}));

for (const [, p] of pages) await p.context().close();
await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log(`\nevery step went; ${n} screenshots in ${out}`);
