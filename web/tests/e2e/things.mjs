// Things on the map that their caster moves, in a real browser against a
// real table (the owner: "dancing lights should be able to split up the
// lights, and they should be able to be on the same square as a player"):
// the DM gives Wren Dancing Lights; in the chapel fight, on Wren's turn, Ana
// casts it on her phone at a space, its four lights come up on the map, and
// her sheet says how they move; she taps one light and then Wren, and it
// goes onto Wren's own square (Wren still there, whole, the light at a
// corner of her space); she taps another and a space away from Wren, and it
// goes there; one sent off alone is refused, the table saying why. The DM's
// map shows them where hers does. Screenshots of each step.
//
//   node tests/e2e/things.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e
// with --party (Ana's Wren, a halfling rogue).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/things.mjs <host.json> <out dir>');
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
  console.log(`\nthe lights went where Ana sent them; ${n} screenshots in ${out}`);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');

// What Ana's map has: Wren, her lights (by name), each where it is drawn on
// the screen, and the canvas's box. Run in her page.
const look = () =>
  ana.evaluate(() => {
    const g = window.hexmap.game;
    const toks = g.scene.tokens ?? [];
    const c = document.querySelector('canvas');
    if (!c?.screenOf) return null;
    const isThing = (t) => (t.tags ?? []).includes('object');
    const wren = toks.find((t) => t.owner === g.me && !isThing(t));
    const lights = toks
      .filter((t) => t.owner === g.me && isThing(t))
      .map((t) => ({ id: t.id, name: t.name, pos: [Number(t.pos[0]), Number(t.pos[1])], at: c.screenOf(t.id) }))
      .sort((a, b) => String(a.name).localeCompare(String(b.name)));
    const r = c.getBoundingClientRect();
    return {
      wren: wren ? { id: wren.id, name: wren.name, pos: [Number(wren.pos[0]), Number(wren.pos[1])], at: c.screenOf(wren.id) } : null,
      lights,
      px: c.pxPerHex(),
      box: { x0: r.left, y0: r.top, x1: r.right, y1: r.bottom },
      creatures: toks.filter((t) => !isThing(t)).map((t) => [Number(t.pos[0]), Number(t.pos[1])]),
    };
  });

// A space near `from` (map units, a cell a unit across): the centre of the
// cell each offset lands in, the first that is on the map, in Ana's sight or
// her line of sight, on her screen (clear of its header and buttons) and
// free of creatures (and `also`, a test of the place). Run in her page.
const placeNear = (from, offsets, also = null) =>
  ana.evaluate(
    ([from, offsets, also]) => {
      const g = window.hexmap.game;
      const c = document.querySelector('canvas');
      const toks = g.scene.tokens ?? [];
      // the cell a point is in, as the web client's Grid has it: its centre, or null off the map
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
      // (the screen's own point for a map point, as screenOf works it out for
      // a token alone on its space: drawn where it is)
      const alone = (t) => !toks.some((o) => o !== t && Math.hypot(Number(o.pos[0]) - Number(t.pos[0]), Number(o.pos[1]) - Number(t.pos[1])) < 0.5);
      const ref = toks.find((t) => !(t.tags ?? []).includes('object') && alone(t)) ?? toks[0];
      const refAt = c.screenOf(ref.id);
      const screen = (x, y) => ({ x: refAt.x + (x - Number(ref.pos[0])) * px, y: refAt.y + (y - Number(ref.pos[1])) * px });
      const test = also ? new Function('x', 'y', `return (${also})`) : () => true;
      for (const [dx, dy] of offsets) {
        const cell = snap(from[0] + dx, from[1] + dy);
        if (!cell) continue;
        const [x, y] = cell;
        if (!open(x, y) || !test(x, y)) continue;
        if (toks.some((o) => !(o.tags ?? []).includes('object') && Math.hypot(Number(o.pos[0]) - x, Number(o.pos[1]) - y) < 0.8)) continue;
        const s = screen(x, y);
        if (s.x < r.left + 24 || s.x > r.right - 64 || s.y < r.top + 130 || s.y > r.bottom - 130) continue;
        return { pos: [x, y], at: s };
      }
      return null;
    },
    [from, offsets, also],
  );

const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

// Ana taps her light, then `to` on the screen, and says yes; true once it has moved.
async function sendLight(light, to) {
  await ana.mouse.click(light.at.x, light.at.y);
  await ana.getByText(`Move ${light.name}: tap where to go`).waitFor({ timeout: 5000 });
  await ana.mouse.click(to.x, to.y);
  await ana.getByRole('dialog', { name: 'Confirm the move' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Move', exact: true }).click();
  return ana
    .waitForFunction(
      ([id, pos]) => {
        const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
        return t && Math.hypot(Number(t.pos[0]) - pos[0], Number(t.pos[1]) - pos[1]) > 0.2;
      },
      [light.id, light.pos],
      { timeout: 4000 },
    )
    .then(
      () => true,
      () => false,
    );
}

let ok = await step('Ana joins; the DM gives Wren Dancing Lights on her card', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.locator('#name').fill('Ana');
  await ana.getByRole('button', { name: 'Join' }).click();
  await ana.getByText('Free movement').waitFor({ timeout: 10000 });
  await dm.locator('.book').getByRole('button', { name: /^Wren/ }).first().click();
  await dm.getByRole('tab', { name: 'Spells' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a spell (any list, any level)' });
  await give.locator('input[type=search]').fill('dancing');
  await give.getByRole('button', { name: 'Give Dancing Lights' }).click({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
  // her Spells tab has it, and says before it is cast how its lights move
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.locator('.row').filter({ hasText: /Dancing Lights \(cantrip/ }).first().waitFor({ timeout: 8000 });
  await ana.getByText(/^Dancing Lights: 4 lights — Bonus Action to move them, each up to 60 feet/).first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_spell_given');
});

ok = ok && (await step('the chapel fight: started, initiative rolled, the turns moved on to Wren', async () => {
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 });
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForFunction(() => window.hexmap.game.scene.role === 'battle' && window.hexmap.game.scene.turns?.mode === 'ordered', null, { timeout: 8000 });
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  const turnNow = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);
  const stillHas = dm.locator('.fightbar').getByRole('group', { name: 'End the turn anyway?' });
  for (let i = 0; i < 12; i++) {
    if (await dm.locator('.fightbar').getByText(/Wren’s turn/).count()) break;
    const was = await turnNow();
    await dm.getByRole('button', { name: 'Next turn ›' }).click();
    await dm.waitForFunction(
      (b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b || !!document.querySelector('.fightbar [aria-label="End the turn anyway?"]'),
      was,
      { timeout: 5000 },
    );
    // (Ben isn't here: the DM ends Brakka's turn anyway)
    if (await stillHas.count()) await stillHas.getByRole('button', { name: 'End it' }).click();
    await dm.waitForFunction((b) => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}` !== b, was, { timeout: 5000 });
  }
  await dm.locator('.fightbar').getByText(/Wren’s turn/).waitFor({ timeout: 2000 });
  await ana.locator('.turn').filter({ hasText: /Your turn: Wren/ }).waitFor({ timeout: 5000 });
}));

let before = null;
ok = ok && (await step('Ana casts Dancing Lights at a space: four lights on the map, and her sheet says how they move', async () => {
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  const row = ana.locator('.row').filter({ hasText: /Dancing Lights \(cantrip/ }).first();
  await row.getByRole('button', { name: 'Cast', exact: true }).click();
  await ana.getByText('Cast: tap a space on the map').waitFor({ timeout: 5000 });
  const seen = await look();
  expect(seen?.wren, 'Ana has no Wren on her map');
  // three spaces off, where no one stands, in her sight
  const r = 3;
  const offsets = [[r, 0], [-r, 0], [r / 2, r * 0.866], [r / 2, -r * 0.866], [-r / 2, r * 0.866], [-r / 2, -r * 0.866], [0, r], [0, -r]];
  const place = await placeNear(seen.wren.pos, offsets);
  expect(place, 'no space three off Wren, in her sight, to cast at');
  await ana.mouse.click(place.at.x, place.at.y);
  await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Do it' }).click();
  await ana.waitForFunction(
    () => (window.hexmap.game.scene.tokens ?? []).filter((t) => (t.tags ?? []).includes('object') && t.owner === window.hexmap.game.me).length === 4,
    null,
    { timeout: 8000 },
  );
  before = await look();
  expect(before.lights.map((l) => l.name).join(',') === 'Light 1,Light 2,Light 3,Light 4', `her lights: ${before.lights.map((l) => l.name).join(', ')}`);
  // none on Wren's square yet: they came up round the space she tapped
  for (const l of before.lights) expect(dist(l.pos, before.wren.pos) > 0.9, `${l.name} came up on Wren`);
  await shot(ana, 'ana_lights_cast');
  // the sheet: what is hers on the map, and how it moves
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.getByText('On the map').first().waitFor({ timeout: 5000 });
  await ana.getByText(/^Dancing Lights: 4 lights — Bonus Action to move them, each up to 60 feet \(each within 20 feet of another/).first().waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'End it' }).first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_sheet_on_the_map');
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForTimeout(500);
}));

ok = ok && (await step('Ana taps Light 1, then Wren: the light goes onto Wren’s own square', async () => {
  const now = await look();
  const light = now.lights.find((l) => l.name === 'Light 1');
  expect(await sendLight(light, now.wren.at), 'Light 1 didn’t move onto Wren');
  const after = await look();
  const l1 = after.lights.find((l) => l.name === 'Light 1');
  expect(dist(l1.pos, after.wren.pos) < 0.3, `Light 1 is at ${l1.pos}, Wren at ${after.wren.pos}`);
  expect(dist(after.wren.pos, before.wren.pos) < 0.01, 'Wren moved');
  // drawn apart on the screen, so a tap finds either: Wren whole on her space, the light at its corner
  expect(dist([l1.at.x, l1.at.y], [after.wren.at.x, after.wren.at.y]) > after.px * 0.3, 'the light is drawn over Wren');
  // the moves of the turn: its first spent her bonus action
  await ana.locator('.turn').filter({ hasText: /Your turn: Wren/ }).waitFor({ timeout: 5000 });
  // the DM's map has it there too
  await dm.waitForFunction(
    ([lid, wpos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === lid);
      return t && Math.hypot(Number(t.pos[0]) - wpos[0], Number(t.pos[1]) - wpos[1]) < 0.3;
    },
    [l1.id, after.wren.pos],
    { timeout: 5000 },
  );
  await shot(ana, 'ana_light_on_wren');
}));

ok = ok && (await step('Ana taps Light 2, then a space away from Wren: it goes there', async () => {
  const now = await look();
  const light = now.lights.find((l) => l.name === 'Light 2');
  const others = now.lights.filter((l) => l.name === 'Light 3' || l.name === 'Light 4').map((l) => l.pos);
  // two spaces further from Wren, still near another light ("A light must be within 20 feet of another light")
  const ux = (light.pos[0] - now.wren.pos[0]) / dist(light.pos, now.wren.pos);
  const uy = (light.pos[1] - now.wren.pos[1]) / dist(light.pos, now.wren.pos);
  const offsets = [];
  for (const k of [2, 1.5, 1]) for (const turn of [0, 0.5, -0.5, 1, -1]) {
    const c = Math.cos(turn);
    const s = Math.sin(turn);
    offsets.push([(ux * c - uy * s) * k, (ux * s + uy * c) * k]);
  }
  const near = `(${JSON.stringify(others)}).some((o) => Math.hypot(o[0] - x, o[1] - y) < 3.5) && Math.hypot(x - ${now.wren.pos[0]}, y - ${now.wren.pos[1]}) > ${dist(light.pos, now.wren.pos) + 0.7}`;
  const place = await placeNear(light.pos, offsets, near);
  expect(place, 'no space away from Wren, near another light, for Light 2');
  expect(await sendLight(light, place.at), `Light 2 didn’t move: ${await ana.evaluate(() => (window.hexmap.game.notices ?? []).map((x) => x.text).join(' | '))}`);
  const after = await look();
  const l2 = after.lights.find((l) => l.name === 'Light 2');
  const l1 = after.lights.find((l) => l.name === 'Light 1');
  expect(dist(l2.pos, after.wren.pos) > dist(light.pos, now.wren.pos) + 0.5, `Light 2 went ${dist(light.pos, now.wren.pos).toFixed(1)} → ${dist(l2.pos, after.wren.pos).toFixed(1)} from Wren`);
  expect(dist(l1.pos, after.wren.pos) < 0.3, 'Light 1 stayed on Wren');
  await dm.waitForFunction(
    ([lid, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === lid);
      return t && Math.hypot(Number(t.pos[0]) - pos[0], Number(t.pos[1]) - pos[1]) < 0.3;
    },
    [l2.id, l2.pos],
    { timeout: 5000 },
  );
  await shot(ana, 'ana_light_away');
}));

ok = ok && (await step('Light 3 sent off alone: refused, the table saying why', async () => {
  const now = await look();
  const light = now.lights.find((l) => l.name === 'Light 3');
  const others = now.lights.filter((l) => l.name !== 'Light 3').map((l) => l.pos);
  const offsets = [];
  for (const k of [7, 8, 6.5, 9]) for (let a = 0; a < 12; a++) offsets.push([Math.cos((a * Math.PI) / 6) * k, Math.sin((a * Math.PI) / 6) * k]);
  const alone = `(${JSON.stringify(others)}).every((o) => Math.hypot(o[0] - x, o[1] - y) > 6)`;
  let place = await placeNear(light.pos, offsets, alone);
  // (none on the phone's screen: she zooms out a little, and looks again)
  for (let i = 0; i < 3 && !place; i++) {
    await ana.getByRole('button', { name: 'Zoom out' }).click();
    await ana.waitForTimeout(400);
    place = await placeNear(light.pos, offsets, alone);
  }
  expect(place, 'no space on screen far from the other lights');
  const moved = await look();
  expect(!(await sendLight(moved.lights.find((l) => l.name === 'Light 3'), place.at)), 'Light 3 went off alone');
  await ana.getByText('Light 3 must stay within 20 feet of another of the lights').first().waitFor({ timeout: 5000 });
  await shot(ana, 'ana_light_alone_refused');
}));

ok = ok && (await step('the DM’s map: Light 1 with Wren, the others where Ana left them', async () => {
  await dm.getByRole('button', { name: 'Show the whole map' }).click().catch(() => {});
  await dm.waitForTimeout(600);
  await shot(dm, 'dm_lights');
}));

await finish();
