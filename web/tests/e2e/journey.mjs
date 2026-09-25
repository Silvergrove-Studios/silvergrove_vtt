// The next playtest's journey, in a real browser against a real table:
// the DM's screen and two players' screens (one a phone), the village
// (a place's card, shown to the players, chat and a private message), a
// character sheet, and the chapel fight (launched, initiative, an attack
// picked on the map, ended). Screenshots of each step go to the output
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

await step('the DM invites: a code and an address', async () => {
  await dm.getByRole('button', { name: 'Invite players' }).first().click();
  await dm.getByText('Open a player’s screen on this computer').waitFor();
  await shot(dm, 'dm_invite');
  await dm.getByRole('button', { name: 'Close' }).click();
});

await step('the DM starts the session', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click();
  await dm.getByText(/Session 1/).first().waitFor({ timeout: 5000 });
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
  await cara.getByRole('button', { name: 'Next' }).click();
  const scores = { Strength: 15, Dexterity: 13, Constitution: 14, Intelligence: 8, Wisdom: 12, Charisma: 10 };
  for (const [label, v] of Object.entries(scores)) await row(label).locator('input').fill(String(v));
  await cara.getByRole('button', { name: 'Next' }).click();
  await row('Skills').locator('input').fill('Athletics, Perception');
  await cara.getByRole('button', { name: 'Submit' }).click();
  await cara.getByText('Human Fighter 1').first().waitFor({ timeout: 10000 });
  await shot(cara, 'cara_sheet');
});

await step('the DM asks the party for a roll; the players answer', async () => {
  await dm.getByRole('tab', { name: 'Party' }).click();
  const before = await dm.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length);
  await dm.getByRole('button', { name: 'Ask', exact: true }).click();
  for (const p of [ana, ben, cara]) {
    if (!p) continue;
    await p.getByRole('dialog', { name: 'The DM asks' }).waitFor({ timeout: 8000 });
  }
  await shot(ana, 'ana_asked');
  for (const p of [ana, ben, cara]) if (p) await p.getByRole('button', { name: 'Answer' }).click();
  await dm.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length >= n + 3, before, { timeout: 10000 });
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

await step('the chapel: the DM starts the fight', async () => {
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.waitForTimeout(1200);
  await dm.getByRole('button', { name: 'Close the card' }).click();
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
  for (let i = 0; i < 12; i++) {
    if (await dm.locator('.fightbar').getByText(/Wren’s turn/).count()) return;
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    await dm.waitForTimeout(300);
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
  await ana.waitForFunction((n) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length > n, before, { timeout: 8000 });
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await shot(ana, 'ana_attack_rolled');
});

await step('the DM ends the fight', async () => {
  await dm.getByRole('button', { name: 'End the fight' }).first().click();
  await dm.locator('.fightbar').getByRole('button', { name: 'End the fight' }).last().click();
  await dm.locator('.fightbar').waitFor({ state: 'detached', timeout: 8000 });
  await shot(dm, 'dm_after_fight');
});

await step('Ana’s journal keeps what she was shown', async () => {
  await ana.getByRole('tab', { name: /Journal/ }).click();
  await ana.getByRole('button', { name: 'Thornwick' }).first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_journal');
});

await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):\n- ${problems.join('\n- ')}`);
  process.exit(1);
}
console.log(`\nthe journey went through; ${n} screenshots in ${out}`);
