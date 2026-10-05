// What the table sends the screens, measured, in a real browser against a
// real table: the DM's screen and Ana's phone through the chapel fight's
// first rounds (joined, the session and the fight started, initiative, the
// party inside, a goblin's attack, Ana's attacks on her turns, a line of
// chat, two rounds of turns), then Ana's phone dropping its connection and
// coming back, then the DM changing what the sheets' buttons do (the sheets
// built again). Every message each page receives is counted by its kind and
// its size, phase by phase; a view's, a scene's and the DM's state are taken
// apart by what they carry (the view schemas on their own) and by what was
// the same as in the one before.
//
//   node tests/e2e/traffic.mjs <host.json> <out dir> [--budget] [--frames]
//
// host.json is what tools/web_host.gd writes, started with --party --seed 12.
// Writes <out>/traffic.json and prints the tables. With --budget it also
// fails when a schema reaches a page twice unchanged, or a phone's views
// average more than VIEW_BUDGET bytes after the first. With --frames it
// writes every message each page received to <out>/frames.jsonl.
import { chromium } from 'playwright-core';
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const args = process.argv.slice(2);
const budget = args.includes('--budget');
const frames = args.includes('--frames');
const [infoPath, out] = args.filter((a) => !a.startsWith('--'));
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/traffic.mjs <host.json> <out dir> [--budget] [--frames]');
  process.exit(2);
}
// a phone's view, once it holds the schemas (what changes with each step)
const VIEW_BUDGET = 64 * 1024;
mkdirSync(out, { recursive: true });
const info = JSON.parse(readFileSync(infoPath, 'utf8'));
const browser = await chromium.launch({ channel: process.env.HEXMAP_BROWSER ?? 'chrome', headless: true });
const problems = [];
const pages = [];
let n = 0;
let phase = 'join';
const phases = ['join'];
// page -> phase -> kind -> {count, bytes, max}
const recv = {};
// page -> kind -> {count, bytes}
const sentBy = {};
// page -> kind -> the whole message before (parsed), for what repeats
const before = {};
// page -> kind -> the last message, whole or not (written out at the end)
const lastOf = {};
// page -> kind -> part -> {bytes, same}
const parts = {};
// page -> schema key (its JSON) -> times received
const schemaSeen = {};

const size = (v) => (v === undefined ? 0 : Buffer.byteLength(JSON.stringify(v), 'utf8'));

function tally(obj, keys, bytes) {
  let o = obj;
  for (const k of keys.slice(0, -1)) o = o[k] ??= {};
  const last = keys[keys.length - 1];
  const r = (o[last] ??= { count: 0, bytes: 0, max: 0 });
  r.count += 1;
  r.bytes += bytes;
  r.max = Math.max(r.max, bytes);
}

// every view schema a message carries, wherever it is: [where, schema] — in
// their places (protocol 3), or once, beside the message (4: `schemas`)
function schemasIn(kind, m) {
  const found = [];
  for (const [id, s] of Object.entries(m.schemas ?? {})) found.push([`schemas:${id.split('@')[0]}`, s]);
  const isTree = (s) => s && typeof s === 'object';
  if (kind === 'view') {
    const v = m.view ?? {};
    for (const [aid, a] of Object.entries(v.actors ?? {})) for (const s of a?.sheets ?? []) if (isTree(s?.schema)) found.push([`sheet:${s.plugin}:${aid}`, s.schema]);
    for (const s of v.status ?? []) if (isTree(s?.schema)) found.push([`status:${s.plugin}`, s.schema]);
    for (const [k, c] of Object.entries(v.cards ?? {})) if (isTree(c?.schema)) found.push([`card:${k}`, c.schema]);
  }
  if (kind === 'dm') {
    const st = m.state ?? {};
    for (const s of st.party_views ?? []) if (isTree(s?.schema)) found.push([`party:${s.plugin}`, s.schema]);
    for (const [k, c] of Object.entries(st.cards ?? {})) if (isTree(c?.schema)) found.push([`card:${k}`, c.schema]);
  }
  return found;
}

const OWN = ['t', 'n', 'base', 'patch', 'schemas'];

// what a view, a scene or the DM's state carries, part by part (a patch's: by
// the parts it changes), and which parts of a whole one were the same as in
// the whole one before (the schemas counted on their own)
function takeApart(name, kind, m) {
  const patch = m.patch && typeof m.patch === 'object' ? m.patch : null;
  let body = patch ? (patch.d ?? {}) : kind === 'view' ? m.view : kind === 'dm' ? m.state : { ...m };
  if (!body || typeof body !== 'object') return;
  if (!patch && kind === 'scene') for (const k of OWN) delete body[k];
  const prev = patch ? undefined : before[name]?.[kind];
  const schemaBytes = schemasIn(kind, m).reduce((s, [, sc]) => s + size(sc), 0);
  const p = ((parts[name] ??= {})[kind] ??= {});
  const add = (part, bytes, same) => {
    const r = (p[part] ??= { bytes: 0, same: 0 });
    r.bytes += bytes;
    if (same) r.same += bytes;
  };
  add('(schemas)', schemaBytes, false);
  for (const [k, v] of Object.entries(body)) {
    let bytes = size(v);
    // a view's schemas are their own part
    if (!patch && kind === 'view' && (k === 'actors' || k === 'status' || k === 'cards')) {
      bytes -= schemasIn('view', { view: { [k]: v } }).reduce((s, [, sc]) => s + size(sc), 0);
    }
    const prevBody = prev === undefined ? undefined : kind === 'view' ? prev.view : kind === 'dm' ? prev.state : prev;
    const same = prevBody !== undefined && JSON.stringify(prevBody?.[k]) === JSON.stringify(v);
    add(k, bytes, same);
  }
  if (!patch) (before[name] ??= {})[kind] = m;
}

async function open(url, viewport, name) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: 1, hasTouch: viewport.width < 600 });
  const page = await ctx.newPage();
  page.on('websocket', (ws) => {
    ws.on('framereceived', (f) => {
      const bytes = Buffer.byteLength(f.payload, typeof f.payload === 'string' ? 'utf8' : undefined);
      let m = null;
      try {
        m = JSON.parse(String(f.payload));
      } catch {
        /* not a message */
      }
      const kind = m && typeof m.t === 'string' ? m.t : '?';
      tally(recv, [name, phase, kind], bytes);
      if (frames && m) appendFileSync(`${out}/frames.jsonl`, JSON.stringify({ page: name, phase, bytes, msg: m }) + '\n');
      if (!m) return;
      if (kind === 'view' || kind === 'scene' || kind === 'dm') {
        takeApart(name, kind, m);
        (lastOf[name] ??= {})[kind] = m;
      }
      for (const [where, sc] of schemasIn(kind, m)) {
        const text = JSON.stringify(sc);
        const key = `${where.split(':').slice(0, 2).join(':')} ${createHash('sha1').update(text).digest('hex')}`;
        const seen = ((schemaSeen[name] ??= {})[key] ??= { where, bytes: Buffer.byteLength(text, 'utf8'), times: 0 });
        seen.times += 1;
      }
    });
    ws.on('framesent', (f) => {
      let kind = '?';
      try {
        kind = JSON.parse(String(f.payload)).t ?? '?';
      } catch {
        /* not a message */
      }
      tally(sentBy, [name, kind], Buffer.byteLength(String(f.payload), 'utf8'));
    });
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
  await page.waitForTimeout(300);
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

// a new phase once the table has gone quiet (what the last step set off counted in it)
async function begin(name) {
  await new Promise((r) => setTimeout(r, 1200));
  phase = name;
  phases.push(name);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');

const turnNow = () => dm.evaluate(() => `${window.hexmap.game.scene.turns?.round}/${window.hexmap.game.scene.turns?.turn}`);
const roundNow = () => dm.evaluate(() => Number(window.hexmap.game.scene.turns?.round ?? 0));
const wrensTurn = async () => (await dm.locator('.fightbar').getByText(/Wren’s turn/).count()) > 0;

// the DM's Next, seen through (a player's turn with an action left asks first: ended anyway)
async function next() {
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

// Ana's attack on her phone: a creature she sees, tapped on the map, said yes to
async function anaAttacks() {
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Combat' }).click();
  await ana.getByRole('button', { name: 'Attack' }).first().click();
  await ana.getByText(/tap a creature on the map/).waitFor({ timeout: 5000 });
  const at = await ana.evaluate(() => {
    const g = window.hexmap.game;
    const t = (g.scene.tokens ?? []).find((x) => !x.owner && /Goblin/.test(x.name ?? ''));
    const c = document.querySelector('canvas');
    return t && c?.screenOf ? { id: t.id, name: t.name, ...c.screenOf(t.id) } : null;
  });
  if (!at) throw new Error('Ana sees no goblin to attack');
  const rolls = await ana.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length);
  await ana.mouse.click(at.x, at.y);
  await ana.getByRole('dialog', { name: 'Confirm the target' }).waitFor({ timeout: 5000 });
  await ana.getByRole('button', { name: 'Do it' }).click();
  await ana.waitForFunction((r) => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll').length > r, rolls, { timeout: 8000 });
}

let ok = await step('the DM’s screen opens; Ana joins on her phone', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await shot(ana, 'ana_joined');
});

await begin('fight starts');
let goblin = null;
ok = ok && (await step('the session and the chapel fight: initiative, the goblins revealed, the party inside, Wren beside a goblin', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click();
  await dm.getByText(/Session 1/).first().waitFor({ timeout: 5000 });
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
    return { at: c.screenOf(gob.id), px: c.pxPerHex(), gob: { id: gob.id, name: gob.name, actor: gob.actor, pos: gob.pos } };
  });
  if (!where) throw new Error('no goblin on the DM’s map');
  goblin = where.gob;
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(600);
  // Wren dragged beside the goblin by the DM
  const drag = await dm.evaluate((gid) => {
    const toks = window.hexmap.game.scene.tokens ?? [];
    const w = toks.find((t) => t.name === 'Wren');
    const c = document.querySelector('canvas');
    if (!w || !c?.screenOf) return null;
    const g = c.screenOf(gid);
    return { id: w.id, pos: w.pos, from: c.screenOf(w.id), to: { x: g.x - c.pxPerHex(), y: g.y } };
  }, goblin.id);
  if (!drag) throw new Error('no Wren on the map');
  await dm.mouse.move(drag.from.x, drag.from.y);
  await dm.mouse.down();
  await dm.mouse.move(drag.from.x + 10, drag.from.y, { steps: 3 });
  await dm.mouse.move(drag.to.x, drag.to.y, { steps: 8 });
  await dm.mouse.up();
  await dm.waitForFunction(
    ([id, pos]) => {
      const t = (window.hexmap.game.scene.tokens ?? []).find((x) => x.id === id);
      return t && (t.pos[0] !== pos[0] || t.pos[1] !== pos[1]);
    },
    [drag.id, drag.pos],
    { timeout: 5000 },
  );
  await shot(dm, 'dm_fight');
}));

await begin('round 1');
ok = ok && (await step('round 1: a goblin’s scimitar at Wren; the turns on to Wren; Ana attacks; on to round 2', async () => {
  await dm.locator('.order .row').filter({ hasText: goblin.name }).first().click();
  await dm.locator('.chosen').waitFor({ timeout: 5000 });
  await dm.locator('.chosen .row').filter({ hasText: /^Scimitar\./ }).first().getByRole('button', { name: 'Use' }).click();
  const banner = dm.getByRole('group', { name: 'Choose the target' });
  await banner.waitFor({ timeout: 5000 });
  await banner.locator('.choice').filter({ hasText: /^Wren/ }).first().click();
  await banner.getByRole('button', { name: 'Done' }).click();
  await banner.waitFor({ state: 'detached', timeout: 5000 });
  await dm.waitForTimeout(800);
  for (let i = 0; i < 14 && !(await wrensTurn()); i++) await next();
  if (!(await wrensTurn())) throw new Error('Wren’s turn never came');
  await anaAttacks();
  await shot(ana, 'ana_attacked');
  for (let i = 0; i < 14 && (await roundNow()) < 2; i++) await next();
}));

await begin('round 2');
ok = ok && (await step('round 2: on to Wren; Ana attacks and says something; on to round 3', async () => {
  for (let i = 0; i < 14 && !(await wrensTurn()); i++) await next();
  if (!(await wrensTurn())) throw new Error('Wren’s turn never came');
  await anaAttacks();
  await ana.getByRole('tab', { name: /Chat/ }).click();
  const box = ana.getByRole('textbox').last();
  await box.fill('Wren ducks behind the font');
  await box.press('Enter');
  await dm.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => e.kind === 'chat' && /behind the font/.test(String(e.text ?? ''))), null, { timeout: 8000 });
  for (let i = 0; i < 14 && (await roundNow()) < 3; i++) await next();
  await shot(dm, 'dm_round_3');
}));

await begin('reconnect');
ok = ok && (await step('Ana’s phone drops its connection and comes back by itself', async () => {
  const seq = await ana.evaluate(() => Number(window.hexmap.game.view.seq ?? 0));
  await ana.evaluate(() => window.hexmap.drop());
  await ana.waitForFunction(() => window.hexmap.game.status !== 'open', null, { timeout: 5000 }).catch(() => {});
  await ana.waitForFunction(() => window.hexmap.game.status === 'open' && window.hexmap.game.joined && !window.hexmap.game.joining, null, { timeout: 15000 });
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Combat' }).click();
  await ana.getByRole('button', { name: 'Attack' }).first().waitFor({ timeout: 8000 });
  if ((await ana.evaluate(() => Number(window.hexmap.game.view.seq ?? 0))) < seq) throw new Error('her view went back');
  await shot(ana, 'ana_back');
}));

await begin('settings');
ok = ok && (await step('the DM sets the sheets to Bookkeeping: Ana’s sheet follows (a By hand tab)', async () => {
  await dm.getByRole('button', { name: /^(Rules|Table) settings/ }).first().click();
  const dialog = dm.getByRole('dialog', { name: /^(Rules|Table) settings$/ });
  await dialog.waitFor({ timeout: 5000 });
  await dialog.getByRole('combobox', { name: 'What the sheets\' buttons do' }).selectOption({ label: 'Bookkeeping: the sheets keep the numbers; players tick slots and uses, mark hit points and set conditions by hand' });
  await dm.waitForTimeout(800);
  await dialog.getByRole('button', { name: 'Done' }).click();
  await dialog.waitFor({ state: 'detached', timeout: 5000 });
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'By hand' }).waitFor({ timeout: 10000 });
  await shot(ana, 'ana_by_hand');
}));
await new Promise((r) => setTimeout(r, 1200));

// ------------------------------------------------------------------ report --
const kb = (b) => (b / 1024).toFixed(1);
const report = { phases, recv, sent: sentBy, parts, schemas: {} };
for (const [name] of pages) {
  console.log(`\n== ${name}: received, by phase (count / KB) ==`);
  const kinds = new Set();
  for (const ph of phases) for (const k of Object.keys(recv[name]?.[ph] ?? {})) kinds.add(k);
  const order = [...kinds].sort();
  console.log(['kind'.padEnd(10), ...phases.map((p) => p.padStart(16)), 'total'.padStart(18), 'max KB'.padStart(9)].join(''));
  const total = { count: 0, bytes: 0 };
  for (const k of order) {
    let c = 0;
    let b = 0;
    let mx = 0;
    const cells = phases.map((ph) => {
      const r = recv[name]?.[ph]?.[k];
      if (!r) return '-'.padStart(16);
      c += r.count;
      b += r.bytes;
      mx = Math.max(mx, r.max);
      return `${r.count} / ${kb(r.bytes)}`.padStart(16);
    });
    total.count += c;
    total.bytes += b;
    console.log([k.padEnd(10), ...cells, `${c} / ${kb(b)}`.padStart(18), kb(mx).padStart(9)].join(''));
  }
  const phaseTotals = phases.map((ph) => {
    const rs = Object.values(recv[name]?.[ph] ?? {});
    return `${rs.reduce((s, r) => s + r.count, 0)} / ${kb(rs.reduce((s, r) => s + r.bytes, 0))}`.padStart(16);
  });
  console.log(['all'.padEnd(10), ...phaseTotals, `${total.count} / ${kb(total.bytes)}`.padStart(18)].join(''));
  for (const kind of ['view', 'scene', 'dm']) {
    const p = parts[name]?.[kind];
    if (!p) continue;
    const all = Object.values(p).reduce((s, r) => s + r.bytes, 0);
    const same = Object.values(p).reduce((s, r) => s + r.same, 0);
    console.log(`\n  ${kind}: ${kb(all)} KB in all; ${kb(same)} KB (${((100 * same) / Math.max(all, 1)).toFixed(0)}%) the same as in the ${kind} before. By part (KB, the same as before):`);
    for (const [part, r] of Object.entries(p).sort((a, b) => b[1].bytes - a[1].bytes).slice(0, 14)) console.log(`    ${part.padEnd(16)}${kb(r.bytes).padStart(10)}${kb(r.same).padStart(10)}`);
  }
  const seen = Object.values(schemaSeen[name] ?? {});
  report.schemas[name] = seen.map((s) => ({ where: s.where, bytes: s.bytes, times: s.times }));
  const again = seen.filter((s) => s.times > 1);
  const wasted = again.reduce((s, x) => s + x.bytes * (x.times - 1), 0);
  console.log(`\n  schemas: ${seen.length} different ones received (${kb(seen.reduce((s, x) => s + x.bytes, 0))} KB once each); ${again.length} of them again unchanged, ${kb(wasted)} KB repeated`);
  if (budget) {
    if (again.length) problems.push(`${name}: ${again.length} schema(s) received again unchanged (${again.slice(0, 3).map((x) => `${x.where} ×${x.times}`).join(', ')})`);
    const views = phases.flatMap((ph) => (recv[name]?.[ph]?.view ? [recv[name][ph].view] : []));
    const count = views.reduce((s, r) => s + r.count, 0);
    const bytes = views.reduce((s, r) => s + r.bytes, 0);
    const first = recv[name]?.join?.view?.max ?? 0;
    if (name !== 'dm' && count > 1 && (bytes - first) / (count - 1) > VIEW_BUDGET) problems.push(`${name}: views average ${kb((bytes - first) / (count - 1))} KB after the first`);
  }
}
writeFileSync(`${out}/traffic.json`, JSON.stringify(report, null, 1));
// the last of each kind each page had, to look into
for (const [name, kinds] of Object.entries(lastOf)) for (const [kind, m] of Object.entries(kinds)) writeFileSync(`${out}/last_${name}_${kind}.json`, JSON.stringify(m));

for (const [, p] of pages) await p.context().close();
await browser.close();
if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(`  - ${p}`);
  process.exit(1);
}
console.log(`\nevery step went; ${n} screenshots and traffic.json in ${out}`);
