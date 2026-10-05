// Real dice typed in, the DM's creatures' rolls out of sight, and a player's
// own preference, in a real browser. The DM sets the table to real dice:
// Ana's attack asks her phone for her d20 and then her damage dice, each box
// checked, and the chat marks both rolls "rolled at the table". The DM sets
// the creatures' dice to real dice too, in the open: in the chapel fight a
// goblin's attack on Wren asks the DM's screen for its d20 and its damage, and
// Ben sees the roll; behind the DM's screen, the same typed hit reaches Ben as
// words alone. Then the creatures' rolls go out of sight: a goblin hits Wren,
// and Ben's screen says so — "it hits, N slashing damage" — with no roll of
// the goblin's and no number but the damage. Last, the table lets each player choose: Ana
// takes her own dice from her ⋯ menu (My preferences), the DM's Table
// settings shows it as hers, her next roll asks; she goes back to the app's
// dice, and the next one rolls at once. Screenshots of each step go to the
// output folder; a step that does not happen fails the run.
//
//   node tests/e2e/dice.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, started with --party (Ana plays
// Wren, a halfling rogue; Ben, Brakka) and a --seed.
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/dice.mjs <host.json> <out dir>');
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
  await shot(dm, `dm_settings_${title.replace(/[^a-z]+/gi, '_').slice(0, 24)}`);
  await dialog.getByRole('button', { name: 'Done' }).click();
  await dialog.waitFor({ state: 'detached', timeout: 5000 });
}

// The card that asks for a roll's dice, on a page: "Your roll" (a player's), "Your dice" (the DM's).
const diceCard = (page, heading) => page.getByRole('dialog', { name: heading });

// Type faces into a dice card's boxes, in order; what its boxes ask for comes back (their d-sides).
// (A card the table waits on ignores taps in its first moment: a person takes longer than that.)
async function typeDice(card, faces) {
  const boxes = card.locator('input.die');
  await boxes.first().waitFor({ timeout: 8000 });
  await card.page().waitForTimeout(700);
  const sides = [];
  for (let i = 0; i < (await boxes.count()); i++) sides.push(Number(String(await boxes.nth(i).getAttribute('placeholder')).slice(1)));
  for (let i = 0; i < faces.length && i < sides.length; i++) {
    await boxes.nth(i).click();
    await boxes.nth(i).pressSequentially(String(faces[i]), { delay: 40 });
  }
  return sides;
}

// The newest roll in a page's log whose label says `what`.
const newestRoll = (page, what) =>
  page.evaluate((w) => {
    const log = window.hexmap.game.view.log ?? [];
    for (let i = log.length - 1; i >= 0; i--) if (log[i].kind === 'roll' && new RegExp(w).test(String(log[i].label ?? ''))) return log[i];
    return null;
  }, what);

const rollsIn = (page) => page.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length);

let ok = await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
});

ok = ok && (await step('the DM gives Wren a dagger, in her hand', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Wren/ }).first().click();
  await dm.getByRole('tab', { name: 'Inventory' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give an item' });
  await give.locator('input[type=search]').fill('dagger');
  await give.getByRole('button', { name: /^Dagger/ }).first().click({ timeout: 8000 });
  const row = dm.locator('.row').filter({ hasText: /Dagger/ }).filter({ has: dm.getByRole('button', { name: 'Equip' }) }).first();
  await row.getByRole('button', { name: 'Equip' }).click({ timeout: 8000 });
  await dm.waitForFunction(() => Object.values(window.hexmap.game.view.actors ?? {}).some((a) => a.name === 'Wren' && (a.derived?.srd5e?.attacks ?? []).some((t) => t.name === 'Dagger')), null, { timeout: 8000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
}));

ok = ok && (await step('the DM sets the table to real dice: the players roll and type what came up', async () => {
  await setRule("Players' dice", 'Real dice: each player rolls and types what came up');
}));

// Ana's attack with Wren's dagger, as her phone sends it: Character, Combat, the
// dagger's Attack — on the region it goes with no target to tap; on a battle
// map, No target: just roll (the theatre of the mind)
async function anaAttacks() {
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Combat' }).click();
  const row = ana.locator('.row').filter({ hasText: /Dagger/ }).filter({ has: ana.getByRole('button', { name: 'Attack' }) }).first();
  await row.getByRole('button', { name: 'Attack' }).click({ timeout: 8000 });
  const banner = ana.getByRole('group', { name: 'Choose the target' });
  const card = diceCard(ana, 'Your roll');
  await Promise.race([banner.waitFor({ timeout: 8000 }), card.waitFor({ timeout: 8000 })]);
  if (await banner.count()) await banner.getByRole('button', { name: 'No target: just roll' }).click();
}

ok = ok && (await step('Ana attacks: her phone asks for her d20 first — a face her die can’t show is refused — then the damage dice', async () => {
  const before = await rollsIn(ana);
  await anaAttacks();
  const card = diceCard(ana, 'Your roll');
  await card.waitFor({ timeout: 8000 });
  const words = await card.innerText();
  expect(/roll your d20/.test(words) && /Type what came up/.test(words), `the card asks for her d20: ${words}`);
  // a d20 can't show 25: the box says so, and Done waits
  const sides = await typeDice(card, [25]);
  expect(sides.length === 1 && sides[0] === 20, `one d20 asked: ${sides}`);
  await card.getByRole('button', { name: /^Done/ }).click();
  await card.getByRole('alert').getByText('A d20 shows 1 to 20.').waitFor({ timeout: 4000 });
  await shot(ana, 'ana_d20_typed_wrong');
  const box = card.locator('input.die').first();
  await box.fill('');
  await box.pressSequentially('17', { delay: 40 });
  await card.getByText(/= \d+/).waitFor({ timeout: 3000 });
  await shot(ana, 'ana_d20_card');
  await card.getByRole('button', { name: /^Done/ }).click();
  // the damage: its own card, once the d20 is in
  await ana.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length > n, before, { timeout: 8000 });
  const dmg = diceCard(ana, 'Your roll');
  await dmg.getByText(/damage/).first().waitFor({ timeout: 8000 });
  const dsides = await typeDice(dmg, [3, 3, 3, 3]);
  expect(dsides.length >= 1 && dsides.every((s) => s >= 4 && s <= 12), `the damage dice asked: ${dsides}`);
  await shot(ana, 'ana_damage_card');
  await dmg.getByRole('button', { name: /^Done/ }).click();
  await dmg.waitFor({ state: 'detached', timeout: 8000 });
  // both rolls are hers as typed: the d20's 17, and marked
  const atk = await newestRoll(ana, '^Dagger \\(no target\\)$');
  expect(atk && atk.spec?.typed === true && atk.result?.dice?.[0]?.face === 17, `the attack roll as typed: ${JSON.stringify(atk?.result?.dice)}`);
  const hurt = await newestRoll(ana, '^Dagger damage \\(no target\\)');
  expect(hurt && hurt.spec?.typed === true && hurt.result.dice.every((d) => d.face === 3), `the damage roll as typed: ${JSON.stringify(hurt?.result?.dice)}`);
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText('rolled at the table').first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_chat_rolled_at_the_table');
  await ben.getByRole('tab', { name: /Chat/ }).click().catch(() => {});
  await ben.getByText('rolled at the table').first().waitFor({ timeout: 5000 });
}));

// Ana's own choice, from her ⋯ menu: My preferences, My dice.
async function anaChooses(label) {
  await ana.getByRole('button', { name: 'More' }).click();
  await ana.getByRole('menuitem', { name: 'My preferences' }).click();
  const box = ana.getByRole('dialog', { name: 'My preferences' });
  await box.waitFor({ timeout: 5000 });
  await box.getByRole('combobox', { name: 'My dice' }).selectOption({ label });
  await ana.waitForFunction(
    (want) => (window.hexmap.game.players ?? []).some((p) => p.id === window.hexmap.game.me && p.prefs?.srd5e?.dice === want),
    label.startsWith('My own') ? 'typed' : 'app',
    { timeout: 8000 },
  );
  await shot(ana, `ana_my_preferences_${label.startsWith('My own') ? 'own' : 'app'}`);
  await box.getByRole('button', { name: 'Done' }).click();
  await box.waitFor({ state: 'detached', timeout: 5000 });
}

ok = ok && (await step('the table lets each player choose: Ana takes her own dice in My preferences, and the DM’s Table settings shows it as hers', async () => {
  await setRule("Players' dice", 'Each player chooses (their preference)');
  await anaChooses('My own dice: I roll and type what came up');
  await dm.getByRole('button', { name: /^Table settings/ }).first().click();
  const dialog = dm.getByRole('dialog', { name: 'Table settings' });
  await dialog.waitFor({ timeout: 5000 });
  const prefs = dialog.getByTestId('players-prefs');
  await prefs.scrollIntoViewIfNeeded();
  const anaDice = prefs.getByRole('combobox', { name: 'Ana: My dice' });
  await anaDice.waitFor({ timeout: 5000 });
  expect((await anaDice.inputValue()) === JSON.stringify('typed'), `the DM's list: ${await anaDice.inputValue()}`);
  await prefs.locator('li').filter({ hasText: 'Ana: My dice' }).getByText('Their choice').waitFor({ timeout: 3000 });
  expect((await prefs.getByRole('combobox', { name: 'Ben: My dice' }).inputValue()) === JSON.stringify('app'), 'Ben’s: the app’s, as the table has it');
  await shot(dm, 'dm_players_preferences');
  await dialog.getByRole('button', { name: 'Done' }).click();
  await dialog.waitFor({ state: 'detached', timeout: 5000 });
}));

ok = ok && (await step('her next attack asks — Roll it for me lets the app roll it; then she goes back to the app’s dice, and the next rolls at once', async () => {
  await anaAttacks();
  const card = diceCard(ana, 'Your roll');
  await card.waitFor({ timeout: 8000 });
  await ana.waitForTimeout(700);
  await shot(ana, 'ana_asked_again');
  await card.getByRole('button', { name: 'Roll it for me' }).click();
  // (a hit's damage asks too: the app's again)
  for (let i = 0; i < 2; i++) {
    const more = diceCard(ana, 'Your roll');
    if (!(await more.waitFor({ timeout: 2500 }).then(() => true, () => false))) break;
    await ana.waitForTimeout(700);
    await more.getByRole('button', { name: 'Roll it for me' }).click();
    await ana.waitForTimeout(400);
  }
  const atk = await newestRoll(ana, '^Dagger \\(no target\\)$');
  expect(atk && atk.spec?.typed !== true, 'Roll it for me: the app rolled it, no mark');
  await anaChooses('The app rolls them');
  const before = await rollsIn(ana);
  await anaAttacks().catch(() => {});
  await ana.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length > n, before, { timeout: 8000 });
  await ana.waitForTimeout(800);
  expect((await diceCard(ana, 'Your roll').count()) === 0, 'a card asked her anyway');
  await shot(ana, 'ana_app_dice_again');
}));

// ------------------------------------------------------------ the chapel fight --
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

const wren = () =>
  dm.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    const a = t ? g.view.actors?.[t.actor] : null;
    return t ? { id: t.id, actor: t.actor, pos: t.pos, hp: a?.resources?.srd5e?.hp?.current } : null;
  });

let goblins = [];
ok = ok && (await step('the DM puts the party inside and Wren beside a goblin', async () => {
  const where = await dm.evaluate(() => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gobs = toks.filter((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? ''));
    const c = document.querySelector('canvas');
    if (!gobs.length || !c?.screenOf) return null;
    return { at: c.screenOf(gobs[0].id), px: c.pxPerHex(), gob: gobs[0].id, ids: gobs.map((g) => g.id) };
  });
  expect(where, 'no goblin on the DM’s map');
  // (by their tokens: every goblin is "Goblin Warrior")
  goblins = where.ids;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(600);
  const w = await wren();
  expect(w, 'no Wren on the map');
  const drag = await dm.evaluate(
    ([wid, gid]) => {
      const c = document.querySelector('canvas');
      const px = c.pxPerHex();
      const from = c.screenOf(wid);
      const g = c.screenOf(gid);
      return { from, to: { x: g.x - px, y: g.y } };
    },
    [w.id, where.gob],
  );
  await dm.mouse.move(drag.from.x, drag.from.y);
  await dm.mouse.down();
  await dm.mouse.move(drag.from.x + 10, drag.from.y, { steps: 3 });
  await dm.mouse.move(drag.to.x, drag.to.y, { steps: 8 });
  await dm.mouse.up();
  await dm.waitForFunction(
    ([wid, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === wid);
      return t && (t.pos[0] !== pos[0] || t.pos[1] !== pos[1]);
    },
    [w.id, w.pos],
    { timeout: 5000 },
  );
  await shot(dm, 'dm_wren_beside_a_goblin');
}));

// A round goes by: Next turn until the round is the next one (each goblin's action back on its turn).
const turnNow = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);
async function nextRound() {
  const round = await dm.evaluate(() => window.hexmap.game.scene.turns?.round ?? 0);
  for (let i = 0; i < 16; i++) {
    if ((await dm.evaluate(() => window.hexmap.game.scene.turns?.round ?? 0)) > round) return;
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
}

// One goblin's attack at Wren from its row (by its token), by the attack's name: the DM picks Wren by name.
async function swing(goblin, attack) {
  await dm.locator(`.order [data-token="${goblin}"]`).click();
  await dm.locator('.chosen').waitFor({ timeout: 5000 });
  await dm.locator('.chosen .row').filter({ hasText: attack }).first().getByRole('button', { name: 'Use' }).click();
  const banner = dm.getByRole('group', { name: 'Choose the target' });
  await banner.waitFor({ timeout: 5000 });
  await banner.locator('.choice').filter({ hasText: /^Wren/ }).first().click();
  await banner.getByRole('button', { name: 'Done' }).click();
}

// A goblin's attack on Wren whose dice the DM types: its card asks the DM's
// screen for the d20 (an 18), then the damage (a 1: Wren takes 1 + 2, and has
// hit points for both of these and the out-of-sight hit after). A goblin whose
// action is spent asks nothing: the next one, or the next round. The roll's
// entry, as the DM's log has it.
async function dmTypesAGoblinsHit(label) {
  const before = await wren();
  const card = diceCard(dm, 'Your dice');
  let asked = false;
  for (let round = 0; round < 3 && !asked; round++) {
    for (const g of goblins) {
      await swing(g, /^Scimitar\./);
      if (await card.waitFor({ timeout: 4000 }).then(() => true, () => false)) {
        asked = true;
        break;
      }
    }
    if (!asked) await nextRound();
  }
  expect(asked, 'no goblin’s attack asked the DM for its dice');
  await card.getByText(/Scimitar → Wren: roll the d20 \+ 4/).first().waitFor({ timeout: 5000 });
  const words = await card.innerText();
  expect(/^Goblin.*'s Scimitar → Wren/m.test(words), `the DM's card names the goblin and whom it's at: ${words}`);
  await typeDice(card, [18]);
  await shot(dm, `dm_goblin_d20_${label}`);
  await card.getByRole('button', { name: /^Done/ }).click();
  const dmg = diceCard(dm, 'Your dice');
  await dmg.getByText(/damage/).first().waitFor({ timeout: 8000 });
  const sides = await typeDice(dmg, [1]);
  expect(sides.length === 1 && sides[0] === 6, `the scimitar's d6: ${sides}`);
  await dmg.getByRole('button', { name: /^Done/ }).click();
  await dmg.waitFor({ state: 'detached', timeout: 8000 });
  await dm.waitForFunction((hp) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    return (g.view.actors?.[t.actor]?.resources?.srd5e?.hp?.current ?? hp) < hp;
  }, before.hp, { timeout: 8000 });
  const after = await wren();
  expect(before.hp - after.hp === 1 + 2, `Wren took ${before.hp - after.hp}, not the 1 + 2 the DM typed`);
  const hit = await newestRoll(dm, '^Scimitar$');
  expect(hit && hit.spec?.typed_by === 'gm' && hit.result?.dice?.[0]?.face === 18, `the goblin's roll as the DM typed it: ${JSON.stringify(hit?.spec)}`);
  return hit;
}

ok = ok && (await step('the DM rolls the creatures’ dice by hand, in the open: a goblin’s attack on Wren asks the DM’s screen for its d20, then its damage, and the players see it', async () => {
  await setRule("Your creatures' dice", 'Your real dice, in the open: you type what came up, and the players see it');
  const hit = await dmTypesAGoblinsHit('open');
  expect(hit.audience === 'all', `in the open: everyone's (${hit.audience})`);
  // the players see it, rolled at the table
  await ben.waitForFunction((id) => (window.hexmap.game.view.log ?? []).some((e) => e.id === id && e.spec?.typed === true), hit.id, { timeout: 8000 });
  await shot(ben, 'ben_sees_the_dms_roll');
}));

ok = ok && (await step('the DM’s real dice behind the screen: the DM types a goblin’s hit, and Ben’s screen hears it with no roll and no number but the damage', async () => {
  await setRule("Your creatures' dice", 'Your real dice, behind your screen: you type what came up, and the players hear what happened');
  const said = 'attacks Wren with its Scimitar: it hits, 3 slashing damage.';
  const heard = () => ben.evaluate((w) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'note' && String(e.text ?? '').includes(w)).length, said);
  const before = await heard();
  const hit = await dmTypesAGoblinsHit('behind');
  expect(hit.audience === 'gm', `behind the screen: the DM's alone (${hit.audience})`);
  await ben.waitForFunction(([w, n]) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'note' && String(e.text ?? '').includes(w)).length > n, [said, before], { timeout: 8000 });
  expect(!(await ben.evaluate((id) => (window.hexmap.game.view.log ?? []).some((e) => e.id === id), hit.id)), 'the DM’s roll reached Ben’s screen');
  await ben.getByRole('tab', { name: /Chat/ }).click().catch(() => {});
  await ben.getByText(said).first().waitFor({ timeout: 5000 });
  await shot(ben, 'ben_hears_the_dms_hit');
}));

ok = ok && (await step('the creatures’ rolls out of sight: a goblin hits Wren, and Ben’s screen says so with no roll and no number but the damage', async () => {
  await setRule("Your creatures' dice", 'The app rolls them out of sight: the players hear what happened, never the numbers');
  const gobRolls = () =>
    ben.evaluate(() => {
      const g = window.hexmap.game;
      const ids = new Set((g.scene.tokens ?? []).filter((t) => /^Goblin/.test(t.name ?? '')).map((t) => t.actor));
      return (g.view.log ?? []).filter((e) => e.kind === 'roll' && ids.has(e.actor)).length;
    });
  const rollsBefore = await gobRolls();
  const said = /attacks Wren with its Scimitar: it hits, \d+ slashing damage\./;
  let line = null;
  for (let round = 0; round < 4 && !line; round++) {
    for (const g of goblins) {
      await swing(g, /^Scimitar\./);
      await dm.waitForTimeout(1200);
      line = await ben.evaluate((src) => {
        const re = new RegExp(src);
        const log = window.hexmap.game.view.log ?? [];
        for (let i = log.length - 1; i >= 0; i--) if (log[i].kind === 'note' && re.test(String(log[i].text ?? ''))) return String(log[i].text);
        return null;
      }, said.source);
      if (line) break;
    }
    if (!line) await nextRound();
  }
  expect(line, 'no hit said on Ben’s screen');
  expect(!/\b(to hit|against|AC)\b/.test(line), `numbers in the line: ${line}`);
  expect((await gobRolls()) === rollsBefore, 'a goblin’s roll reached Ben’s screen');
  // the DM's log has the rolls, numbers and all
  const dmRolls = await dm.evaluate(() => {
    const g = window.hexmap.game;
    const ids = new Set((g.scene.tokens ?? []).filter((t) => /^Goblin/.test(t.name ?? '')).map((t) => t.actor));
    return (g.view.log ?? []).filter((e) => e.kind === 'roll' && ids.has(e.actor) && e.audience === 'gm').length;
  });
  expect(dmRolls > 0, 'the DM’s log has no goblin roll out of sight');
  await ben.getByRole('tab', { name: /Chat/ }).click().catch(() => {});
  await ben.getByText(said).first().waitFor({ timeout: 5000 });
  await shot(ben, 'ben_hears_the_hit');
}));

await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log('\nevery step went');
