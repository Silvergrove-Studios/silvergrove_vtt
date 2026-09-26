// The next playtest's journey, in a real browser against a real table:
// the DM's screen and two players' screens (one a phone), the village
// (a place's card, shown to the players, chat and a private message), a
// character sheet, and the chapel fight (launched, initiative, an attack
// picked on the map, a token moved by tapping it and then where it goes,
// ended). Screenshots of each step go to the output
// folder; a step that does not happen fails the run.
//
//   node tests/e2e/journey.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes (started with --party).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/journey.mjs <host.json> <out dir>');
  process.exit(2);
}
mkdirSync(out, { recursive: true });
const info = JSON.parse(readFileSync(infoPath, 'utf8'));
const browser = await chromium.launch({ channel: process.env.HEXMAP_BROWSER ?? 'chrome', headless: true });
const problems = [];
let n = 0;

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

const pages = [];

async function step(label, f) {
  process.stdout.write(`${label} … `);
  try {
    await f();
    console.log('ok');
  } catch (e) {
    console.log('FAILED');
    problems.push(`${label}: ${String(e.message ?? e).split('\n')[0]}`);
    // what each screen showed when it failed
    for (const [name, p] of pages) await p.screenshot({ path: `${out}/failed_${label.replace(/[^a-z0-9]+/gi, '_').slice(0, 40)}_${name}.png` }).catch(() => {});
  }
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

await step('the DM’s screen opens', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  // the first view is the whole map, fitted to the space it has (not to a
  // size from before the page had one): showing the whole map changes nothing
  const px = () => dm.evaluate(() => document.querySelector('canvas')?.pxPerHex?.() ?? 0);
  await dm.waitForTimeout(400);
  const first = await px();
  await dm.getByRole('button', { name: 'Show the whole map' }).click();
  const whole = await px();
  if (!(whole > 0) || Math.abs(first - whole) > whole * 0.02) throw new Error(`the first view is not the whole map: ${first} px a cell, the whole map ${whole}`);
  await shot(dm, 'dm_first');
});

await step('Ana joins by typing her name', async () => {
  await ana.locator('#name').fill('Ana');
  await ana.getByRole('button', { name: 'Join' }).click();
  await ana.getByText('Free movement').waitFor({ timeout: 10000 });
  await shot(ana, 'ana_joined');
});

await step('Ben joins by tapping his name', async () => {
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await shot(ben, 'ben_joined');
});

await step('the adventure’s book opens with its introduction', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Introduction/ }).first().click();
  await dm.getByText('Adventure background').waitFor({ timeout: 5000 });
  await shot(dm, 'dm_introduction');
  await dm.getByRole('button', { name: 'Close the card' }).click();
});

await step('the DM invites: a code and an address', async () => {
  await dm.getByRole('button', { name: 'Invite players' }).first().click();
  await dm.getByText('Open a player’s screen on this computer').waitFor();
  // one address in sight, the others folded away, and how players somewhere else join
  await dm.getByText('Players somewhere else?').waitFor();
  if ((await dm.locator('.invite .url').count()) !== 1) throw new Error('more than one address in sight');
  await shot(dm, 'dm_invite');
  await dm.getByRole('button', { name: 'Close' }).click();
});

await step('the DM starts the session', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click();
  await dm.getByText(/Session 1/).first().waitFor({ timeout: 5000 });
  // the next step points at what the adventure says to read first, by its own title
  await dm.locator('.guide').getByRole('button', { name: 'Open “Introduction”' }).waitFor({ timeout: 5000 });
});

await step('a place’s card, from the book', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Thornwick/ }).first().click();
  await dm.getByText('Read aloud').waitFor({ timeout: 5000 });
  await shot(dm, 'dm_place_card');
});

await step('a card popped out into a window of its own', async () => {
  const [win] = await Promise.all([dm.context().waitForEvent('page'), dm.getByRole('button', { name: /Pop out/ }).click()]);
  await win.setViewportSize({ width: 720, height: 900 });
  await win.getByText('Read aloud').waitFor({ timeout: 10000 });
  await shot(win, 'dm_card_popped_out');
  await win.close();
});

await step('shown to the players: it comes up on their screens', async () => {
  await dm.getByRole('button', { name: 'Show the players' }).first().click();
  await ana.getByRole('dialog', { name: 'Thornwick' }).waitFor({ timeout: 5000 });
  await shot(ana, 'ana_shown');
  await ana.getByRole('button', { name: /it is in your Journal/ }).click();
  await ben.getByRole('dialog', { name: 'Thornwick' }).waitFor({ timeout: 5000 });
  await ben.getByRole('button', { name: /it is in your Journal/ }).click();
});

await step('chat: Ana to everyone, Ben privately to Ana', async () => {
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByLabel('Message').fill('Hello, Thornwick!');
  await ana.getByRole('button', { name: 'Send' }).click();
  await ben.getByRole('tab', { name: /Chat/ }).click();
  await ben.getByText('Hello, Thornwick!').waitFor({ timeout: 5000 });
  await ben.locator('.to').getByRole('button', { name: 'Ana' }).click();
  await ben.getByText('keep it from the DM').click();
  await ben.getByLabel('Message').fill('Psst — watch the reeve.');
  await ben.getByRole('button', { name: 'Send' }).click();
  await ana.getByText('Psst — watch the reeve.').waitFor({ timeout: 5000 });
  await dm.getByRole('tab', { name: /Chat/ }).click();
  await dm.getByText('Hello, Thornwick!').waitFor({ timeout: 5000 });
  if (await dm.getByText('Psst — watch the reeve.').count()) throw new Error('the DM read a private message');
  await shot(ana, 'ana_chat');
  await shot(dm, 'dm_chat');
});

await step('Ana’s character sheet', async () => {
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByText('Wren').first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_sheet');
});

await step('the DM makes a folder of their own and files someone in it', async () => {
  const answer = (text) => dm.once('dialog', (d) => d.accept(text));
  const people = dm.locator('.book .group').filter({ has: dm.locator('.head .title', { hasText: /^People$/ }) }).first();
  await people.locator('.head').hover();
  await people.getByRole('button', { name: 'Arrange People' }).click();
  answer('Suspects');
  await dm.getByRole('menuitem', { name: 'New folder inside' }).click();
  await dm.locator('.book').getByText('Suspects').waitFor({ timeout: 5000 });
  await dm.locator('.book').getByRole('button', { name: /^Reeve Hollis Dunmore/ }).first().click();
  const option = await dm.locator('.file select option', { hasText: 'Suspects' }).first().getAttribute('value');
  await dm.locator('.file select').selectOption(option ?? '');
  await dm.waitForFunction(() => Object.values(window.hexmap.game.dm.contents?.in ?? {}).length > 0, null, { timeout: 5000 });
  const folder = dm.locator('.book .group.folder').filter({ hasText: 'Suspects' }).first();
  await folder.getByText('Reeve Hollis Dunmore').waitFor({ timeout: 5000 });
  await folder.locator('.head').first().hover();
  await folder.getByRole('button', { name: 'Arrange Suspects' }).click();
  answer('The reeve’s circle');
  await dm.getByRole('menuitem', { name: 'Rename' }).click();
  await dm.locator('.book').getByText('The reeve’s circle').waitFor({ timeout: 5000 });
  await shot(dm, 'dm_folders');
  await dm.getByRole('button', { name: 'Close the card' }).click();
});

let cara = null;
await step('a new player makes a character with the wizard', async () => {
  cara = await open(info.player, { width: 390, height: 844 }, 'cara');
  await cara.locator('#name').fill('Cara');
  await cara.getByRole('button', { name: 'Join' }).click();
  await cara.getByText('Make your character').waitFor({ timeout: 10000 });
  const row = (label) => cara.locator('.wizard .row').filter({ hasText: label });
  await row('Name').locator('input').fill('Tamsin');
  for (const [label, pick] of [['Species', 'Human'], ['Background', 'Soldier'], ['Class', 'Fighter']]) {
    // (the choices come from the table: the select is drawn again when they arrive)
    await cara.waitForFunction(
      (lab) => {
        const r = [...document.querySelectorAll('.wizard .row')].find((x) => x.textContent?.includes(lab));
        const sel = r?.querySelector('select');
        return !!sel && !sel.disabled && sel.options.length > 1;
      },
      label,
      { timeout: 8000 },
    );
    await row(label).locator('select').selectOption({ label: pick });
  }
  await shot(cara, 'cara_wizard');
  const next = cara.locator('.wizard .nav button.accent');
  await next.click();
  // the species' choices (a human): Skillful's skill, Versatile's Origin feat
  await cara.getByText('What your species lets you choose.').waitFor({ timeout: 8000 });
  await cara.getByRole('checkbox', { name: /^Insight/ }).click();
  await cara.getByRole('radio', { name: /^Alert/ }).click({ timeout: 8000 });
  await shot(cara, 'cara_species');
  await next.click();
  // ability scores: a point buy from 8s; she asks for the fighter's suggestion; the soldier's +2/+1 placed
  await cara.getByText('27 left').waitFor({ timeout: 8000 });
  await cara.getByRole('button', { name: 'Suggested for a Fighter' }).click();
  await cara.getByText('All spent ✓').waitFor({ timeout: 5000 });
  await shot(cara, 'cara_scores');
  await next.click();
  // skills: the soldier's two already, two of the fighter's to choose
  await cara.getByText('From your background').first().waitFor({ timeout: 5000 });
  for (const s of ['Perception', 'Survival']) await cara.getByRole('checkbox', { name: new RegExp(`^${s}`) }).click();
  await next.click();
  // equipment (before the class's choices, as the SRD 5.2 orders them): the fighter's package A, the soldier's package A
  for (const r of await cara.getByRole('radio', { name: /^Package A/ }).all()) await r.click();
  await shot(cara, 'cara_equipment');
  await next.click();
  // the class's choices at level 1: a Fighting Style feat, three kinds of weapons to master
  await cara.getByText('What your class lets you choose at level 1.').waitFor({ timeout: 8000 });
  await cara.getByRole('radio', { name: /^Defense/ }).click({ timeout: 8000 });
  for (const w of ['Longsword', 'Greatsword', 'Longbow']) await cara.getByRole('checkbox', { name: new RegExp(`^${w}`) }).click();
  await shot(cara, 'cara_class_features');
  await next.click();
  // what her choices give, then the character
  await cara.getByText('From your background, Soldier:').waitFor({ timeout: 8000 });
  await next.click();
  await cara.getByText('Human Fighter 1').first().waitFor({ timeout: 10000 });
  await shot(cara, 'cara_sheet');
});

await step('the DM asks the party for a roll; each player rolls their own', async () => {
  await dm.getByRole('tab', { name: 'Party' }).click();
  const rolls = () => dm.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length);
  const before = await rolls();
  await dm.getByRole('button', { name: 'Ask', exact: true }).click();
  // the form says it went
  await dm.getByText('Done ✓').first().waitFor({ timeout: 5000 });
  const asked = [ana, ben, cara].filter(Boolean);
  for (const p of asked) await p.getByRole('dialog', { name: 'The DM asks' }).waitFor({ timeout: 8000 });
  await shot(ana, 'ana_asked');
  // one roll lands per tap, whoever is still to roll (a playtest's party
  // waited two minutes on its slowest player before anyone's roll was made)
  let n = before;
  for (const p of asked) {
    await p.getByRole('button', { name: /^Roll Perception/ }).click();
    n += 1;
    await dm.waitForFunction((want) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length >= want, n, { timeout: 10000 });
  }
  // the roller sees the result where they are
  await ana.locator('.rolled').waitFor({ timeout: 5000 });
  await shot(ana, 'ana_rolled');
  await dm.getByText('Rolls asked').first().waitFor({ timeout: 5000 });
  await dm.getByRole('tab', { name: /Chat/ }).click();
  await shot(dm, 'dm_rolls');
});

await step('the DM moves the party along the road', async () => {
  const where = await dm.evaluate(() => {
    const t = (window.hexmap.game.scene.tokens ?? []).find((x) => (x.tags ?? []).includes('party'));
    const c = document.querySelector('canvas');
    return t && c?.screenOf ? { id: t.id, pos: t.pos, at: c.screenOf(t.id), px: c.pxPerHex() } : null;
  });
  if (!where) throw new Error('no party marker');
  await dm.mouse.move(where.at.x, where.at.y);
  await dm.mouse.down();
  await dm.mouse.move(where.at.x - 10, where.at.y, { steps: 3 });
  await dm.mouse.move(where.at.x - where.px * 2.2, where.at.y, { steps: 8 });
  await dm.mouse.up();
  await dm.waitForFunction(
    ([id, x]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((k) => k.id === id);
      return t && t.pos[0] < x - 1;
    },
    [where.id, where.pos[0]],
    { timeout: 5000 },
  );
});

await step('a place marked on the players’ map', async () => {
  await dm.locator('.book').getByRole('button', { name: /^The ford/ }).first().click();
  await dm.getByText('The players can see it on the map').click();
  await ana.waitForFunction(() => (window.hexmap.game.scene.tokens ?? []).some((t) => t.name === 'The ford'), null, { timeout: 5000 });
  await dm.getByRole('button', { name: 'Close the card' }).click();
  await ana.getByRole('tab', { name: /Map/ }).click();
  await shot(ana, 'ana_ford_marked');
});

await step('the book says which is which, and a search ends once used', async () => {
  // "The ruined chapel" is a place and a picture: each says what it is
  const book = dm.locator('aside.book');
  const words = await book.locator('.item').filter({ has: dm.locator('.label', { hasText: /^The ruined chapel$/ }) }).locator('.kindword:not(.sr-only)').allTextContents();
  if (!words.includes('place') || !words.includes('picture')) throw new Error(`the two say ${JSON.stringify(words)}`);
  const search = dm.getByRole('searchbox', { name: 'Look up anything' });
  await search.fill('Marta');
  await search.press('Enter');
  await dm.locator('.reader').waitFor({ timeout: 5000 });
  if (await search.inputValue()) throw new Error('the search stayed once something was opened');
  await shot(dm, 'dm_book_kinds');
  await dm.getByRole('button', { name: 'Close the card' }).click();
});

await step('the chapel: the DM starts the fight', async () => {
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  // the fight's card gives way to its map by itself
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 });
  await dm.waitForTimeout(800);
  await shot(dm, 'dm_fight');
});

await step('initiative is rolled; the order shows', async () => {
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Reveal them all' }).click().catch(() => {});
  await dm.waitForTimeout(800);
  await shot(dm, 'dm_order');
});

await step('the DM chooses a creature: its stat block', async () => {
  await dm.locator('.order .row').filter({ hasNotText: /Wren|Brakka/ }).first().click();
  await dm.locator('.chosen').waitFor({ timeout: 5000 });
  await shot(dm, 'dm_statblock');
});

await step('the DM drags Wren beside a goblin', async () => {
  const where = await dm.evaluate(() => {
    const g = window.hexmap.game;
    const toks = g.scene.tokens ?? [];
    const wren = toks.find((t) => t.name === 'Wren');
    const gob = toks.find((t) => /Goblin/.test(t.name ?? ''));
    const c = document.querySelector('canvas');
    if (!wren || !gob || !c?.screenOf) return null;
    return { from: c.screenOf(wren.id), to: c.screenOf(gob.id), px: c.pxPerHex(), id: wren.id, pos: wren.pos };
  });
  if (!where) throw new Error('no Wren or goblin on the DM’s map');
  await dm.mouse.move(where.from.x, where.from.y);
  await dm.mouse.down();
  await dm.mouse.move(where.from.x + 10, where.from.y, { steps: 3 });
  await dm.mouse.move(where.to.x - where.px, where.to.y, { steps: 8 });
  await dm.mouse.up();
  await dm.waitForFunction(
    ([id, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
      return t && (t.pos[0] !== pos[0] || t.pos[1] !== pos[1]);
    },
    [where.id, where.pos],
    { timeout: 5000 },
  );
  await shot(dm, 'dm_dragged');
});

await step('the DM moves the turns on to Wren', async () => {
  const now = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);
  for (let i = 0; i < 12; i++) {
    if (await dm.locator('.fightbar').getByText(/Wren’s turn/).count()) return;
    // (each step seen through before the next: a look taken before the turn
    // reached the screen went one past Wren's)
    const was = await now();
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was, { timeout: 5000 });
  }
  throw new Error('Wren’s turn never came');
});

await step('Ana attacks: a target picked on the map, the roll in the log', async () => {
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Combat' }).click();
  await ana.getByRole('button', { name: 'Attack' }).first().click();
  await ana.getByText(/tap a creature on the map/).waitFor({ timeout: 5000 });
  await shot(ana, 'ana_pick');
  // tap a creature Ana can see that is not one of the party
  await ana.waitForFunction(() => (window.hexmap.game.scene.tokens ?? []).some((x) => /Goblin/.test(x.name ?? '')), null, { timeout: 5000 });
  const at = await ana.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => !x.owner && !(x.tags ?? []).some((k) => k === 'place' || k === 'party'));
    const c = document.querySelector('canvas');
    return t && c?.screenOf ? { id: t.id, name: t.name, ...c.screenOf(t.id) } : null;
  });
  if (!at) throw new Error('Ana sees no creature to attack');
  const before = await ana.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length);
  await ana.mouse.click(at.x, at.y);
  // on a touch screen the tap asks first (a playtest's double tap to zoom fired an attack)
  await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
  const asks = await ana.getByRole('dialog', { name: 'Confirm the target' }).innerText();
  if (!asks.includes(at.name)) throw new Error(`the confirmation names the target (${at.name}): ${asks}`);
  await shot(ana, 'ana_confirm_target');
  await ana.getByRole('button', { name: 'Do it' }).click();
  await ana.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length > n, before, { timeout: 8000 });
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await shot(ana, 'ana_attack_rolled');
});

// (a playtest's tablet player never managed to drag her token: tap it, then where it goes)
await step('Ana taps Wren, then where she goes, and says yes', async () => {
  await ana.getByRole('tab', { name: /Map/ }).click();
  const w = await ana.evaluate(() => {
    const g = window.hexmap.game;
    const toks = g.scene.tokens ?? [];
    const t = toks.find((x) => x.owner === g.me);
    const c = document.querySelector('canvas');
    if (!t || !c?.screenOf) return null;
    const at = c.screenOf(t.id);
    const px = c.pxPerHex();
    // two cells off, where no one stands
    for (const [dx, dy] of [[-2, 0], [0, -1.7], [0, 1.7], [2, 0]]) {
      const x = Number(t.pos[0]) + dx;
      const y = Number(t.pos[1]) + dy;
      if (!toks.some((o) => Math.hypot(Number(o.pos[0]) - x, Number(o.pos[1]) - y) < 0.8)) return { id: t.id, name: t.name, pos: t.pos, at, to: { x: at.x + dx * px, y: at.y + dy * px } };
    }
    return null;
  });
  if (!w) throw new Error('Ana has no token, or nowhere free beside it');
  await ana.mouse.click(w.at.x, w.at.y);
  await ana.getByText(`Move ${w.name}: tap where to go`).waitFor({ timeout: 5000 });
  await ana.mouse.click(w.to.x, w.to.y);
  // on a touch screen the move asks first
  await ana.getByRole('dialog', { name: 'Confirm the move' }).waitFor({ timeout: 5000 });
  await shot(ana, 'ana_confirm_move');
  await ana.getByRole('button', { name: 'Move', exact: true }).click();
  await ana.waitForFunction(
    ([id, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
      return t && (t.pos[0] !== pos[0] || t.pos[1] !== pos[1]);
    },
    [w.id, w.pos],
    { timeout: 5000 },
  );
  await shot(ana, 'ana_moved');
});

await step('the DM ends the fight', async () => {
  await dm.locator('.fightbar').getByRole('button', { name: 'End the fight' }).click();
  await dm.getByRole('dialog', { name: 'End the fight?' }).getByRole('button', { name: 'End the fight' }).click();
  await dm.locator('.fightbar').waitFor({ state: 'detached', timeout: 8000 });
  await shot(dm, 'dm_after_fight');
});

await step('the DM sees the map as Ana does, and back', async () => {
  await dm.getByRole('combobox', { name: /See as/ }).selectOption({ label: 'Ana' });
  await dm.getByRole('status').filter({ hasText: 'Ana' }).first().waitFor({ timeout: 8000 });
  await shot(dm, 'dm_sees_as_ana');
  await dm.getByRole('button', { name: 'Back to yours' }).click();
  await dm.getByRole('button', { name: 'Back to yours' }).waitFor({ state: 'detached', timeout: 8000 });
});

await step('the DM makes a fight of their own: a goblin, started, ended', async () => {
  await dm.getByRole('button', { name: '+ New fight' }).click();
  await dm.getByRole('textbox', { name: 'Name' }).first().waitFor({ timeout: 8000 });
  await dm.getByRole('searchbox', { name: 'Find a creature' }).fill('goblin');
  await dm.locator('.found').first().waitFor({ timeout: 8000 });
  await dm.locator('.found').first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).waitFor({ timeout: 8000 });
  await dm.waitForFunction(() => document.querySelector('.fightcard .line') !== null, null, { timeout: 8000 });
  await shot(dm, 'dm_new_fight');
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 10000 });
  // the chat beside the fight, a pane of its own
  await dm.locator('.fightchat').getByLabel('Message').waitFor({ timeout: 5000 });
  await dm.locator('.fightchat').getByRole('heading', { name: 'Chat & rolls' }).waitFor({ timeout: 5000 });
  await shot(dm, 'dm_new_fight_on');
  await dm.locator('.fightbar').getByRole('button', { name: 'End the fight' }).click();
  await dm.getByRole('dialog', { name: 'End the fight?' }).getByRole('button', { name: 'End the fight' }).click();
  await dm.locator('.fightbar').waitFor({ state: 'detached', timeout: 8000 });
});

await step('Ana’s journal keeps what she was shown', async () => {
  await ana.getByRole('tab', { name: /Journal/ }).click();
  await ana.getByRole('button', { name: 'Thornwick' }).first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_journal');
});

await step('a reload keeps what Ana has read of the chat', async () => {
  await ben.getByRole('tab', { name: /Chat/ }).click();
  await ben.getByLabel('Message').fill('One more thing before we go.');
  await ben.getByRole('button', { name: 'Send' }).click();
  const badge = ana.getByRole('tab', { name: /Chat/ }).locator('.badge');
  // (the badge may be up already, from the fight's rolls: wait for Ben's line itself)
  await ana.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => e.kind === 'chat' && e.text === 'One more thing before we go.'), null, { timeout: 5000 });
  await badge.waitFor({ timeout: 5000 });
  await ana.waitForTimeout(300);
  const before = await badge.textContent();
  await ana.reload();
  await ana.getByRole('tab', { name: /Journal/ }).waitFor({ timeout: 10000 });
  await ana.waitForTimeout(1500);
  const after = (await badge.count()) ? await badge.textContent() : '0';
  // (a reload counted the whole log as new: a playtest's badge said 279)
  if (after !== before) throw new Error(`Chat’s badge said ${before} before a reload and ${after} after`);
});

await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):\n- ${problems.join('\n- ')}`);
  process.exit(1);
}
console.log(`\nthe journey went through; ${n} screenshots in ${out}`);
