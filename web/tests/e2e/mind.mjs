// A fight in the theatre of the mind, in a real browser against a real table
// (the owner's plan: where fights happen is the DM's — on maps, in the
// theatre of the mind, or each fight its own). The DM lets each fight decide,
// gives Sela Burning Hands and makes a fight with no map: three goblins,
// started in the theatre of the mind. No map anywhere: the DM's screen and
// both players' Map tabs show who's in the fight — names, health, the order.
// On Sela's turn Ana picks a goblin from the list for her Fire Bolt; on her
// next she casts Burning Hands, naming two goblins from the list ("Who does
// your Burning Hands catch?"), and nothing lands until the DM confirms it on
// a card (Apply), though this table approves nothing else. The DM adds a
// wolf, with no token to put down; the fight ends. Screenshots of each step.
//
//   node tests/e2e/mind.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party --wizard --seed 12 (Ana's Sela, a wizard; Ben's Brakka).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/mind.mjs <host.json> <out dir>');
  process.exit(2);
}
mkdirSync(out, { recursive: true });
const info = JSON.parse(readFileSync(infoPath, 'utf8'));
const browser = await chromium.launch({ channel: process.env.HEXMAP_BROWSER ?? 'chrome', headless: true });
const problems = [];
const pages = [];
let n = 0;
// what each screen sent the table (an intent's exact shape)
const sent = new Map();

async function open(url, viewport, name) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, hasTouch: viewport.width < 600 });
  const page = await ctx.newPage();
  sent.set(name, []);
  page.on('websocket', (ws) =>
    ws.on('framesent', (f) => {
      try {
        sent.get(name).push(JSON.parse(String(f.payload)));
      } catch {
        /* not a message */
      }
    }),
  );
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
  console.log(`\na fight in the theatre of the mind, its targets and its area chosen from the list, the DM confirming; ${n} screenshots in ${out}`);
}

const logWords = (page) => page.evaluate(() => (window.hexmap.game.view.log ?? []).map((e) => `${e.kind ?? ''}|${e.label ?? ''}|${e.text ?? ''}`));
/** The fight's list on a page: each row's words. */
const listOf = (page) => page.getByRole('region', { name: "Who's in the fight" });
/** The creatures on a page's scene, as it was sent them. */
const creatures = (page) => page.evaluate(() => (window.hexmap.game.scene.tokens ?? []).map((t) => ({ id: t.id, name: t.name, actor: t.actor, tags: t.tags ?? [] })));

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

/** Next turn on the DM's bar until it is `who`'s turn (a player's turn ended as the bar asks). */
async function toTurnOf(who) {
  for (let i = 0; i < 14; i += 1) {
    const up = await dm.evaluate(() => {
      const g = window.hexmap.game;
      const t = g.scene.turns ?? {};
      const entry = (t.order ?? [])[t.turn ?? 0];
      return (g.scene.tokens ?? []).find((x) => x.id === entry)?.name ?? '';
    });
    if (up === who) return;
    const bar = dm.locator('.fightbar');
    await bar.getByRole('button', { name: /Next turn/ }).click();
    // (the bar asks before it ends a player's turn with an action left, or one a player ended)
    const endIt = bar.getByRole('button', { name: /^End (it|.+’s turn)$/ });
    if (await endIt.count().catch(() => 0)) await endIt.first().click().catch(() => {});
    await dm.waitForTimeout(700);
  }
  throw new Error(`never ${who}'s turn`);
}

let ok = await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).first().waitFor({ timeout: 10000 });
});

ok = ok && (await step('the DM lets each fight decide where it happens (Table settings)', async () => {
  await dm.getByRole('button', { name: /^Table settings/ }).click();
  const box = dm.getByRole('dialog', { name: 'Table settings' });
  await box.waitFor({ timeout: 5000 });
  await box.getByRole('combobox', { name: 'Where fights happen' }).selectOption('per_fight');
  await dm.waitForFunction(() => window.hexmap.game.dm?.table?.space === 'per_fight', null, { timeout: 5000 });
  await shot(dm, 'dm_each_fight_decides');
  await box.getByRole('button', { name: 'Done' }).click();
  await box.waitFor({ state: 'detached', timeout: 5000 });
}));

ok = ok && (await step('the DM gives Sela Burning Hands', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Sela/ }).first().click();
  await dm.getByRole('tab', { name: 'Spells' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a spell (any list, any level)' });
  await give.locator('input[type=search]').fill('burning hands');
  await give.getByRole('button', { name: 'Give Burning Hands' }).click({ timeout: 8000 });
  // a wizard's spellbook has it now; the DM puts it on her prepared list
  const given = dm.locator('.row').filter({ hasText: /Burning Hands \(/ }).first();
  await given.getByRole('button', { name: 'Prepare' }).click({ timeout: 8000 });
  await dm.locator('.row').filter({ hasText: /● Burning Hands \(/ }).first().waitFor({ timeout: 5000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
}));

ok = ok && (await step('a fight with no map: three goblins, started in the theatre of the mind', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click().catch(() => {});
  await dm.getByRole('button', { name: '+ New fight' }).click();
  const card = dm.locator('.fightcard');
  await card.waitFor({ timeout: 8000 });
  await card.getByRole('combobox', { name: /The map it's on/ }).selectOption('');
  await dm.waitForFunction(() => (window.hexmap.game.dm.encounters ?? []).some((e) => e.name === 'A new fight' && e.map === ''), null, { timeout: 5000 });
  await card.getByRole('spinbutton', { name: /How many/ }).fill('3');
  await card.getByRole('checkbox', { name: /hidden until you reveal them/ }).uncheck();
  await card.getByRole('searchbox', { name: 'Find a creature' }).fill('goblin warrior');
  await card.locator('.found').filter({ hasText: /^Goblin Warrior/ }).first().click({ timeout: 8000 });
  await card.locator('.line').filter({ hasText: 'Goblin Warrior' }).waitFor({ timeout: 8000 });
  // where the table leaves it to each fight, Start says where; with no map, in the mind
  expect((await card.getByRole('button', { name: 'Start on its map' }).count()) === 0, 'a fight with no map offered to start on a map');
  await shot(dm, 'dm_fight_no_map');
  await card.getByRole('button', { name: 'Start in the theatre of the mind' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 10000 });
  await dm.locator('.fightbar').getByText('in the theatre of the mind').waitFor({ timeout: 5000 });
  const list = listOf(dm);
  await list.waitFor({ timeout: 8000 });
  expect((await dm.locator('.mapholder canvas').count()) === 0, 'a map on the DM’s screen');
  const names = await list.locator('.row .name').allInnerTexts();
  expect(names.filter((x) => /Goblin Warrior/.test(x)).length === 3 && names.some((x) => /Sela/.test(x)) && names.some((x) => /Brakka/.test(x)), `who’s in the fight: ${names.join(', ')}`);
  const scene = await dm.evaluate(() => ({ space: window.hexmap.game.scene.space, map: window.hexmap.game.scene.map }));
  expect(scene.space === 'mind' && scene.map === '', `the scene: ${JSON.stringify(scene)}`);
  await shot(dm, 'dm_who_is_in_the_fight');
}));

ok = ok && (await step('the players’ Map tab: who’s in the fight, no map', async () => {
  await ana.getByRole('tab', { name: /Map/ }).click();
  for (const [page, name] of [[ana, 'ana'], [ben, 'ben']]) {
    const list = listOf(page);
    await list.waitFor({ timeout: 8000 });
    const names = await list.locator('.row .name').allInnerTexts();
    expect(names.filter((x) => /Goblin Warrior/.test(x)).length === 3, `${name}'s list: ${names.join(', ')}`);
    expect((await page.locator('.mapwrap canvas').count()) === 0, `a map on ${name}’s screen`);
    await shot(page, `${name}_who_is_in_the_fight`);
  }
}));

ok = ok && (await step('initiative: the order on every list', async () => {
  await dm.locator('.fightbar').getByRole('button', { name: 'Roll initiative' }).click();
  await dm.waitForFunction(() => window.hexmap.game.scene.turns?.running === true, null, { timeout: 10000 });
  await ana.waitForFunction(() => window.hexmap.game.scene.turns?.running === true, null, { timeout: 10000 });
  await listOf(ana).locator('.row.current').waitFor({ timeout: 5000 });
  expect((await listOf(ana).locator('.init').count()) >= 5, 'no order on Ana’s list');
  await shot(ana, 'ana_order');
}));

let goblins = [];
let gob1 = null;
ok = ok && (await step('on Sela’s turn Ana picks a goblin from the list for her Fire Bolt', async () => {
  await toTurnOf('Sela');
  goblins = (await creatures(dm)).filter((c) => /^Goblin Warrior/.test(c.name));
  expect(goblins.length === 3, `three goblins: ${goblins.map((g) => g.name).join(', ')}`);
  gob1 = goblins[0];
  const before = sent.get('ana').length;
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Fire Bolt \(/ }).first();
  await row.getByRole('button', { name: 'Cast', exact: true }).click();
  // the pick waits on the list, where the map would be
  const list = listOf(ana);
  await list.getByText('Fire Bolt: choose a creature below, then Done.').waitFor({ timeout: 5000 });
  await shot(ana, 'ana_fire_bolt_pick');
  await list.getByRole('button', { name: `Choose ${gob1.name}`, exact: true }).click();
  await list.getByRole('button', { name: 'Done' }).click();
  await ana.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => /casts Fire Bolt at/.test(e.text ?? '')), null, { timeout: 8000 });
  const went = sent.get('ana').slice(before).map((m) => m.intent).filter((i) => i?.kind === 'action' && i.action === 'cast');
  expect(went.length === 1 && went[0].ctx?.target === `token:${gob1.id}` && !went[0].ctx?.no_target, `the cast went at the goblin: ${JSON.stringify(went.map((i) => i.ctx))}`);
  const words = await logWords(ana);
  const line = words.find((w) => /casts Fire Bolt at/.test(w));
  expect(line && !/out of range|can't be chosen/.test(line), `nothing refused for its distance: ${line}`);
  await shot(ana, 'ana_fire_bolt_done');
}));

ok = ok && (await step('on her next turn Ana casts Burning Hands, naming two goblins; nothing lands until the DM applies it', async () => {
  await toTurnOf('Brakka');
  await toTurnOf('Sela');
  const hp = await dm.evaluate((ids) => Object.fromEntries(ids.map((id) => [id, window.hexmap.game.view.actors?.[id]?.resources?.srd5e?.hp?.current])), goblins.map((g) => g.actor));
  const before = sent.get('ana').length;
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Burning Hands \(/ }).first();
  await row.getByRole('button', { name: 'Cast', exact: true }).click();
  const list = listOf(ana);
  await list.getByText('Who does your Burning Hands catch? Choose each creature it catches below, then Done.').waitFor({ timeout: 5000 });
  // two of them, from the list
  for (const g of goblins.slice(1)) await list.getByRole('button', { name: `Choose ${g.name}`, exact: true }).click();
  await list.getByText(`Burning Hands catches ${goblins[1].name}, ${goblins[2].name}`).waitFor({ timeout: 3000 });
  await shot(ana, 'ana_burning_hands_caught');
  await list.getByRole('button', { name: 'Done' }).click();
  const went = sent.get('ana').slice(before).map((m) => m.intent).filter((i) => i?.kind === 'action' && i.action === 'cast');
  expect(went.length === 1 && went[0].ctx?.caught === true && JSON.stringify(went[0].ctx?.target) === JSON.stringify(goblins.slice(1).map((g) => `token:${g.id}`)), `the cast named the two: ${JSON.stringify(went.map((i) => i.ctx))}`);
  // the DM's card: whom she named, what it does; nothing landed yet
  const card = dm.getByRole('dialog', { name: 'To approve' });
  await card.waitFor({ timeout: 10000 });
  await card.getByText(/Sela's Burning Hands, catching the Goblin Warrior/).first().waitFor({ timeout: 3000 });
  const still = await dm.evaluate((ids) => Object.fromEntries(ids.map((id) => [id, window.hexmap.game.view.actors?.[id]?.resources?.srd5e?.hp?.current])), goblins.map((g) => g.actor));
  expect(JSON.stringify(still) === JSON.stringify(hp), `something landed before the DM said so: ${JSON.stringify(hp)} → ${JSON.stringify(still)}`);
  await ana.getByText(/waits on the DM|Waiting on the DM|the DM/).first().waitFor({ timeout: 5000 }).catch(() => {});
  await shot(dm, 'dm_confirms_the_area');
  await card.getByRole('button', { name: 'Apply', exact: true }).click();
  await card.waitFor({ state: 'detached', timeout: 6000 });
  await dm.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => /casts Burning Hands/.test(e.text ?? '')), null, { timeout: 8000 });
  const after = await dm.evaluate((ids) => Object.fromEntries(ids.map((id) => [id, window.hexmap.game.view.actors?.[id]?.resources?.srd5e?.hp?.current])), goblins.map((g) => g.actor));
  expect(after[goblins[1].actor] < hp[goblins[1].actor] && after[goblins[2].actor] < hp[goblins[2].actor], `the two named are burned: ${JSON.stringify(hp)} → ${JSON.stringify(after)}`);
  const words = await logWords(dm);
  const line = words.find((w) => /casts Burning Hands/.test(w)) ?? '';
  expect(line.includes(goblins[1].name) && line.includes(goblins[2].name), `the cast’s line names both: ${line}`);
  await listOf(ana).locator('.row').first().waitFor({ timeout: 3000 });
  await shot(ana, 'ana_after_burning_hands');
  await shot(dm, 'dm_after_burning_hands');
}));

ok = ok && (await step('the DM adds a wolf to the fight: no token to put down', async () => {
  const join = dm.getByRole('region', { name: 'Add to the fight' });
  await join.getByRole('searchbox', { name: 'Find a creature to add to the fight' }).fill('wolf');
  await join.locator('.found').filter({ hasText: /^Wolf/ }).first().click({ timeout: 8000 });
  await listOf(dm).locator('.row .name').filter({ hasText: /^Wolf/ }).waitFor({ timeout: 8000 });
  await listOf(ben).locator('.row .name').filter({ hasText: /^Wolf/ }).waitFor({ timeout: 8000 });
  await shot(dm, 'dm_wolf_joins');
}));

ok = ok && (await step('the fight ends: no list, the region again', async () => {
  await dm.locator('.fightbar').getByRole('button', { name: 'End the fight' }).click();
  await dm.getByRole('dialog', { name: 'End the fight?' }).getByRole('button', { name: 'End the fight' }).click();
  await dm.locator('.fightbar').waitFor({ state: 'detached', timeout: 8000 });
  await listOf(ana).waitFor({ state: 'detached', timeout: 8000 });
  await shot(ana, 'ana_after_the_fight');
}));

await finish();
