// A choice the words make the caster's, in a real browser against a real
// table (the owner: "Conjure minor elementals shouldn't pick a type
// automatically the player should have to, they may not even know the other
// creatures resistances"): the DM gives Sela Chromatic Orb; in the chapel
// fight, on her turn, Ana casts it at a goblin on her phone, and a card asks
// the type of orb before anything is spent — a button for each of its six
// types and Cancel, none chosen for her, nothing spent while she chooses; she
// picks Fire, the orb hits, and the cast's line in the log and its rolls say
// Fire ("hit, 12 fire damage"). Then a choice made as a hit lands (the owner:
// "it should be with each attack"): the DM gives Sela a Javelin of Lightning
// ("you can have it deal Lightning damage instead of Piercing damage"); on
// her next turn (the DM's call, advantage, till one hits) her throw hits, and
// a card is in front on Ana's phone at once — Piercing or Lightning, its
// seconds counting — while the DM's screen says the table waits on her; the
// DM answers it for her from there (Answer, beside Go on): Lightning, and the
// damage roll says it. Screenshots of each step.
//
//   node tests/e2e/choices.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party --wizard (Ana's Sela, a wizard) and --seed 5 (the dice from a
// start where the orb hits).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/choices.mjs <host.json> <out dir>');
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
  console.log(`\nthe orb's type was hers to choose, and Fire was said; ${n} screenshots in ${out}`);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');

const turnNow = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);

// The DM's Next turn until the fight bar says it's `who`'s turn (Ben isn't
// here: the DM ends Brakka's anyway).
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

// The card the table puts in front of Ana (it opens by itself, or from its pill
// when it came while she was tapping).
async function cardOnAna(name) {
  const card = ana.getByRole('dialog', { name });
  const opened = await card.waitFor({ timeout: 4000 }).then(
    () => true,
    () => false,
  );
  if (!opened) {
    await ana.locator('button.waiting').click({ timeout: 4000 });
    await card.waitFor({ timeout: 4000 });
  }
  return card;
}

// What a page's log holds: each entry's words (a line's text, a roll's label).
const logWords = (page) =>
  page.evaluate(() => (window.hexmap.game.view.log ?? []).map((e) => `${e.kind ?? ''}|${e.label ?? ''}|${e.text ?? ''}`));

let ok = await step('Ana joins as Sela; the DM gives Sela Chromatic Orb on her card', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await dm.locator('.book').getByRole('button', { name: /^Sela/ }).first().click();
  await dm.getByRole('tab', { name: 'Spells' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a spell (any list, any level)' });
  await give.locator('input[type=search]').fill('chromatic orb');
  await give.getByRole('button', { name: 'Give Chromatic Orb' }).click({ timeout: 8000 });
  // a wizard's spellbook has it now; the DM puts it on her prepared list
  const given = dm.locator('.row').filter({ hasText: /Chromatic Orb \(/ }).first();
  await given.getByRole('button', { name: 'Prepare' }).click({ timeout: 8000 });
  await dm.locator('.row').filter({ hasText: /● Chromatic Orb \(/ }).first().waitFor({ timeout: 5000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.locator('.row').filter({ hasText: /Chromatic Orb \(/ }).first().waitFor({ timeout: 8000 });
  await shot(ana, 'ana_spell_given');
});

let goblin = null;
ok = ok && (await step('the chapel fight: started, initiative rolled, the goblins revealed, the party inside by them', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click().catch(() => {});
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 });
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Reveal them all' }).click().catch(() => {});
  await dm.waitForTimeout(600);
  const where = await dm.evaluate(() => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gob = toks.find((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? ''));
    const c = document.querySelector('canvas');
    if (!gob || !c?.screenOf) return null;
    return { at: c.screenOf(gob.id), px: c.pxPerHex(), gob: { id: gob.id, name: gob.name } };
  });
  expect(where, 'no goblin on the DM’s map');
  goblin = where.gob;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 4, where.at.y);
  await dm.waitForTimeout(600);
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForFunction(() => window.hexmap.game.scene.role === 'battle' && window.hexmap.game.scene.turns?.mode === 'ordered', null, { timeout: 8000 });
  await shot(dm, 'dm_order');
}));

ok = ok && (await step('on Sela’s turn Ana casts Chromatic Orb at the goblin: before anything is spent, a card asks the type of orb — six types and Cancel, none chosen for her', async () => {
  await nextUntil('Sela');
  await ana.locator('.turn').filter({ hasText: /Your turn: Sela/ }).waitFor({ timeout: 5000 });
  const slotsBefore = await ana.evaluate(() => {
    const g = window.hexmap.game;
    const sela = Object.values(g.view.actors ?? {}).find((a) => a.name === 'Sela');
    return Number(((sela?.resources ?? {}).slot_1 ?? {}).current ?? -1);
  });
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Chromatic Orb \(/ }).first();
  await row.getByRole('button', { name: 'Cast', exact: true }).click();
  await ana.getByText(/tap a creature/).waitFor({ timeout: 5000 });
  // the goblin, on her map
  await ana.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((x) => x.id === id), goblin.id, { timeout: 5000 });
  const at = await ana.evaluate((id) => {
    const c = document.querySelector('canvas');
    return c?.screenOf ? c.screenOf(id) : null;
  }, goblin.id);
  expect(at, 'the goblin isn’t on Ana’s screen');
  await ana.mouse.click(at.x, at.y);
  await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Do it' }).click();
  const card = await cardOnAna('Your choice');
  await card.getByText(/Chromatic Orb: the type of orb you create/).waitFor({ timeout: 3000 });
  for (const ty of ['Acid', 'Cold', 'Fire', 'Lightning', 'Poison', 'Thunder', 'Cancel: spend nothing']) {
    expect(await card.getByRole('button', { name: ty, exact: true }).count(), `no ${ty} button on the card`);
  }
  // nothing spent while she chooses
  const slotsNow = await ana.evaluate(() => {
    const g = window.hexmap.game;
    const sela = Object.values(g.view.actors ?? {}).find((a) => a.name === 'Sela');
    return Number(((sela?.resources ?? {}).slot_1 ?? {}).current ?? -1);
  });
  expect(slotsNow === slotsBefore, `a slot was spent before she chose (${slotsBefore} → ${slotsNow})`);
  await shot(ana, 'ana_orb_card');
}));

ok = ok && (await step('she picks Fire: the cast goes, and the cast’s line and its rolls say Fire', async () => {
  const card = ana.getByRole('dialog', { name: 'Your choice' });
  // (a card's first moment's taps are its own: it settles)
  await ana.waitForTimeout(700);
  await card.getByRole('button', { name: 'Fire', exact: true }).click();
  await card.waitFor({ state: 'detached', timeout: 6000 });
  await ana.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => /Chromatic Orb \(Fire\)/.test(`${e.text ?? ''} ${e.label ?? ''}`)), null, { timeout: 8000 });
  const words = await logWords(ana);
  const line = words.find((w) => /casts Chromatic Orb \(Fire\) at/.test(w));
  expect(line, `no cast's line naming Fire: ${words.slice(-6).join(' / ')}`);
  expect(/(hit|critical hit), \d+ fire damage/.test(line), `the orb hits, and its damage is fire (a --seed where it hits: 5): ${line}`);
  const rolls = words.filter((w) => /^roll\|Chromatic Orb \(Fire\) → /.test(w));
  expect(rolls.length >= 2, `its attack and its damage rolls say Fire: ${words.filter((w) => w.startsWith('roll|')).slice(-4).join(' / ')}`);
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText(/casts Chromatic Orb \(Fire\) at/).first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_orb_fire_said');
  // the DM's log says it too
  const dmWords = await logWords(dm);
  expect(dmWords.some((w) => /casts Chromatic Orb \(Fire\) at/.test(w)), 'the DM’s log doesn’t say Fire');
  await shot(dm, 'dm_orb_fire_said');
}));

ok = ok && (await step('the DM gives Sela a Javelin of Lightning, and it’s in her hand', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Sela/ }).first().click();
  await dm.getByRole('tab', { name: 'Inventory' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a magic item' });
  await give.locator('input[type=search]').fill('javelin of lightning');
  await give.getByRole('button', { name: /^Javelin of Lightning/ }).first().click({ timeout: 8000 });
  const row = dm.locator('.row').filter({ hasText: /Javelin of Lightning/ }).first();
  await row.getByRole('button', { name: 'Equip' }).click({ timeout: 8000 });
  await dm.getByText(/Lightning damage instead of Piercing: asked on each hit/).first().waitFor({ timeout: 5000 });
  await shot(dm, 'dm_javelin_given');
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
}));

// The DM's Next turn until it's `who`'s turn in a later round than now.
async function nextRoundOf(who) {
  const round = await dm.evaluate(() => Number(window.hexmap.game.scene.turns?.round ?? 0));
  for (let i = 0; i < 20; i++) {
    const now = await dm.evaluate(() => Number(window.hexmap.game.scene.turns?.round ?? 0));
    if (now > round && (await dm.locator('.fightbar').getByText(new RegExp(`${who}’s turn`)).count())) return;
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
  throw new Error(`no later turn of ${who}'s`);
}

// On Sela's next turn, her javelin at a goblin still standing (the orb may have
// killed the first); a miss asks nothing: the next round, again.
ok = ok && (await step('her throw hits: a card in front on Ana’s phone at once — Piercing or Lightning, its seconds counting — and the DM’s screen says the table waits on her', async () => {
  const target = await dm.evaluate((first) => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gob = toks.find((t) => /^Goblin Warrior \d/.test(t.name ?? '') && t.id !== first);
    return gob ? { id: gob.id, name: gob.name } : null;
  }, goblin.id);
  expect(target, 'no goblin left standing');
  let hit = false;
  for (let round = 0; round < 6 && !hit; round++) {
    await nextRoundOf('Sela');
    // (the DM's call, advantage on her throw: a javelin at +1 against AC 15 is a long shot)
    await dm.locator('.book').getByRole('button', { name: /^Sela/ }).first().click();
    await dm.getByRole('tab', { name: 'Combat' }).first().click();
    await dm.getByRole('combobox', { name: 'Their next attack roll' }).first().selectOption({ label: 'With advantage' });
    await dm.waitForFunction(() => Object.values(window.hexmap.game.view.actors ?? {}).some((a) => a.name === 'Sela' && ((a.ext ?? {}).srd5e ?? {}).next_edge === 'advantage'), null, { timeout: 5000 }).catch(() => {});
    await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
    await ana.locator('.turn').filter({ hasText: /Your turn: Sela/ }).waitFor({ timeout: 5000 });
    await ana.getByRole('tab', { name: /Character/ }).click();
    await ana.getByRole('tab', { name: 'Combat' }).click();
    const row = ana.locator('.row').filter({ hasText: /^Javelin of Lightning/ }).first();
    await row.getByRole('button', { name: 'Attack' }).click();
    await ana.getByText(/tap a creature/).waitFor({ timeout: 5000 });
    const at = await ana.evaluate((id) => {
      const c = document.querySelector('canvas');
      return c?.screenOf ? c.screenOf(id) : null;
    }, target.id);
    expect(at, 'the goblin isn’t on Ana’s screen');
    const before = await ana.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length);
    await ana.mouse.click(at.x, at.y);
    await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
    await ana.getByRole('button', { name: 'Do it' }).click();
    await ana.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length > n, before, { timeout: 8000 });
    // a hit brings the card at once; a miss, nothing
    hit = await ana
      .getByRole('dialog', { name: 'Your hit' })
      .waitFor({ timeout: 2500 })
      .then(
        () => true,
        () => false,
      );
  }
  expect(hit, 'four throws, no hit');
  const card = ana.getByRole('dialog', { name: 'Your hit' });
  await card.getByText(/Your (critical )?hit with Javelin of Lightning on the Goblin/).waitFor({ timeout: 3000 });
  await card.getByText(/Javelin of Lightning's damage — Piercing · Lightning/).waitFor({ timeout: 3000 });
  expect(await card.getByRole('button', { name: 'Piercing', exact: true }).count(), 'no Piercing button');
  expect(await card.getByRole('button', { name: 'Lightning', exact: true }).count(), 'no Lightning button');
  expect(!(await card.getByRole('button', { name: 'Not this time' }).count()), 'its own damage isn’t optional');
  expect(await card.getByRole('timer').count(), 'no seconds on the card');
  await shot(ana, 'ana_hit_card');
  await dm.locator('.waitstrip').getByText(/Waiting on Ana: a choice for Sela's hit/).waitFor({ timeout: 5000 });
  await shot(dm, 'dm_waiting_on_ana');
}));

ok = ok && (await step('the DM answers it for her — Lightning — and the damage roll says it', async () => {
  const strip = dm.locator('.waitstrip');
  await strip.getByRole('button', { name: 'Answer' }).click();
  const card = dm.getByRole('dialog', { name: /^For Ana: your hit/ });
  await card.waitFor({ timeout: 5000 });
  await shot(dm, 'dm_answers_for_ana');
  await dm.waitForTimeout(700);
  await card.getByRole('button', { name: 'Lightning', exact: true }).click();
  await card.waitFor({ state: 'detached', timeout: 6000 });
  await ana.getByRole('dialog', { name: 'Your hit' }).waitFor({ state: 'detached', timeout: 6000 });
  await ana.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => e.kind === 'roll' && /^Javelin of Lightning damage \(Lightning\)/.test(e.label ?? '')), null, { timeout: 8000 });
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await shot(ana, 'ana_lightning_said');
}));

await finish();
