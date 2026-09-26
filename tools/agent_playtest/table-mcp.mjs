// The browser as tools (MCP over stdio) for one person at the table: the
// seat (seat.mjs) keeps their page open; these tools act on it. No shell in
// between, so nothing an agent writes is refused for how it looks.
//
//   node table-mcp.mjs <seat port> [<the person's folder>]
//
// With the folder, every call goes into <folder>/log/tools.jsonl: when, which
// tool, what it was asked, how long it took, and what it answered.
import { appendFileSync, mkdirSync, readFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

const port = Number(process.argv[2]);
const folder = process.argv[3] ?? '';
if (folder) mkdirSync(`${folder}/log`, { recursive: true });
function record(entry) {
  if (!folder) return;
  try {
    appendFileSync(`${folder}/log/tools.jsonl`, JSON.stringify({ at: new Date().toISOString(), ...entry }) + '\n');
  } catch {
    /* a log that can't be written stops nothing */
  }
}
const clock = () => new Date().toTimeString().slice(0, 5);

async function seat(code, maxMs = 100000) {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/`, { method: 'POST', body: code, headers: { 'x-max-ms': String(maxMs) } });
    return await res.json();
  } catch (e) {
    return { ok: false, error: `your browser is not answering (${e.message})`, events: [] };
  }
}

const show = (v) => (typeof v === 'string' ? v : JSON.stringify(v, null, 2));
function textOf(r, max = 8000) {
  let t = r.ok ? show(r.result) : `ERROR: ${r.error}`;
  if (t.length > max) t = t.slice(0, max) + `\n… (${t.length - max} more characters: look at a smaller part of the page)`;
  if (r.events?.length) t += '\n\n[the page also said]\n' + r.events.map((e) => '  ' + e).join('\n');
  return `(${clock()})\n${t}`;
}

const TOOLS = [
  {
    name: 'act',
    description:
      "Do something in your browser, the way a person would, with a few lines of Playwright script. `page` is your page: page.getByRole('button', { name: 'Join' }).click(), page.getByLabel(...).fill(...), page.getByText(...), page.keyboard.press('Enter'), and so on. Helpers: look(selector?) the accessibility tree; text(selector?) the visible text; shot(label) saves a screenshot and returns its path; changed(selector?, ms?) waits for that part of the page to change; waitForText(text, ms?); sleep(ms); choose(locator, 'photos/<file>') clicks a button that opens a file picker and picks that file; answer('text') types that into the next box that pops up asking for text (call it before the click that opens it). `return` what you want to see. Keep it under 90 seconds.",
    inputSchema: { type: 'object', properties: { script: { type: 'string', description: 'The lines of script (the body of an async function).' } }, required: ['script'] },
    run: async (a) => ({ content: [{ type: 'text', text: textOf(await seat(String(a.script ?? ''))) }] }),
  },
  {
    name: 'screenshot',
    description: 'See your screen: takes a screenshot (the whole screen, the whole page, or one part of it), keeps it in shots/ and shows it to you.',
    inputSchema: {
      type: 'object',
      properties: {
        label: { type: 'string', description: 'A few words for the file name.' },
        full_page: { type: 'boolean', description: 'The whole page, not only what fits on the screen.' },
        selector: { type: 'string', description: 'Only this part of the page (a CSS selector).' },
      },
    },
    run: async (a) => {
      const r = await seat(`return await shot(${JSON.stringify(String(a.label ?? 'screen'))}, ${JSON.stringify({ full: a.full_page === true, selector: a.selector || undefined })})`);
      if (!r.ok) return { content: [{ type: 'text', text: textOf(r) }], isError: true };
      const path = String(r.result);
      const data = readFileSync(path).toString('base64');
      return { content: [{ type: 'text', text: `(${clock()}) kept as shots/${path.split('/shots/')[1]}` + (r.events?.length ? '\n[the page also said]\n' + r.events.map((e) => '  ' + e).join('\n') : '') }, { type: 'image', data, mimeType: 'image/png' }] };
    },
  },
  {
    name: 'look',
    description: "Read your screen directly: the page's accessibility tree (its headings, buttons, fields, text), or one part of it by CSS selector.",
    inputSchema: { type: 'object', properties: { selector: { type: 'string', description: 'Only this part of the page (a CSS selector). Default: all of it.' } } },
    run: async (a) => ({ content: [{ type: 'text', text: textOf(await seat(`return await look(${JSON.stringify(a.selector || 'body')})`)) }] }),
  },
  {
    name: 'wait_for_change',
    description: 'Wait for something to happen on your screen (someone says something, a turn comes round): waits until the text of the page, or of one part of it, changes, and tells you the new lines. Up to 90 seconds.',
    inputSchema: {
      type: 'object',
      properties: { selector: { type: 'string', description: 'The part of the page to watch (a CSS selector). Default: all of it.' }, seconds: { type: 'number', description: 'How long to wait at most (default 60, at most 90).' } },
    },
    run: async (a) => {
      const ms = Math.round(Math.min(90, Math.max(1, Number(a.seconds ?? 60))) * 1000);
      return { content: [{ type: 'text', text: textOf(await seat(`return await changed(${JSON.stringify(a.selector || 'body')}, ${ms})`, ms + 15000)) }] };
    },
  },
];

const send = (m) => process.stdout.write(JSON.stringify(m) + '\n');
const rl = createInterface({ input: process.stdin });
rl.on('line', async (line) => {
  let m;
  try {
    m = JSON.parse(line);
  } catch {
    return;
  }
  const { id, method, params } = m;
  if (id === undefined) return; // a notification
  try {
    if (method === 'initialize') {
      send({ jsonrpc: '2.0', id, result: { protocolVersion: params?.protocolVersion ?? '2025-06-18', capabilities: { tools: {} }, serverInfo: { name: 'table', version: '1.0.0' } } });
    } else if (method === 'tools/list') {
      send({ jsonrpc: '2.0', id, result: { tools: TOOLS.map(({ run, ...t }) => t) } });
    } else if (method === 'tools/call') {
      const tool = TOOLS.find((t) => t.name === params?.name);
      if (!tool) send({ jsonrpc: '2.0', id, error: { code: -32602, message: `no tool ${params?.name}` } });
      else {
        const started = Date.now();
        const result = await tool.run(params.arguments ?? {});
        const text = (result.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join('\n');
        record({ tool: tool.name, args: params.arguments ?? {}, ms: Date.now() - started, error: result.isError === true, text: text.length > 20000 ? text.slice(0, 20000) + '…' : text, image: (result.content ?? []).some((c) => c.type === 'image') });
        send({ jsonrpc: '2.0', id, result });
      }
    } else if (method === 'ping') {
      send({ jsonrpc: '2.0', id, result: {} });
    } else {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: `no method ${method}` } });
    }
  } catch (e) {
    send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: `ERROR: ${e.message}` }], isError: true } });
  }
});
