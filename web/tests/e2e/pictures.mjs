// Pictures from the people at the table, in a real browser against a real
// table (the team, after the character maker): a player's picture for her
// character's token, placed in the round window, kept by the table, shown
// on her sheet and to the DM, and on the fight's map; a picture in her
// journal, shared with another player who sees it; a picture in the DM's
// own notes. Screenshots of each step.
//
//   node tests/e2e/pictures.mjs <host.json> <out dir>
//
// host.json is what tools/web_host.gd writes (started with --party).
import { chromium } from 'playwright-core';
import { mkdirSync, readFileSync } from 'node:fs';

const [infoPath, out] = process.argv.slice(2);
if (!infoPath || !out) {
  console.error('usage: node tests/e2e/pictures.mjs <host.json> <out dir>');
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

function expect(cond, what) {
  if (!cond) throw new Error(what);
}

/** A picture drawn in the page: a PNG file's bytes, `w` × `h`, a face-ish disc on a field. */
async function drawn(page, w, h, hue) {
  const b64 = await page.evaluate(
    ([w, h, hue]) => {
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      const g = c.getContext('2d');
      g.fillStyle = `hsl(${hue} 55% 35%)`;
      g.fillRect(0, 0, w, h);
      g.fillStyle = `hsl(${(hue + 180) % 360} 70% 70%)`;
      g.beginPath();
      g.arc(w / 2, h / 2, Math.min(w, h) / 3, 0, Math.PI * 2);
      g.fill();
      g.fillStyle = '#111';
      g.fillRect(w / 2 - 40, h / 2 - 30, 20, 20);
      g.fillRect(w / 2 + 20, h / 2 - 30, 20, 20);
      return c.toDataURL('image/png').split(',')[1];
    },
    [w, h, hue],
  );
  return { name: 'picture.png', mimeType: 'image/png', buffer: Buffer.from(b64, 'base64') };
}

/** Does an <img> on the page show (loaded, with pixels)? */
async function shows(locator) {
  await locator.first().waitFor({ timeout: 8000 });
  return locator.first().evaluate((img) => new Promise((resolve) => (img.complete ? resolve(img.naturalWidth > 0) : ((img.onload = () => resolve(img.naturalWidth > 0)), (img.onerror = () => resolve(false))))));
}

const dm = await open(info.dm, { width: 1440, height: 900 }, 'dm');
const ana = await open(info.player, { width: 390, height: 844 }, 'ana');
const ben = await open(info.player, { width: 1280, height: 800 }, 'ben');
let tokenRef = '';

await step('Ana and Ben join', async () => {
  await ana.locator('#name').fill('Ana');
  await ana.getByRole('button', { name: 'Join' }).click();
  await ana.getByText('Free movement').waitFor({ timeout: 10000 });
  await ben.getByRole('button', { name: 'Ben' }).click({ timeout: 10000 });
  await ben.getByRole('tab', { name: /Character/ }).waitFor({ timeout: 10000 });
});

await step('Ana gives Wren a picture: placed in the round window, kept by the table', async () => {
  await ana.getByRole('tab', { name: /Character/ }).first().click();
  await ana.getByText('Initials on the map, or a picture of your own.').waitFor({ timeout: 8000 });
  await shot(ana, 'ana_token_initials');
  await ana.locator('input[type=file][aria-label="A picture for the token"]').setInputFiles(await drawn(ana, 900, 600, 200));
  await ana.getByText('The circle is what the token shows.').waitFor({ timeout: 8000 });
  // she moves it a little and comes closer
  const view = ana.getByRole('application', { name: 'The picture: drag to move it' });
  const box = await view.boundingBox();
  await ana.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await ana.mouse.down();
  await ana.mouse.move(box.x + box.width / 2 + 30, box.y + box.height / 2, { steps: 5 });
  await ana.mouse.up();
  await ana.getByRole('slider', { name: 'How close' }).fill('1.4');
  await shot(ana, 'ana_crop');
  await ana.getByRole('button', { name: 'Use this picture' }).click();
  await ana.getByText('Your picture, on the map.').waitFor({ timeout: 15000 });
  tokenRef = await ana.evaluate(() => {
    const g = window.hexmap.game;
    const wren = Object.values(g.view.actors ?? {}).find((a) => a.mine);
    return String(wren?.token?.art ?? '');
  });
  expect(/^upload:[0-9a-f]{32}$/.test(tokenRef), `Wren's token says the picture: ${tokenRef}`);
  expect(await shows(ana.locator('.token-picture .disc img')), 'and her sheet shows it');
  const res = await ana.evaluate(async (ref) => {
    const r = await fetch(`/upload/${ref.slice(7)}.webp`);
    return { status: r.status, type: r.headers.get('content-type') };
  }, tokenRef);
  expect(res.status === 200 && res.type === 'image/webp', `served as WebP: ${JSON.stringify(res)}`);
  await shot(ana, 'ana_token_picture');
});

await step('the DM sees it on Wren’s card; the fight’s map puts it on her token', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Wren/ }).first().click();
  expect(await shows(dm.locator('.token-picture .disc img')), 'the DM’s card shows Wren’s picture');
  await shot(dm, 'dm_wren_card');
  await dm.getByRole('button', { name: 'Close the card' }).click();
  await dm.locator('.book').getByRole('button', { name: /^The ruined chapel/ }).first().click();
  await dm.getByRole('button', { name: 'Start the fight' }).click();
  await dm.waitForFunction(
    (ref) => (window.hexmap.game.scene.tokens ?? []).some((t) => t.art === ref),
    tokenRef,
    { timeout: 10000 },
  );
  await dm.getByRole('button', { name: 'Close the card' }).click().catch(() => {});
  await shot(dm, 'dm_fight_with_picture');
  await ana.getByRole('tab', { name: /Map/ }).first().click();
  await ana.waitForTimeout(800);
  await shot(ana, 'ana_map_with_picture');
});

await step('a picture in Ana’s journal, shared with Ben: he sees it too', async () => {
  await ana.getByRole('tab', { name: /Journal/ }).first().click();
  await ana.getByRole('button', { name: 'New note' }).click();
  await ana.locator('#note-title:visible').fill('The chapel door');
  const noteBox = ana.locator('textarea[placeholder="Your note"]:visible');
  await noteBox.fill('The runes on the door.');
  await ana.locator('input[type=file][aria-label="Add a picture"]').first().setInputFiles(await drawn(ana, 1200, 800, 30));
  await ana.getByText('How it reads').waitFor({ timeout: 15000 });
  const text = await noteBox.inputValue();
  expect(/!\[\]\(upload:[0-9a-f]{32}\)/.test(text), `the picture in the note's text: ${text}`);
  expect(await shows(ana.locator('.preview img.md-picture')), 'and in how it reads');
  await ana.getByLabel('Ben').check();
  await ana.waitForTimeout(800);
  await shot(ana, 'ana_journal_picture');
  await ben.getByRole('tab', { name: /Journal/ }).first().click().catch(() => {});
  await ben.getByRole('button', { name: /The chapel door/ }).first().click({ timeout: 10000 });
  expect(await shows(ben.locator('img.md-picture')), 'Ben reads it, the picture too');
  await shot(ben, 'ben_reads_it');
});

await step('a picture in the DM’s own notes on a place', async () => {
  await dm.locator('.book').getByRole('button', { name: /^Brother Aldous's hut/ }).first().click();
  await dm.getByRole('button', { name: /Write some|Edit/ }).first().click();
  await dm.locator('.yours textarea').fill('He keeps a sketch of the Warden.');
  await dm.locator('.yours input[type=file]').setInputFiles(await drawn(dm, 800, 800, 280));
  await dm.waitForFunction(() => /upload:[0-9a-f]{32}/.test(document.querySelector('.yours textarea')?.value ?? ''), null, { timeout: 15000 });
  await dm.locator('.yours').getByRole('button', { name: 'Done' }).click();
  expect(await shows(dm.locator('.yours img.md-picture')), 'his notes show the picture');
  await shot(dm, 'dm_notes_picture');
});

for (const [, p] of pages) await p.context().close();
await browser.close();
if (problems.length) {
  console.log('\nproblems:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(`\nthe pictures went through; ${n} screenshots in ${out}`);
