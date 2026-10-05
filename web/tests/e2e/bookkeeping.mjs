// How much the rules do is the DM's (the owner: "the level of automation and
// alot of hidden mechanics is really up to the dm"), in a real browser against
// a real table: the DM sets the sheets to Bookkeeping in the settings (what the
// sheets' buttons do) and Ana's sheet follows at once — a By hand tab, Cast gone,
// her spell slots counters she ticks herself (and the table hears of it); in
// the chapel fight the DM wounds a goblin, its Bloodied mark on her map; the DM
// says the players see nothing of a monster's health, and the mark leaves her
// map while the DM's keeps it; at Exact its hit points show under it on both.
// Screenshots of each step.
//
//   node tests/e2e/bookkeeping.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party --wizard (Ana's Sela, a wizard with spell slots).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/bookkeeping.mjs <host.json> <out dir>');
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
  console.log(`\nthe table ran at the DM's level: Ana's sheet kept counters, and the goblin's health was the DM's to show; ${n} screenshots in ${out}`);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');

// A ruleset's setting, from the DM's settings window (Rules settings, or Table
// settings where the table has levels): its select, by its title.
async function setRule(title, option) {
  await dm.getByRole('button', { name: /^(Rules|Table) settings/ }).first().click();
  const dialog = dm.getByRole('dialog', { name: /^(Rules|Table) settings$/ });
  await dialog.waitFor({ timeout: 5000 });
  await dialog.getByRole('combobox', { name: title }).selectOption({ label: option });
  await dm.waitForTimeout(800);
  await shot(dm, `dm_rules_${title.replace(/[^a-z]+/gi, '_').slice(0, 24)}`);
  await dialog.getByRole('button', { name: 'Done' }).click();
  await dialog.waitFor({ state: 'detached', timeout: 5000 });
}

// Sela's spell slots of a level, as Ana's page holds them.
const slot = (level) =>
  ana.evaluate((lvl) => {
    const sela = Object.values(window.hexmap.game.view.actors ?? {}).find((a) => a.name === 'Sela');
    return Number((((sela?.resources ?? {}).srd5e ?? {})[`slot_${lvl}`] ?? {}).current ?? -1);
  }, level);

// A token's tags and hit points as a page's scene holds them.
const tokenOn = (page, id) => page.evaluate((tid) => {
  const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === tid);
  return t ? { tags: t.tags ?? [], hp: t.hp ?? null } : null;
}, id);

let ok = await step('Ana joins as Sela; her full sheet casts (Cast on her spells)', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: 'Spells' }).click({ timeout: 8000 });
  await ana.getByRole('button', { name: 'Cast', exact: true }).first().waitFor({ timeout: 8000 });
  await ana.locator('.stat').filter({ hasText: 'Level 1' }).first().scrollIntoViewIfNeeded();
  await shot(ana, 'ana_full_spells');
});

ok = ok && (await step('the DM sets the table to Bookkeeping: what the sheets’ buttons do', async () => {
  await setRule('What the sheets\' buttons do', 'Bookkeeping: the sheets keep the numbers; players tick slots and uses, mark hit points and set conditions by hand');
}));

ok = ok && (await step('Ana’s sheet follows: a By hand tab, no Cast, her slots counters she ticks — and the table hears of it', async () => {
  await ana.getByRole('tab', { name: 'By hand' }).waitFor({ timeout: 10000 });
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.locator('.stat').filter({ hasText: 'Level 1' }).first().waitFor({ timeout: 8000 });
  expect((await ana.getByRole('button', { name: /^Cast/ }).count()) === 0, 'Cast is still on her sheet');
  await ana.locator('.stat').filter({ hasText: 'Level 1' }).first().scrollIntoViewIfNeeded();
  await shot(ana, 'ana_book_spells');
  const before = await slot(1);
  expect(before > 0, `no level 1 slots to tick: ${before}`);
  await ana.locator('.stat').filter({ hasText: 'Level 1' }).first().getByRole('button', { name: 'Spend' }).click();
  await ana.waitForFunction((b) => {
    const sela = Object.values(window.hexmap.game.view.actors ?? {}).find((a) => a.name === 'Sela');
    return Number((((sela?.resources ?? {}).srd5e ?? {}).slot_1 ?? {}).current ?? -1) === b - 1;
  }, before, { timeout: 8000 });
  await dm.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => /Sela spends a level 1 spell slot/.test(String(e.text ?? ''))), null, { timeout: 8000 });
  await shot(ana, 'ana_slot_ticked');
}));

ok = ok && (await step('By hand: a condition a tap, and a note', async () => {
  await ana.getByRole('tab', { name: 'By hand' }).click();
  await ana.getByRole('button', { name: 'Prone', exact: true }).click({ timeout: 8000 });
  await ana.getByRole('button', { name: 'Prone ✓' }).waitFor({ timeout: 8000 });
  await ana.getByLabel('A note (Blessed)').fill('Blessed');
  await ana.getByLabel('Its words, if any (+1d4 to attacks and saves)').fill('+1d4 to attacks and saves');
  await ana.getByRole('button', { name: 'Add the note' }).click();
  await ana.getByText('Blessed, +1d4 to attacks and saves').first().waitFor({ timeout: 8000 });
  await shot(ana, 'ana_by_hand');
}));

let goblin = null;
ok = ok && (await step('the chapel fight: started, the goblins revealed, the party beside one', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click().catch(() => {});
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 }).catch(() => {});
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Reveal them all' }).click().catch(() => {});
  await dm.waitForTimeout(600);
  const where = await dm.evaluate(() => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gob = toks.find((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? '') && t.actor);
    const c = document.querySelector('canvas');
    if (!gob || !c?.screenOf) return null;
    return { at: c.screenOf(gob.id), px: c.pxPerHex(), gob: { id: gob.id, name: gob.name, actor: gob.actor } };
  });
  expect(where, 'no goblin on the DM’s map');
  goblin = where.gob;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 2, where.at.y);
  await dm.waitForTimeout(600);
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id), goblin.id, { timeout: 8000 });
  await shot(dm, 'dm_fight');
}));

ok = ok && (await step('the DM wounds the goblin on its stat block: Bloodied, on Ana’s map too (the players see the marks)', async () => {
  const hp = await dm.evaluate((aid) => ((((window.hexmap.game.view.actors ?? {})[aid] ?? {}).resources ?? {}).srd5e ?? {}).hp ?? null, goblin.actor);
  expect(hp && hp.max > 1, `the goblin's hit points aren't on the DM's page: ${JSON.stringify(hp)}`);
  const amount = Math.ceil(Number(hp.max) / 2);
  // its row in the order, by its own name exactly ("Goblin Warrior" isn't "Goblin
  // Warrior 2", nor "Goblin Warrior JA", a creature spawned out of the players'
  // sight; the current one's row says its turn after its name), chosen
  const idx = await dm.evaluate((name) => [...document.querySelectorAll('.fightpanel .order button')].findIndex((b) => {
    const n = b.querySelector('.name');
    return !!n && [...n.childNodes].filter((c) => c.nodeType === Node.TEXT_NODE).map((c) => c.textContent).join('').trim() === name;
  }), goblin.name);
  expect(idx >= 0, `no row in the order named ${goblin.name}`);
  await dm.locator('.fightpanel .order button').nth(idx).click();
  await dm.waitForFunction((i) => !!document.querySelectorAll('.fightpanel .order button')[i]?.classList.contains('on'), idx, { timeout: 5000 });
  const block = dm.locator('.fightpanel .chosen');
  // (the damage is on its stat block: its card's Stat block tab, where the card has tabs)
  const statTab = block.getByRole('tab', { name: 'Stat block' });
  if (await statTab.count()) await statTab.first().click();
  await block.getByLabel('Damage (or healing)').fill(String(amount));
  await block.getByRole('button', { name: 'Apply' }).first().click();
  const marked = (page) => page.waitForFunction((id) => ((window.hexmap.game.scene.tokens ?? []).find((t) => t.id === id)?.tags ?? []).includes('bloodied'), goblin.id, { timeout: 8000 })
    .catch(async () => { throw new Error(`${goblin.name} isn't Bloodied on the ${page === dm ? 'DM' : 'player'}'s map: ${JSON.stringify(await tokenOn(page, goblin.id))}, ${JSON.stringify(await dm.evaluate((aid) => ((((window.hexmap.game.view.actors ?? {})[aid] ?? {}).resources ?? {}).srd5e ?? {}).hp ?? null, goblin.actor))}`); });
  await marked(dm);
  await marked(ana);
  await shot(ana, 'ana_goblin_bloodied');
}));

ok = ok && (await step('the DM: players see nothing of a monster’s health — the mark leaves Ana’s map, the DM’s keeps it', async () => {
  await setRule('What players see of a monster\'s health', 'Nothing: the DM describes it');
  await ana.waitForFunction((id) => {
    const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
    return !!t && !(t.tags ?? []).includes('bloodied');
  }, goblin.id, { timeout: 10000 });
  const mine = await tokenOn(dm, goblin.id);
  expect(mine && mine.tags.includes('bloodied'), `the DM's map lost the mark: ${JSON.stringify(mine)}`);
  await shot(ana, 'ana_goblin_no_mark');
  await shot(dm, 'dm_goblin_marked');
}));

ok = ok && (await step('and at Exact its hit points show under it, on Ana’s map and the DM’s', async () => {
  await setRule('What players see of a monster\'s health', 'Exact: its marks and its hit points');
  await ana.waitForFunction((id) => {
    const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
    return !!t && Array.isArray(t.hp) && (t.tags ?? []).includes('bloodied');
  }, goblin.id, { timeout: 10000 });
  const theirs = await tokenOn(ana, goblin.id);
  const mine = await tokenOn(dm, goblin.id);
  expect(JSON.stringify(theirs.hp) === JSON.stringify(mine.hp), `the same numbers on both: ${JSON.stringify(theirs.hp)} / ${JSON.stringify(mine.hp)}`);
  await shot(ana, 'ana_goblin_exact');
}));

await finish();
