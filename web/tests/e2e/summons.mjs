// A creature a spell makes, in a real browser against a real table (the
// owner: "things with hit points, familiars and summons and the like need to
// become full tokens with accessible stat blocks also controlled by the
// casting player"): the DM gives Sela Find Familiar; in the chapel fight, on
// her turn, Ana casts it on her phone, choosing its form as it's cast; the
// familiar comes up on the map beside Sela, and her Character tab has a tab
// of its own with its stat block; on its own turn (a slot of its own in the
// order) Ana moves it on the map and ends its turn from its tab; a goblin's
// arrow drops it to 0 hit points, and it's gone — from the map, the order and
// her tabs. Screenshots of each step.
//
//   node tests/e2e/summons.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party --wizard (Ana's Sela, a wizard) and --seed 12.
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/summons.mjs <host.json> <out dir>');
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
  console.log(`\nthe familiar came, moved, took its turn and went; ${n} screenshots in ${out}`);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');

// A token on a page's map by its name (or a test of it): where it is and
// where it's drawn on the screen.
const token = (page, name) =>
  page.evaluate((name) => {
    const g = window.hexmap.game;
    const c = document.querySelector('canvas');
    const t = (g.scene.tokens ?? []).find((x) => (x.name ?? '') === name);
    if (!t) return null;
    return { id: t.id, actor: t.actor, name: t.name, owner: t.owner ?? '', pos: [Number(t.pos[0]), Number(t.pos[1])], at: c?.screenOf ? c.screenOf(t.id) : null, px: c?.pxPerHex ? c.pxPerHex() : 0 };
  }, name);

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

// A space near a token on Ana's map (map units; a cell a unit across), free of
// creatures, in her sight, on her screen: its centre on the screen, or null.
const spaceNear = (from, rings) =>
  ana.evaluate(
    ([from, rings]) => {
      const g = window.hexmap.game;
      const c = document.querySelector('canvas');
      const toks = g.scene.tokens ?? [];
      const gd = (g.maps[String(g.scene.map ?? '')] ?? {}).grid ?? {};
      const R = 1 / Math.sqrt(3);
      const cols = gd.columns ?? 20;
      const rows = gd.rows ?? 14;
      const snap = (x, y) => {
        if (gd.shape === 'square') {
          const col = Math.floor(x);
          const row = Math.floor(y);
          return col >= 0 && row >= 0 && col < cols && row < rows ? [col + 0.5, row + 0.5] : null;
        }
        if (gd.orientation === 'flat') return [x, y];
        const row = Math.round((y - R) / (1.5 * R));
        const shift = ((row & 1) === 1) === (gd.offset !== 'even') ? 0.5 : 0;
        const col = Math.round(x - 0.5 - shift);
        return col >= 0 && row >= 0 && col < cols && row < rows ? [col + 0.5 + shift, row * 1.5 * R + R] : null;
      };
      const inPoly = (p, poly) => {
        let inside = false;
        for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
          const [xi, yi] = poly[i];
          const [xj, yj] = poly[j];
          if (yi > p.y !== yj > p.y && p.x < ((xj - xi) * (p.y - yi)) / (yj - yi) + xi) inside = !inside;
        }
        return inside;
      };
      const polys = [...(g.scene.visible ?? []), ...(g.scene.los ?? [])].filter((poly) => Array.isArray(poly) && poly.length >= 3);
      const open = (x, y) => !g.scene.fog || polys.some((poly) => inPoly({ x, y }, poly));
      const r = c.getBoundingClientRect();
      const px = c.pxPerHex();
      const alone = (t) => !toks.some((o) => o !== t && Math.hypot(Number(o.pos[0]) - Number(t.pos[0]), Number(o.pos[1]) - Number(t.pos[1])) < 0.5);
      const ref = toks.find((t) => !(t.tags ?? []).includes('object') && alone(t)) ?? toks[0];
      const refAt = c.screenOf(ref.id);
      const screen = (x, y) => ({ x: refAt.x + (x - Number(ref.pos[0])) * px, y: refAt.y + (y - Number(ref.pos[1])) * px });
      for (const k of rings) {
        for (let a = 0; a < 12; a++) {
          const cell = snap(from[0] + Math.cos((a * Math.PI) / 6) * k, from[1] + Math.sin((a * Math.PI) / 6) * k);
          if (!cell) continue;
          const [x, y] = cell;
          if (!open(x, y)) continue;
          if (Math.hypot(x - from[0], y - from[1]) < 0.6) continue;
          if (toks.some((o) => Math.hypot(Number(o.pos[0]) - x, Number(o.pos[1]) - y) < 0.8)) continue;
          const s = screen(x, y);
          if (s.x < r.left + 24 || s.x > r.right - 64 || s.y < r.top + 130 || s.y > r.bottom - 130) continue;
          return { pos: [x, y], at: s };
        }
      }
      return null;
    },
    [from, rings],
  );

// Ana's Character tab on one of hers (a roll's line over the top closed first).
async function anaTab(name) {
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.locator('button.rolled').click({ timeout: 1000 }).catch(() => {});
  await ana.locator('.who').getByRole('tab', { name }).click({ timeout: 5000 });
}

// The card the table puts in front of Ana (it opens by itself, or from its pill).
async function cardOnAna() {
  const card = ana.getByRole('dialog', { name: 'The DM asks' });
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

let ok = await step('Ana joins as Sela; the DM gives Sela Find Familiar on her card', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await dm.locator('.book').getByRole('button', { name: /^Sela/ }).first().click();
  await dm.getByRole('tab', { name: 'Spells' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a spell (any list, any level)' });
  await give.locator('input[type=search]').fill('find familiar');
  await give.getByRole('button', { name: 'Give Find Familiar' }).click({ timeout: 8000 });
  // a wizard's spellbook has it now; the DM puts it on her prepared list
  const given = dm.locator('.row').filter({ hasText: /Find Familiar \(/ }).first();
  await given.getByRole('button', { name: 'Prepare' }).click({ timeout: 8000 });
  await dm.locator('.row').filter({ hasText: /● Find Familiar \(/ }).first().waitFor({ timeout: 5000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.locator('.row').filter({ hasText: /Find Familiar \(/ }).first().waitFor({ timeout: 8000 });
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

ok = ok && (await step('on Sela’s turn Ana casts Find Familiar at a space beside her, choosing an owl (fey) as it’s cast', async () => {
  await nextUntil('Sela');
  await ana.locator('.turn').filter({ hasText: /Your turn: Sela/ }).waitFor({ timeout: 5000 });
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Find Familiar \(/ }).first();
  await row.getByRole('button', { name: 'Cast', exact: true }).click();
  await ana.getByText('Cast: tap a space on the map').waitFor({ timeout: 5000 });
  const sela = await token(ana, 'Sela');
  expect(sela?.at, 'no Sela on Ana’s map');
  // one space off (the spell's range is 10 feet)
  const place = await spaceNear(sela.pos, [1, 1.7]);
  expect(place, 'no space beside Sela to cast at');
  await ana.mouse.click(place.at.x, place.at.y);
  await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Do it' }).click();
  const card = await cardOnAna();
  await card.getByText(/Find Familiar/).first().waitFor({ timeout: 3000 });
  await card.getByRole('combobox', { name: 'Its form' }).selectOption({ label: 'Owl' });
  await card.getByRole('combobox', { name: 'It is a Celestial, Fey or Fiend instead of a Beast' }).selectOption({ label: 'Fey' });
  await shot(ana, 'ana_familiar_choice');
  await card.getByRole('button', { name: 'Cast Find Familiar' }).click();
  await ana.waitForFunction(() => (window.hexmap.game.scene.tokens ?? []).some((t) => t.name === 'Owl' && t.owner === window.hexmap.game.me), null, { timeout: 8000 });
  const owl = await token(ana, 'Owl');
  expect(Math.hypot(owl.pos[0] - place.pos[0], owl.pos[1] - place.pos[1]) < 0.6, `the owl came up at ${owl.pos}, not where she cast it (${place.pos})`);
  await ana.getByRole('tab', { name: /Map/ }).click();
  await shot(ana, 'ana_owl_on_the_map');
}));

ok = ok && (await step('her Character tab: a tab for the owl, its stat block saying whose it is, and a slot of its own in the order', async () => {
  // Sela's sheet in front, the owl's a tab beside it
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.locator('button.rolled').click({ timeout: 1000 }).catch(() => {});
  await ana.locator('.who').getByRole('tab', { name: 'Sela', selected: true }).waitFor({ timeout: 5000 });
  await anaTab('Owl');
  await ana.getByText(/Sela's familiar \(Find Familiar\): it can't attack/).first().waitFor({ timeout: 5000 });
  await ana.getByText('Small Fey, unaligned').first().waitFor({ timeout: 3000 });
  await ana.getByRole('button', { name: 'End its turn' }).waitFor({ timeout: 3000 });
  await shot(ana, 'ana_owl_tab');
  // its own slot in the order (it rolled its own initiative)
  await dm.locator('.order .row').filter({ hasText: /\bOwl\b/ }).first().waitFor({ timeout: 5000 });
  await shot(dm, 'dm_order_with_owl');
  await anaTab('Sela');
}));

ok = ok && (await step('the owl’s own turn: Ana moves it on the map and ends its turn from its tab', async () => {
  await nextUntil('Owl');
  await ana.locator('.turn').filter({ hasText: /Your turn: Owl/ }).waitFor({ timeout: 5000 });
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForTimeout(500);
  const owl = await token(ana, 'Owl');
  expect(owl?.at, 'no owl on Ana’s map');
  const place = await spaceNear(owl.pos, [2, 1.7, 1]);
  expect(place, 'no space near the owl to fly to');
  await ana.mouse.click(owl.at.x, owl.at.y);
  await ana.getByText('Move Owl: tap where to go').waitFor({ timeout: 5000 });
  await ana.mouse.click(place.at.x, place.at.y);
  await ana.getByRole('dialog', { name: 'Confirm the move' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Move', exact: true }).click();
  await ana.waitForFunction(
    ([id, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
      return t && Math.hypot(Number(t.pos[0]) - pos[0], Number(t.pos[1]) - pos[1]) > 0.2;
    },
    [owl.id, owl.pos],
    { timeout: 5000 },
  );
  await shot(ana, 'ana_owl_moved');
  const was = await turnNow();
  await anaTab('Owl');
  await ana.getByRole('button', { name: 'End its turn' }).click({ timeout: 5000 });
  await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was, { timeout: 5000 });
  await dm.locator('.fightbar').getByText(/Owl’s turn/).waitFor({ state: 'detached', timeout: 3000 });
  await shot(dm, 'dm_after_owls_turn');
}));

ok = ok && (await step('a goblin’s arrow drops the owl to 0: it’s gone — from the map, the order and Ana’s tabs', async () => {
  // (by their tokens: every goblin is "Goblin Warrior")
  const goblins = await dm.evaluate(() => (window.hexmap.game.scene.tokens ?? []).filter((t) => /^Goblin/.test(t.name ?? '')).map((t) => t.id));
  let gone = false;
  for (let round = 0; round < 3 && !gone; round++) {
    for (const g of goblins) {
      await dm.locator(`.order [data-token="${g}"]`).click();
      await dm.locator('.chosen').waitFor({ timeout: 5000 });
      const bow = dm.locator('.chosen .row').filter({ hasText: /^Shortbow\./ }).first();
      if (!(await bow.count())) continue;
      await bow.getByRole('button', { name: 'Use' }).click();
      const banner = dm.getByRole('group', { name: 'Choose the target' });
      await banner.waitFor({ timeout: 5000 });
      const choice = banner.locator('.choice').filter({ hasText: /^Owl/ }).first();
      if (!(await choice.count())) {
        await banner.getByRole('button', { name: /Cancel|Stop/ }).first().click().catch(() => {});
        continue;
      }
      await choice.click();
      await banner.getByRole('button', { name: 'Done' }).click();
      gone = await ana
        .waitForFunction(() => !(window.hexmap.game.scene.tokens ?? []).some((t) => t.name === 'Owl'), null, { timeout: 4000 })
        .then(
          () => true,
          () => false,
        );
      if (gone) break;
    }
  }
  expect(gone, 'no goblin’s arrow dropped the owl');
  await dm.waitForFunction(() => !(window.hexmap.game.scene.tokens ?? []).some((t) => t.name === 'Owl'), null, { timeout: 5000 });
  await dm.locator('.order .row').filter({ hasText: /\bOwl\b/ }).waitFor({ state: 'detached', timeout: 5000 });
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.locator('.who').getByRole('tab', { name: 'Owl' }).waitFor({ state: 'detached', timeout: 5000 });
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText(/Owl.*(vanishes|is gone|disappears)/).first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_owl_gone');
  await shot(dm, 'dm_owl_gone');
}));

await finish();
