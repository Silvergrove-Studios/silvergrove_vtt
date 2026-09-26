// One timeline of a playtest by agents, from its logs: what each person
// said and did at the table (the host's log), each tool each agent used
// (its tools.jsonl), and what went wrong in their browsers (page.jsonl),
// in the order it happened. Writes <run>/timeline.md.
//
//   node tools/agent_playtest/timeline.mjs <run> [--host <run>/host.jsonl]
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const run = process.argv[2];
if (!run) {
  console.error('usage: node tools/agent_playtest/timeline.mjs <run> [--host <host.jsonl>]');
  process.exit(2);
}
const hi = process.argv.indexOf('--host');
const hostLog = hi > 0 ? process.argv[hi + 1] : join(run, 'host.jsonl');
const cast = JSON.parse(readFileSync(join(run, 'cast.json'), 'utf8'));
const people = [cast.dm, ...cast.players];

const lines = (file) =>
  existsSync(file)
    ? readFileSync(file, 'utf8')
        .split('\n')
        .filter(Boolean)
        .map((l) => {
          try {
            return JSON.parse(l);
          } catch {
            return null;
          }
        })
        .filter(Boolean)
    : [];
const one = (s, n = 160) => {
  const t = String(s ?? '').replace(/\s+/g, ' ').trim();
  return t.length > n ? t.slice(0, n) + '…' : t;
};
// the host writes local time without a zone; the tools write ISO (UTC)
const when = (at) => new Date(/Z$|[+-]\d\d:\d\d$/.test(at) ? at : at.replace(' ', 'T')).getTime();

const out = [];
const add = (at, who, what) => out.push({ t: when(at), who, what });

/** A roll as the table would say it: "d20 4 + 3 (charisma +1, proficiency +2) = 7, failure". */
function rollWords(en) {
  const r = en.result ?? {};
  const main = (r.dice ?? []).filter((d) => d.group === 'main');
  const kept = main.filter((d) => d.kept !== false).map((d) => d.face);
  const dropped = main.filter((d) => d.kept === false).map((d) => d.face);
  const dice = main.length ? `${main.length > 1 && !dropped.length ? main.length : ''}d${main[0].sides} ${kept.join(' + ')}${dropped.length ? ` (${dropped.join(', ')} not kept)` : ''}` : String(r.groups?.main?.expr ?? '');
  const others = Object.entries(r.groups ?? {}).filter(([g]) => g !== 'main').map(([g, v]) => ` + ${g} ${v?.total ?? '?'}`).join('');
  const mod = Number(r.modifier ?? 0);
  const parts = (r.parts ?? []).filter((p) => Number(p.value)).map((p) => `${p.label} ${Number(p.value) > 0 ? '+' : ''}${p.value}`).join(', ');
  const edge = en.spec?.why_adv ? `, with advantage (${en.spec.why_adv})` : en.spec?.why_dis ? `, with disadvantage (${en.spec.why_dis})` : '';
  return `${dice}${others}${mod ? ` ${mod > 0 ? '+' : '−'} ${Math.abs(mod)}${parts ? ` (${parts})` : ''}` : ''} = ${r.total ?? '?'}${r.outcome ? `, ${r.outcome}` : ''}${edge}`;
}

// the table: players by id, from the events that add them
// (and from a join answered by the table's "Ana joined", for players it had before the log)
const names = {};
// and the characters and creatures, for who rolled what
const actorNames = {};
let joining = '';
for (const e of lines(hostLog)) {
  if (e.dir === 'event' && e.ev?.t === 'player.add') names[e.ev.player?.id] = e.ev.player?.name;
  if (e.dir === 'event' && e.ev?.t === 'actor.add') actorNames[e.ev.actor?.id] = e.ev.actor?.name;
  if (e.dir === 'event' && e.ev?.t === 'actor.set' && e.ev.changes?.name) actorNames[e.ev.id] = e.ev.changes.name;
  if (e.dir === 'in' && e.msg?.t === 'join') joining = String(e.msg.player ?? '');
  const joined = e.dir === 'note' && /^(.+) joined$/.exec(e.text ?? '');
  if (joined && joining && !names[joining]) names[joining] = joined[1];
}
for (const e of lines(hostLog)) {
  const who = e.gm ? 'DM' : e.player ? names[e.player] ?? e.player : 'a screen';
  if (e.dir === 'note') add(e.at, 'table', e.text);
  else if (e.dir === 'out') add(e.at, 'table', `refused ${who}: ${one(e.msg?.why ?? JSON.stringify(e.msg))}`);
  else if (e.dir === 'in') {
    const m = e.msg ?? {};
    if (m.t === 'intent') {
      const it = m.intent ?? {};
      const to = (Array.isArray(it.to) ? it.to : [it.to]).filter((x) => x && x !== 'all').map((x) => names[x] ?? x);
      if (it.kind === 'chat') add(e.at, who, `says${to.length ? ` to ${to.join(', ')}` : ''}${it.private ? ' (private)' : ''}: ${one(it.text, 400)}`);
      else if (it.kind === 'dm') {
        const { kind, op, ...rest } = it;
        add(e.at, who, `(DM screen) ${op ?? '?'} ${one(JSON.stringify(rest), 200)}`);
      } else if (it.kind === 'action') add(e.at, who, `${it.action ?? '?'} ${one(JSON.stringify(it.ctx ?? {}), 200)}`);
      else add(e.at, who, `${it.kind ?? 'intent'} ${one(JSON.stringify({ ...it, kind: undefined }), 200)}`);
    } else if (!['hello', 'view', 'ack', 'pong', 'need'].includes(m.t)) add(e.at, who, `${m.t} ${one(JSON.stringify({ ...m, t: undefined }), 200)}`);
  } else if (e.dir === 'event') {
    const ev = e.ev ?? {};
    if (ev.t === 'log.add') {
      const en = ev.entry ?? {};
      if (en.kind === 'roll') add(e.at, 'table', `roll: ${actorNames[en.actor] ? `${actorNames[en.actor]}, ` : ''}${one(en.label)}: ${rollWords(en)}${en.audience && en.audience !== 'all' ? ` [${en.audience}]` : ''}`);
      else if (en.kind !== 'chat') add(e.at, 'table', `${en.kind ?? 'log'}: ${one(en.text ?? en.title ?? '', 300)}`);
    } else if (['turns.start', 'turns.end', 'turns.advance', 'actor.add', 'token.add', 'scene.add', 'player.add'].includes(ev.t)) {
      add(e.at, 'table', `${ev.t} ${one(ev.actor?.name ?? ev.token?.name ?? ev.player?.name ?? ev.scene?.name ?? '', 80)}`);
    }
  }
}

// each agent: its tool calls, and its browser's troubles
for (const p of people) {
  for (const e of lines(join(run, p.key, 'log', 'tools.jsonl'))) {
    const a = e.args ?? {};
    const what = e.tool === 'act' ? one(a.script, 140) : e.tool === 'screenshot' ? one(a.label ?? '') : e.tool === 'look' ? one(a.selector ?? 'the page') : e.tool === 'wait_for_change' ? `${a.seconds ?? 60}s` : '';
    const err = e.error || /^\(\d\d:\d\d\)\nERROR/.test(e.text ?? '') ? ` → ${one((e.text ?? '').replace(/^\(\d\d:\d\d\)\n/, ''), 160)}` : '';
    add(e.at, p.name, `[${e.tool}] ${what}${err}${e.ms > 20000 ? ` (${Math.round(e.ms / 1000)} s)` : ''}`);
  }
  for (const e of lines(join(run, p.key, 'log', 'page.jsonl'))) {
    if (e.kind === 'pageerror') add(e.at, p.name, `page error: ${one(e.message)}`);
    else if (e.kind === 'socket' && e.state !== 'open') add(e.at, p.name, `the table's socket ${e.state}`);
    else if (e.kind === 'http' || e.kind === 'requestfailed') add(e.at, p.name, `${e.kind} ${e.status ?? e.failure ?? ''} ${one(e.url, 100)}`);
    else if (e.kind === 'console' && e.type === 'error') add(e.at, p.name, `console error: ${one(e.text)}`);
  }
}

out.sort((a, b) => a.t - b.t);
const hhmmss = (t) => new Date(t).toTimeString().slice(0, 8);
const line = (e) => `- ${hhmmss(e.t)} **${e.who}** ${e.what}`;
writeFileSync(join(run, 'timeline.md'), [`# Timeline of ${run}`, '', ...out.map(line)].join('\n') + '\n');
// the story alone: what happened at the table, not each agent's clicks
const table = out.filter((e) => !e.what.startsWith('['));
writeFileSync(join(run, 'table.md'), [`# At the table: ${run}`, '', ...table.map(line)].join('\n') + '\n');
console.log(`${out.length} moments in ${join(run, 'timeline.md')}; ${table.length} at the table in ${join(run, 'table.md')}`);
