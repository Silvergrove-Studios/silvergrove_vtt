// One seat at the table: a Chrome page kept open for one person (a player
// or the DM), sized like their device, that the agent playing them drives
// through table-mcp.mjs. It runs the scripts posted to it (the body of an
// async function, with `page` and a few helpers) and keeps screenshots in
// <dir>/shots. Only on 127.0.0.1.
//
//   node seat.mjs --port 9301 --url <url> --size 390x844 [--touch] [--ua iphone|android|windows|mac] --dir <folder>
//       [--timelapse <seconds>]   a picture of the screen that often, in <folder>/timelapse
//
// <folder>/log/page.jsonl is what happened in the page: every script run on it
// (and its answer), console messages, page errors, dialogs, navigations,
// failed requests, the table's socket opening and closing.
import { chromium } from '../../web/node_modules/playwright-core/index.mjs';
import http from 'node:http';
import { appendFileSync, mkdirSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const arg = (k, d) => {
  const i = process.argv.indexOf(k);
  return i > 0 ? process.argv[i + 1] : d;
};
const port = Number(arg('--port', '9301'));
const url = arg('--url');
const [w, h] = arg('--size', '1280x800').split('x').map(Number);
const touch = process.argv.includes('--touch');
const dir = resolve(arg('--dir', '.'));
const UAS = {
  iphone: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1',
  android: 'Mozilla/5.0 (Linux; Android 15; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  windows: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  mac: undefined,
};
mkdirSync(`${dir}/shots`, { recursive: true });
mkdirSync(`${dir}/log`, { recursive: true });
const note = (kind, data = {}) => appendFileSync(`${dir}/log/page.jsonl`, JSON.stringify({ at: new Date().toISOString(), kind, ...data }) + '\n');
const cut = (v, n = 4000) => {
  const s = typeof v === 'string' ? v : JSON.stringify(v);
  return s && s.length > n ? s.slice(0, n) + `… (${s.length} characters)` : s;
};

const browser = await chromium.launch({ channel: 'chrome', headless: true });
const context = await browser.newContext({
  viewport: { width: w, height: h },
  deviceScaleFactor: 1,
  hasTouch: touch,
  isMobile: touch && w < 600,
  userAgent: UAS[arg('--ua', 'mac')],
});
const events = [];
let page;
async function openPage() {
  page = await context.newPage();
  page.setDefaultTimeout(10000);
  page.on('pageerror', (e) => {
    events.push(`page error: ${e.message}`);
    note('pageerror', { message: e.message, stack: cut(e.stack ?? '', 2000) });
  });
  page.on('console', (m) => {
    if (m.type() === 'error') events.push(`console error: ${m.text()}`);
    note('console', { type: m.type(), text: cut(m.text(), 2000) });
  });
  // a box that asks for text gets the answer set with answer(), or what it
  // already holds (a run's browsers answered every question with nothing, and
  // "Name the new folder" made no folder)
  page.on('dialog', async (d) => {
    const typed = d.type() === 'prompt' ? (nextAnswer ?? d.defaultValue()) : undefined;
    nextAnswer = null;
    events.push(`a ${d.type()} box said: "${d.message()}" (answered OK${typed !== undefined ? `, with "${typed}"` : ''})`);
    note('dialog', { type: d.type(), message: d.message(), answer: typed ?? null });
    await d.accept(typed).catch(() => {});
  });
  page.on('framenavigated', (f) => {
    if (f === page.mainFrame()) note('navigated', { url: f.url() });
  });
  page.on('requestfailed', (r) => note('requestfailed', { url: r.url(), failure: r.failure()?.errorText ?? '' }));
  page.on('response', (r) => {
    if (r.status() >= 400) note('http', { url: r.url(), status: r.status() });
  });
  page.on('websocket', (ws) => {
    note('socket', { url: ws.url(), state: 'open' });
    ws.on('close', () => note('socket', { url: ws.url(), state: 'closed' }));
    ws.on('socketerror', (e) => note('socket', { url: ws.url(), state: 'error', error: String(e) }));
  });
  await page.goto(url);
  return page;
}
await openPage();

let n = readdirSync(`${dir}/shots`).filter((f) => f.endsWith('.png')).length;
const slug = (s) => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 50) || 'screen';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let nextAnswer = null;

const helpers = {
  sleep,
  async shot(label = 'screen', { full = false, selector } = {}) {
    n += 1;
    const path = `${dir}/shots/${String(n).padStart(3, '0')}_${slug(label)}.png`;
    await sleep(300);
    if (selector) await page.locator(selector).first().screenshot({ path });
    else await page.screenshot({ path, fullPage: full });
    return path;
  },
  async look(selector = 'body') {
    return page.locator(selector).first().ariaSnapshot();
  },
  async text(selector = 'body') {
    return page.locator(selector).first().innerText();
  },
  async waitForText(t, ms = 60000) {
    try {
      await page.getByText(t).first().waitFor({ timeout: ms });
      return true;
    } catch {
      return false;
    }
  },
  async changed(selector = 'body', ms = 60000) {
    const read = () => page.locator(selector).first().innerText().catch(() => '');
    const before = await read();
    const end = Date.now() + ms;
    while (Date.now() < end) {
      await sleep(700);
      const now = await read();
      if (now !== before) {
        const had = new Set(before.split('\n'));
        return { changed: true, new_lines: now.split('\n').filter((l) => l.trim() && !had.has(l)) };
      }
    }
    return { changed: false };
  },
  async choose(locator, file) {
    const [fc] = await Promise.all([page.waitForEvent('filechooser', { timeout: 8000 }), locator.click()]);
    await fc.setFiles(resolve(dir, file));
    return `picked ${file}`;
  },
  answer(t) {
    nextAnswer = String(t);
    return `the next box that asks for text will get "${nextAnswer}"`;
  },
  async reopen() {
    await page.close().catch(() => {});
    return openPage();
  },
};

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
http
  .createServer(async (req, res) => {
    let body = '';
    for await (const c of req) body += c;
    const limit = Math.min(Number(req.headers['x-max-ms'] ?? 120000), 540000);
    let out;
    const started = Date.now();
    try {
      const fn = new AsyncFunction('page', 'context', ...Object.keys(helpers), body);
      let timer;
      const result = await Promise.race([
        fn(page, context, ...Object.values(helpers)),
        new Promise((_, rej) => (timer = setTimeout(() => rej(new Error(`stopped after ${limit / 1000} s`)), limit))),
      ]);
      clearTimeout(timer);
      out = { ok: true, result: result === undefined ? null : result };
    } catch (e) {
      out = { ok: false, error: String(e?.message ?? e).split('\n').slice(0, 14).join('\n') };
    }
    out.events = events.splice(0);
    note('run', { code: cut(body), ms: Date.now() - started, ok: out.ok, result: out.ok ? cut(out.result) : undefined, error: out.error, events: out.events });
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(out));
  })
  .listen(port, '127.0.0.1', () => console.log(`seat ready on ${port}: ${url}`));

// a timelapse: the screen every so often, whatever the agent is doing
const every = Number(arg('--timelapse', '0'));
if (every > 0) {
  mkdirSync(`${dir}/timelapse`, { recursive: true });
  setInterval(() => {
    const t = new Date().toTimeString().slice(0, 8).replace(/:/g, '');
    page?.screenshot({ path: `${dir}/timelapse/${t}.jpg`, type: 'jpeg', quality: 60 }).catch(() => {});
  }, every * 1000);
}
note('started', { url, size: `${w}x${h}`, touch });

for (const s of ['SIGINT', 'SIGTERM']) process.on(s, async () => {
  await browser.close().catch(() => {});
  process.exit(0);
});
