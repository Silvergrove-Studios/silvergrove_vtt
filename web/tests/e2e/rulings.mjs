// The DM's rulings and the approval step, in a real browser. An Assisted
// table: the DM turns on "Approve outcomes before they land" in Rules
// settings; in the chapel fight a goblin's scimitar hits Wren (Ana's rogue):
// the roll is in everyone's chat at once, its damage waits on the DM's card
// (in front at once; Ana's phone and Ben's screen say the table waits on the
// DM) and Wren's hit points don't move; the DM changes the damage and
// applies it, and the log says so. A later hit the DM applies as it is; then,
// from that roll's line in Chat & rolls, the DM calls it a miss: the damage
// is healed back, and the log says that too. Screenshots of each step go to
// the output folder; a step that does not happen fails the run.
//
//   node tests/e2e/rulings.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, started with --party (Ana's
// character is Wren, a halfling rogue: no reaction to ask) and a --seed whose
// dice let a goblin hit her twice.
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/rulings.mjs <host.json> <out dir>');
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
  await page.addLocatorHandler(page.getByRole('dialog', { name: 'How this table runs' }), async () => {
    await page.getByRole('dialog', { name: 'How this table runs' }).getByRole('button', { name: 'Got it' }).click();
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

// Wren's token and hit points, as the DM's screen has them
const wren = () =>
  dm.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    const a = t ? g.view.actors?.[t.actor] : null;
    return t ? { id: t.id, actor: t.actor, pos: t.pos, hp: a?.resources?.srd5e?.hp?.current } : null;
  });

// the DM's card for an outcome: in front, headed "To approve"
const card = () => dm.getByRole('dialog', { name: 'To approve' });

await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
});

await step('an Assisted table: the DM turns on Approve outcomes before they land', async () => {
  // (Rules settings, or Table settings where the table has levels)
  await dm.getByRole('button', { name: /^(Rules|Table) settings/ }).first().click();
  const box = dm.getByRole('dialog', { name: /^(Rules|Table) settings$/ });
  await box.waitFor({ timeout: 5000 });
  const row = box.locator('li').filter({ hasText: 'Approve outcomes before they land' });
  await row.locator('input[type="checkbox"]').check();
  await row.getByText('On', { exact: true }).waitFor({ timeout: 5000 });
  await shot(dm, 'dm_rules_settings');
  await box.getByRole('button', { name: 'Done' }).click();
  await box.waitFor({ state: 'detached', timeout: 5000 });
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
});

let goblins = [];
await step('the DM puts the party inside and Wren beside a goblin', async () => {
  const where = await dm.evaluate(() => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const gobs = toks.filter((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? ''));
    const c = document.querySelector('canvas');
    if (!gobs.length || !c?.screenOf) return null;
    return { at: c.screenOf(gobs[0].id), px: c.pxPerHex(), gob: gobs[0].id, names: gobs.map((g) => g.name) };
  });
  if (!where) throw new Error('no goblin on the DM’s map');
  goblins = where.names;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(600);
  const w = await wren();
  if (!w) throw new Error('no Wren on the map');
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
});

// A round goes by: Next turn until the round is the next one (each goblin's
// action back on its turn).
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

// One goblin's attack at Wren, by its row's name: true when it hit (its card
// in front of the DM).
async function swing(goblin, attack) {
  await dm.locator('.order .row').filter({ hasText: goblin }).first().click();
  await dm.locator('.chosen').waitFor({ timeout: 5000 });
  await dm.locator('.chosen .row').filter({ hasText: attack }).first().getByRole('button', { name: 'Use' }).click();
  const banner = dm.getByRole('group', { name: 'Choose the target' });
  await banner.waitFor({ timeout: 5000 });
  await banner.locator('.choice').filter({ hasText: /^Wren/ }).first().click();
  await banner.getByRole('button', { name: 'Done' }).click();
  return card().waitFor({ timeout: 4000 }).then(
    () => true,
    () => false,
  );
}

// The goblins at Wren, one after another, until one hits: its card comes up
// in front of the DM. Each swings its scimitar (the goblins round their fire
// are all beside her), shooting only when she's out of its reach; a round of
// misses, and the next round comes.
async function aGoblinHitsWren() {
  for (let round = 0; round < 3; round++) {
    for (const g of goblins) {
      if (await swing(g, /^Scimitar\./)) return g;
      if ((await dm.getByText(/out of reach/).count()) > 0 && (await swing(g, /^Shortbow\./))) return g;
    }
    await nextRound();
  }
  throw new Error('no goblin hit Wren (pick another --seed)');
}
let proposed = 0;

let before = null;
await step('a goblin’s hit on Wren: its roll in the chat at once, its damage waiting on the DM’s card; Ana and Ben told the table waits on the DM; Wren unhurt', async () => {
  before = await wren();
  await aGoblinHitsWren();
  const c = card();
  const words = await c.innerText();
  const m = /hits Wren — Wren: (\d+) (slashing|piercing) damage \(\d+ → \d+ hit points/.exec(words);
  if (!m) throw new Error(`the card: ${words}`);
  proposed = Number(m[1]);
  for (const b of ['Apply', 'Change…', 'Skip']) await c.getByRole('button', { name: b }).waitFor({ timeout: 3000 });
  await shot(dm, 'dm_card_to_approve');
  // the roll reached the players at once
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText(/Scimitar|Shortbow/).first().waitFor({ timeout: 5000 });
  // everyone told whom the table waits on
  await ana.getByRole('status', { name: 'What the table waits on' }).getByText('Waiting on the DM: an outcome to approve').waitFor({ timeout: 5000 });
  await ben.getByRole('status', { name: 'What the table waits on' }).getByText('Waiting on the DM: an outcome to approve').waitFor({ timeout: 5000 });
  await shot(ana, 'ana_waiting_on_the_dm');
  const now = await wren();
  if (now.hp !== before.hp) throw new Error(`Wren was hurt before the DM applied it: ${before.hp} → ${now.hp}`);
});

let changedTo = 0;
await step('the DM changes the damage and applies it: Wren takes the DM’s number, and the log says so', async () => {
  const c = card();
  await dm.waitForTimeout(700);
  await c.getByRole('button', { name: 'Change…' }).click();
  // the second card: the amount it deals, the proposed one to start from
  const amount = card().getByRole('spinbutton', { name: /Wren: (slashing|piercing) damage/ });
  await amount.waitFor({ timeout: 5000 });
  // (the proposed amount to start from, once the card has filled it in)
  await dm.waitForFunction((want) => [...document.querySelectorAll('input[type="number"]')].some((i) => Number(i.value) === want), proposed, { timeout: 5000 });
  changedTo = Math.max(1, proposed - 2);
  await amount.fill(String(changedTo));
  await shot(dm, 'dm_change_card');
  await dm.waitForTimeout(700);
  await card().getByRole('button', { name: 'Apply these' }).click();
  await card().waitFor({ state: 'detached', timeout: 8000 });
  await dm.waitForFunction((hp) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    return (g.view.actors?.[t.actor]?.resources?.srd5e?.hp?.current ?? hp) < hp;
  }, before.hp, { timeout: 8000 });
  const now = await wren();
  if (now.hp !== before.hp - changedTo) throw new Error(`Wren: ${before.hp} → ${now.hp}, not the DM's ${changedTo}`);
  await ana.getByText(new RegExp(`The DM changes it — Wren: ${changedTo} (slashing|piercing) damage \\(${proposed} proposed\\)`)).first().waitFor({ timeout: 8000 });
  await ana.getByRole('status', { name: 'What the table waits on' }).waitFor({ state: 'detached', timeout: 5000 });
  await shot(ana, 'ana_the_dm_changed_it');
});

let hit = null;
await step('a later hit, applied as it is; then, from its line in Chat & rolls, the DM calls it a miss: the damage is healed back, and said', async () => {
  before = await wren();
  await aGoblinHitsWren();
  await dm.waitForTimeout(700);
  await card().getByRole('button', { name: 'Apply' }).click();
  await card().waitFor({ state: 'detached', timeout: 8000 });
  await dm.waitForFunction((hp) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    return (g.view.actors?.[t.actor]?.resources?.srd5e?.hp?.current ?? hp) < hp;
  }, before.hp, { timeout: 8000 });
  const hurt = await wren();
  const dealt = before.hp - hurt.hp;
  // the attack's line: the newest roll the DM may call a miss
  hit = await dm.evaluate(() => {
    const log = window.hexmap.game.view.log ?? [];
    for (let i = log.length - 1; i >= 0; i--) {
      const acts = log[i]?.dm?.srd5e?.actions ?? [];
      if (log[i].kind === 'roll' && acts.some((a) => a.label === 'Call it a miss')) return { id: log[i].id, label: log[i].label };
    }
    return null;
  });
  if (!hit) throw new Error('no attack roll the DM may call a miss');
  const line = dm.locator(`[data-line="${hit.id}"]`);
  await line.scrollIntoViewIfNeeded();
  await line.hover();
  await line.getByRole('button', { name: 'Rule' }).click();
  const rulings = line.getByRole('group', { name: 'Rule on it' });
  for (const b of ['Call it a miss', 'Change the total', 'Reroll']) await rulings.getByRole('button', { name: b }).waitFor({ timeout: 3000 });
  await shot(dm, 'dm_rule_on_the_hit');
  await rulings.getByRole('button', { name: 'Call it a miss' }).click();
  await dm.waitForFunction((hp) => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => x.name === 'Wren');
    return g.view.actors?.[t.actor]?.resources?.srd5e?.hp?.current === hp;
  }, before.hp, { timeout: 8000 });
  await ana.getByText(new RegExp(`The DM calls it a miss: ${dealt} healed back to Wren`)).first().waitFor({ timeout: 8000 });
  // the log keeps both lines: the roll as it was rolled, and the ruling
  const kept = await ana.evaluate((id) => (window.hexmap.game.view.log ?? []).some((e) => e.id === id && e.kind === 'roll' && !e.dm), hit.id);
  if (!kept) throw new Error('the roll’s line is gone from Ana’s chat, or carries the DM’s buttons');
  await shot(ana, 'ana_called_a_miss');
  await shot(dm, 'dm_called_a_miss');
});

await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log('\nevery step went');
