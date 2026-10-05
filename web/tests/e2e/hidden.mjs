// What the players know, in a real browser against a real table: the DM keeps
// monsters' names and conditions from the players (Rules settings). In the
// chapel fight one goblin is shown: on Ana's phone and Ben's laptop it is "a
// creature", labelled "?", and its scimitar at Wren is a creature's; a second
// is shown, the two are 1 and 2, and Ana's Fireball preview is "2 creatures"
// on Ben's screen; the DM seeing as Ana sees her screen's names and marks; the
// DM reveals the first goblin's name and both players' screens name it — its
// token, and the line said before; a Frightened put on the other goblin is the
// DM's alone. Screenshots of each step.
//
//   node tests/e2e/hidden.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes, hosting a package on srd5e with
// --party (Ana's Wren, a halfling rogue; Ben's Brakka).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/hidden.mjs <host.json> <out dir>');
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
  console.log(`\nthe monsters' names and conditions stayed the DM's until the DM said; ${n} screenshots in ${out}`);
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');

/** A token as a page's scene holds it. */
const tokenOn = (page, id) => page.evaluate((tid) => (window.hexmap.game.scene.tokens ?? []).find((t) => t.id === tid) ?? null, id);
/** Where a token is on a page's map (client pixels). */
const screenOf = (page, id) =>
  page.evaluate((tid) => {
    const c = document.querySelector('canvas');
    return c?.screenOf ? c.screenOf(tid) : null;
  }, id);
/** What a page was told of the creatures on the table, as text: its scene's
 *  tokens, its log, the cards and what the table waits on, the marks, the
 *  creatures in its view (not a character's own words: a halfling's Brave
 *  speaks of the Frightened condition, and a sheet's languages of Goblin). */
const told = (page) =>
  page.evaluate(() => {
    const g = window.hexmap.game;
    const actors = Object.values(g.view.actors ?? {}).map((a) => ({ name: a.name, effects: a.effects, tokens: a.tokens }));
    return JSON.stringify({ tokens: g.scene.tokens, log: g.view.log, prompts: g.view.prompts, waiting: g.view.waiting, rolls: g.view.rolls, actors, marks: g.marks, preview: g.preview, previewMarks: g.previewMarks });
  });
/** The words of a page's list of marks (opened from the map's tools, closed again). */
async function marksList(page) {
  await page.getByRole('button', { name: /^Marks on the map/ }).click();
  const list = page.getByRole('region', { name: 'Marks on the map' });
  await list.waitFor({ timeout: 4000 });
  const words = await list.innerText();
  return { words, close: () => list.getByRole('button', { name: 'Close' }).click() };
}

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

let ok = await step('the DM’s screen opens; Ana (a phone) and Ben (a laptop) join', async () => {
  await dm.getByText('Invite players').first().waitFor({ timeout: 10000 });
  await ana.getByRole('button', { name: 'Ana' }).click({ timeout: 10000 });
  await ana.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).first().waitFor({ timeout: 10000 });
});

ok = ok && (await step('the DM keeps monsters’ names and conditions from the players, and gives Wren Fireball', async () => {
  await setRule('Whether players know a monster\'s name', 'Hidden: "a creature" until the DM reveals it');
  await setRule('Whether players see a monster\'s conditions', 'Hidden: the DM describes it');
  await dm.locator('.book').getByRole('button', { name: /^Wren/ }).first().click();
  await dm.getByRole('tab', { name: 'Spells' }).first().click();
  const give = dm.locator('.picker').filter({ hasText: 'Give a spell (any list, any level)' });
  await give.locator('input[type=search]').fill('fireball');
  await give.getByRole('button', { name: 'Give Fireball' }).click({ timeout: 8000 });
  await dm.locator('.row').filter({ hasText: /Fireball \(/ }).first().waitFor({ timeout: 8000 });
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
}));

let first = null; // the goblin the players see first
let second = null; // the one shown after it
ok = ok && (await step('the chapel fight: one goblin shown — on the players’ screens “a creature”, labelled “?”', async () => {
  await dm.getByRole('button', { name: /Start session/ }).first().click().catch(() => {});
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.locator('.fightbar').waitFor({ timeout: 8000 });
  await dm.locator('.reader').waitFor({ state: 'detached', timeout: 5000 });
  await dm.getByRole('button', { name: 'Roll initiative' }).click();
  await dm.getByText('Turn order').waitFor({ timeout: 8000 });
  // two goblins near each other, hidden for now
  const pair = await dm.evaluate(() => {
    const toks = (window.hexmap.game.scene.tokens ?? []).filter((t) => /^Goblin/.test(t.name ?? '') && !/Boss/.test(t.name ?? '') && t.actor);
    let best = null;
    for (const a of toks)
      for (const b of toks) {
        if (a === b) continue;
        const d = Math.hypot(a.pos[0] - b.pos[0], a.pos[1] - b.pos[1]);
        if (!best || d < best.d) best = { d, a, b };
      }
    return best ? { a: { id: best.a.id, name: best.a.name, actor: best.a.actor }, b: { id: best.b.id, name: best.b.name, actor: best.b.actor } } : null;
  });
  expect(pair, 'no two goblins on the DM’s map');
  first = pair.a;
  second = pair.b;
  // the DM shows the first: its row in the order, Reveal
  await dm.locator(`.fightpanel .order [data-token="${first.id}"]`).click();
  await dm.locator('.fightpanel .chosen').getByRole('button', { name: 'Reveal', exact: true }).click();
  await dm.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id && !t.hidden), first.id, { timeout: 5000 });
  // the party just west of it, Wren beside it
  const where = await dm.evaluate((id) => {
    const c = document.querySelector('canvas');
    return c?.screenOf ? { at: c.screenOf(id), px: c.pxPerHex() } : null;
  }, first.id);
  await dm.locator('.mapbar').getByRole('button', { name: 'Move the party here' }).click();
  await dm.getByText('Move the party here: tap where they are').waitFor({ timeout: 5000 });
  await dm.mouse.click(where.at.x - where.px * 3, where.at.y);
  await dm.waitForTimeout(800);
  await ana.getByRole('tab', { name: /Map/ }).click();
  await ana.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id), first.id, { timeout: 8000 });
  const seen = await tokenOn(ana, first.id);
  expect(seen.name === 'a creature' && seen.label === '?', `Ana's screen: ${JSON.stringify({ name: seen.name, label: seen.label })}`);
  const onBen = await tokenOn(ben, first.id);
  expect(onBen && onBen.name === 'a creature' && onBen.label === '?', `Ben's screen: ${JSON.stringify(onBen && { name: onBen.name, label: onBen.label })}`);
  const dmTok = await tokenOn(dm, first.id);
  expect(dmTok.name === first.name && dmTok.name_known === false && dmTok.player_label === '?', `the DM's: ${JSON.stringify({ name: dmTok.name, known: dmTok.name_known, label: dmTok.player_label })}`);
  // the DM's stat block says what the players call it, with Reveal its name
  await dm.locator('.fightpanel .chosen').getByText('To the players: a creature').waitFor({ timeout: 5000 });
  expect(!(await told(ana)).includes(first.name.split(' ')[0]), 'something Ana was told names the goblin');
  await shot(ana, 'ana_a_creature');
  await shot(dm, 'dm_its_name_kept');
}));

ok = ok && (await step('a creature attacks Wren: the players’ chat says a creature, the DM’s the goblin', async () => {
  // Wren beside the goblin
  const w = await dm.evaluate(() => (window.hexmap.game.scene.tokens ?? []).find((t) => t.name === 'Wren') ?? null);
  expect(w, 'no Wren on the map');
  const drag = await dm.evaluate(
    ([wid, gid]) => {
      const c = document.querySelector('canvas');
      const px = c.pxPerHex();
      const from = c.screenOf(wid);
      const g = c.screenOf(gid);
      return { from, to: { x: g.x - px, y: g.y } };
    },
    [w.id, first.id],
  );
  await dm.mouse.move(drag.from.x, drag.from.y);
  await dm.mouse.down();
  await dm.mouse.move(drag.from.x + 10, drag.from.y, { steps: 3 });
  await dm.mouse.move(drag.to.x, drag.to.y, { steps: 8 });
  await dm.mouse.up();
  await dm.waitForTimeout(600);
  // its scimitar at Wren, from its stat block
  await dm.locator(`.fightpanel .order [data-token="${first.id}"]`).click();
  await dm.locator('.fightpanel .chosen .row').filter({ hasText: /^Scimitar\./ }).first().getByRole('button', { name: 'Use' }).click();
  const banner = dm.getByRole('group', { name: 'Choose the target' });
  await banner.waitFor({ timeout: 5000 });
  await banner.locator('.choice').filter({ hasText: /^Wren/ }).first().click();
  await banner.getByRole('button', { name: 'Done' }).click();
  // the roll on every screen: Ana's says a creature at Wren
  const rollOf = (page) =>
    page.evaluate(() => (window.hexmap.game.view.log ?? []).filter((e) => e.kind === 'roll' && /^Scimitar/.test(e.label ?? '')).map((e) => ({ who: e.who, whom: e.whom })).pop() ?? null);
  await ana.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => e.kind === 'roll' && /^Scimitar/.test(e.label ?? '')), null, { timeout: 8000 });
  const anaRoll = await rollOf(ana);
  expect(anaRoll.who === 'A creature' && anaRoll.whom === 'Wren', `Ana's: ${JSON.stringify(anaRoll)}`);
  await ben.waitForFunction(() => (window.hexmap.game.view.log ?? []).some((e) => e.kind === 'roll' && /^Scimitar/.test(e.label ?? '')), null, { timeout: 8000 });
  const benRoll = await rollOf(ben);
  expect(benRoll.who === 'A creature' && benRoll.whom === 'Wren', `Ben's: ${JSON.stringify(benRoll)}`);
  const dmRoll = await rollOf(dm);
  expect(dmRoll.who === first.name && dmRoll.whom === 'Wren', `the DM's: ${JSON.stringify(dmRoll)}`);
  // and on her phone, in the chat, in words
  await ana.getByRole('tab', { name: /Chat/ }).click();
  await ana.getByText('A creature').first().waitFor({ timeout: 5000 });
  await ana.getByText(/Scimitar → Wren/).first().waitFor({ timeout: 5000 });
  expect(!(await told(ana)).includes(first.name.split(' ')[0]), 'something Ana was told names the goblin');
  await shot(ana, 'ana_a_creature_attacks_wren');
  await ana.getByRole('tab', { name: /Map/ }).click();
}));

ok = ok && (await step('a second goblin shown: 1 and 2; Ana previews Fireball, and Ben’s screen says 2 creatures', async () => {
  await dm.locator(`.fightpanel .order [data-token="${second.id}"]`).click();
  await dm.locator('.fightpanel .chosen').getByRole('button', { name: 'Reveal', exact: true }).click();
  await ana.waitForFunction((id) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id), second.id, { timeout: 8000 });
  const a1 = await tokenOn(ana, first.id);
  const a2 = await tokenOn(ana, second.id);
  expect(a1.name === 'a creature' && a2.name === 'a creature' && [a1.label, a2.label].sort().join(',') === '1,2', `Ana's: ${JSON.stringify([a1.label, a2.label])}`);
  // Fireball's preview from her Spells tab, put on the first goblin
  await ana.getByRole('tab', { name: /Character/ }).click();
  await ana.getByRole('tab', { name: 'Spells' }).click();
  await ana.locator('.row').filter({ hasText: /Fireball \(/ }).first().getByRole('button', { name: 'Preview' }).click();
  const banner = ana.getByRole('group', { name: 'Preview' });
  await banner.getByText('Fireball, 20-ft sphere: tap where it goes').waitFor({ timeout: 5000 });
  const at = await screenOf(ana, first.id);
  expect(at, 'the goblin isn’t on Ana’s map');
  await ana.mouse.click(at.x, at.y);
  await banner.getByText(/2 creatures/).waitFor({ timeout: 5000 });
  const words = await banner.innerText();
  expect(!/Goblin/.test(words), `Ana's preview names a goblin: ${words}`);
  await shot(ana, 'ana_fireball_2_creatures');
  await banner.getByRole('button', { name: 'Pin' }).click();
  await banner.getByRole('button', { name: 'Done' }).click();
  await ben.waitForFunction(() => Object.values(window.hexmap.game.marks ?? {}).some((m) => m.kind === 'preview' && m.label === 'Fireball, 20-ft sphere'), null, { timeout: 6000 });
  const list = await marksList(ben);
  expect(list.words.includes('2 creatures') && !/Goblin/.test(list.words), `Ben's list: ${list.words}`);
  await shot(ben, 'ben_preview_2_creatures');
  await list.close();
}));

ok = ok && (await step('the DM sees as Ana: her screen’s names and her marks', async () => {
  await dm.locator('.seeas select').selectOption({ label: 'Ana' });
  await dm.waitForFunction(() => !!window.hexmap.game.preview && window.hexmap.game.previewMarks !== null, null, { timeout: 6000 });
  const seen = await dm.evaluate((id) => (window.hexmap.game.preview.tokens ?? []).find((t) => t.id === id) ?? null, second.id);
  expect(seen && seen.name === 'a creature', `the DM's See as Ana: ${JSON.stringify(seen && seen.name)}`);
  const marks = await dm.evaluate(() => Object.values(window.hexmap.game.previewMarks ?? {}).map((m) => m.label));
  expect(marks.includes('Fireball, 20-ft sphere'), `her marks: ${JSON.stringify(marks)}`);
  await shot(dm, 'dm_sees_as_ana');
  await dm.locator('.seeas select').selectOption({ value: '' });
  await dm.waitForFunction(() => !window.hexmap.game.preview, null, { timeout: 6000 });
}));

ok = ok && (await step('the DM reveals the first goblin’s name: both players’ screens name it, and the line said before', async () => {
  await dm.locator(`.fightpanel .order [data-token="${first.id}"]`).click();
  await dm.locator('.fightpanel .chosen').getByRole('button', { name: 'Reveal its name' }).click();
  await dm.locator('.fightpanel .chosen').getByText('The players know its name').waitFor({ timeout: 5000 });
  for (const page of [ana, ben]) {
    await page.waitForFunction(([id, nm]) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.id === id && t.name === nm), [first.id, first.name], { timeout: 8000 });
    const two = await tokenOn(page, second.id);
    expect(two.name === 'a creature' && two.label === '?', `the other goblin, still: ${JSON.stringify({ name: two.name, label: two.label })}`);
    await page.waitForFunction((nm) => (window.hexmap.game.view.log ?? []).some((e) => e.kind === 'roll' && e.who === nm && /^Scimitar/.test(e.label ?? '')), first.name, { timeout: 8000 });
  }
  // (both are "Goblin Warrior": what Ana holds of the other one — its token,
  // its creature, its rolls — names it nowhere)
  const leak = await ana.evaluate(([tid, aid]) => {
    const g = window.hexmap.game;
    const tok = (g.scene.tokens ?? []).find((t) => t.id === tid);
    const rolls = (g.view.log ?? []).filter((e) => e.actor === aid).map((e) => `${e.who ?? ''} ${e.label ?? ''} ${e.text ?? ''}`);
    return [tok?.name, (g.view.actors ?? {})[aid]?.name, ...rolls].filter((w) => w && /Goblin/.test(w));
  }, [second.id, second.actor]);
  expect(leak.length === 0, `Ana was told the other goblin’s name: ${leak.join(' | ')}`);
  await shot(ana, 'ana_the_goblin_named');
}));

ok = ok && (await step('a Frightened goblin: the DM’s alone — not on the players’ screens', async () => {
  await dm.locator(`.fightpanel .order [data-token="${second.id}"]`).click();
  const block = dm.locator('.fightpanel .chosen');
  await block.getByRole('combobox', { name: 'Add a condition' }).selectOption({ label: 'Frightened' });
  await block.getByRole('button', { name: 'Add', exact: true }).click();
  await dm.waitForFunction((aid) => ((window.hexmap.game.view.actors ?? {})[aid]?.effects ?? []).some((fx) => fx.key === 'frightened'), second.actor, { timeout: 8000 });
  await dm.waitForTimeout(1200);
  for (const page of [ana, ben]) {
    const t = await told(page);
    expect(!/Frightened|frightened/.test(t), `a player was told of its Frightened: ${t.slice(Math.max(0, t.search(/[Ff]rightened/) - 160), t.search(/[Ff]rightened/) + 40)}`);
  }
  await shot(dm, 'dm_goblin_frightened');
}));

await finish();
