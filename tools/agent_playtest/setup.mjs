// Sets up a playtest by agents: for each person in the cast (a DM who
// knows only D&D, players with personalities) a folder with their brief,
// a few pictures for their camera roll and their tools' config, and a
// browser seat open on the table a host is serving (tools/web_host.gd).
// Prints the command that starts each agent, and the one that brings an
// agent back after an interruption.
//
//   node tools/agent_playtest/setup.mjs --run <dir> --host <host.json>
//       [--mode session|campaign] [--hours 3.5] [--in 3] [--cast cast.json] [--timelapse 120]
//
// Each person's folder keeps its logs: log/agent.jsonl (everything the agent
// said and did, as Claude streams it), log/tools.jsonl (each tool call and
// its answer), log/page.jsonl (what happened in their browser), and a
// timelapse of their screen. The host's own log is its --log.
//
// <dir> must be outside any repository, and so must the agents: they know
// the site only through their browsers (an agent started in the repository
// sees its history and notes, which is what the playtest must not have).
import { chromium } from '../../web/node_modules/playwright-core/index.mjs';
import { spawn } from 'node:child_process';
import { appendFileSync, copyFileSync, existsSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const arg = (k, d) => {
  const i = process.argv.indexOf(k);
  return i > 0 ? process.argv[i + 1] : d;
};
const run = arg('--run') && resolve(arg('--run'));
const hostFile = arg('--host') && resolve(arg('--host'));
if (!run || !hostFile) {
  console.error('usage: node tools/agent_playtest/setup.mjs --run <dir> --host <host.json> [--mode session|campaign] [--hours 3.5] [--in 3]');
  process.exit(2);
}
const mode = arg('--mode', 'campaign');
const hours = Number(arg('--hours', '3.5'));
const castFile = resolve(arg('--cast', join(here, 'cast.json')));
const cast = JSON.parse(readFileSync(castFile, 'utf8'));
const host = JSON.parse(readFileSync(hostFile, 'utf8'));
mkdirSync(run, { recursive: true });
copyFileSync(castFile, join(run, 'cast.json'));

// the evening's clock
const t0 = new Date(Date.now() + Number(arg('--in', '3')) * 60000);
t0.setSeconds(0, 0);
const at = (min) => new Date(t0.getTime() + min * 60000).toTimeString().slice(0, 5);
const end = mode === 'campaign' ? Math.round(hours * 60) : 115;
const times = {
  t_research: at(10),
  t_dm_research: at(8),
  t_character: at(40),
  t_story: at(45),
  t_level: at(95),
  t_wrap: at(mode === 'campaign' ? end - 5 : 112),
  t_end: at(end),
  t_review: at(end + 15),
};

function fill(template, values) {
  let s = template;
  for (const m of ['session', 'campaign']) {
    const re = new RegExp(`\\{\\{#${m}\\}\\}([\\s\\S]*?)\\{\\{/${m}\\}\\}`, 'g');
    s = s.replace(re, (_, inner) => (m === mode ? inner : ''));
  }
  s = s.replace(/\{\{(\w+)\}\}/g, (_, k) => {
    if (!(k in values)) throw new Error(`the brief wants {{${k}}}`);
    return String(values[k]);
  });
  return s.replace(/\n{3,}/g, '\n\n');
}

const people = [{ ...cast.dm, role: 'the DM', brief: 'dm.md', url: host.dm }, ...cast.players.map((p) => ({ ...p, role: 'a player', brief: 'player.md', url: host.player }))];

// pictures for each camera roll: emoji art on painted grounds
const browser = await chromium.launch({ channel: process.env.HEXMAP_BROWSER ?? 'chrome', headless: true });
const page = await browser.newPage();
for (const p of people) {
  const dir = join(run, p.key);
  mkdirSync(join(dir, 'shots'), { recursive: true });
  mkdirSync(join(dir, 'photos'), { recursive: true });
  for (const [name, emoji, a, b, w, h] of p.photos ?? []) {
    await page.setViewportSize({ width: w, height: h });
    const size = Math.round(Math.min(w / [...new Intl.Segmenter().segment(emoji)].length, h) * 0.62);
    await page.setContent(
      `<body style="margin:0;width:${w}px;height:${h}px;display:flex;align-items:center;justify-content:center;background:radial-gradient(circle at 40% 35%, ${b}, ${a} 75%);overflow:hidden"><div style="font-size:${size}px;line-height:1;filter:drop-shadow(0 12px 18px rgba(0,0,0,.45))">${emoji}</div></body>`,
    );
    await page.waitForTimeout(100);
    await page.screenshot({ path: join(dir, 'photos', `${name}.png`) });
  }
}
await browser.close();

const seats = join(run, 'seats.pids');
const commands = [];
for (const p of people) {
  const dir = join(run, p.key);
  const values = { ...times, ...p, name: p.name };
  writeFileSync(join(dir, 'brief.md'), fill(readFileSync(join(here, 'briefs', p.brief), 'utf8'), values));
  writeFileSync(join(dir, 'resume.md'), fill(readFileSync(join(here, 'briefs', 'resume.md'), 'utf8'), values));
  writeFileSync(join(dir, 'mcp.json'), JSON.stringify({ mcpServers: { table: { command: 'node', args: [join(here, 'table-mcp.mjs'), String(p.port), dir] } } }, null, 2));
  mkdirSync(join(dir, 'log'), { recursive: true });
  if (!existsSync(join(dir, 'seat.log')) || !readFileSync(join(dir, 'seat.log'), 'utf8').includes('ready')) {
    const args = [join(here, 'seat.mjs'), '--port', String(p.port), '--url', p.url, '--size', p.size, '--ua', p.ua ?? 'mac', '--dir', dir, '--timelapse', arg('--timelapse', '120')];
    if (p.touch) args.push('--touch');
    const log = openSync(join(dir, 'seat.log'), 'w');
    const child = spawn('node', args, { detached: true, stdio: ['ignore', log, log] });
    child.unref();
    appendFileSync(seats, `${child.pid}\n`);
  }
  const allowed = '"mcp__table" "Read(./**)" "Edit(./**)" "Glob" "Grep" "WebSearch" "WebFetch"';
  const start = (file) =>
    `cd ${dir} && claude -p "$(cat ${file})" --model ${p.model} --permission-mode dontAsk --strict-mcp-config --mcp-config mcp.json --allowedTools ${allowed} -n "${p.name} (playtest)" --output-format stream-json --verbose < /dev/null >> log/agent.jsonl 2>> log/agent.err`;
  commands.push({ who: p.name, start: start('brief.md'), resume: start('resume.md') });
}

// the seats are ready when each says so
const deadline = Date.now() + 30000;
for (const p of people) {
  while (!readFileSync(join(run, p.key, 'seat.log'), 'utf8').includes('ready')) {
    if (Date.now() > deadline) throw new Error(`${p.name}'s seat did not start: see ${join(run, p.key, 'seat.log')}`);
    await new Promise((r) => setTimeout(r, 250));
  }
}
writeFileSync(join(run, 'commands.json'), JSON.stringify(commands, null, 2));
console.log(`${mode}: starts ${at(0)}, characters by ${times.t_character}, story by ${times.t_story}, ends ${times.t_end}, reviews by ${times.t_review}`);
for (const c of commands) console.log(`\n# ${c.who}\n${c.start}`);
console.log(`\n(resume commands in ${join(run, 'commands.json')}; stop the seats with: kill $(cat ${seats}))`);
