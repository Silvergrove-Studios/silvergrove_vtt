# Playtests by agents

A table of AI agents plays a campaign package through the web Table in real
time — a DM who knows only D&D, and players with personalities — each in
its own browser, sized like their device, talking only through the game's
chat. They keep diaries as they go and write reviews at the end.

The agents must not know the project: each runs as its own `claude -p` in a
folder outside any repository (an agent started from the repository sees
its history and its notes). They know the site only through their browser
tools, can read and write only their own folder, and research D&D on the web.

## Parts

- `seat.mjs` — one Chrome page per person, kept open, sized like their device
  (a phone, a tablet, a laptop); runs the scripts posted to it on 127.0.0.1.
- `table-mcp.mjs` — the browser as tools (MCP): `screenshot` (the image comes
  back to the agent), `look` (the accessibility tree), `act` (a few lines of
  Playwright), `wait_for_change`, and `roll_dice` (the person's own real dice
  beside them, rolled fairly, for a table that types its dice in). Every
  answer starts with the time. Tools, not
  a shell: scripts with braces in them were refused by the shell's permission
  checks, which the agents took for clicks that didn't land.
- `cast.json` — who plays: persona, device, model, seat port, camera roll.
  `cast2.json` is another table (a warlock, a paladin, a sorcerer, a rogue,
  and a DM who improvises fights): `setup.mjs --cast cast2.json`.
  `cast3.json` names no classes (the players choose), and its DM lets the
  players lead, as the DM brief now asks of every DM. `cast4.json` is a table
  of rules lawyers for a `oneshot` at level 12: experienced players who do
  their homework and check the site against the rules at every level.
- `cast5-bookkeeping.json`, `cast5-rolling.json`, `cast5-assisted.json`,
  `cast5-automated.json` — the levels playtest: four tables, each with a DM
  whose persona wants one of the site's four ways of running a table (never
  named to them: they choose in the site's walkthrough) and players whose
  dice and devices vary. Each table has its own seat ports (9310s, 9320s,
  9330s, 9340s), so they can run side by side.
- `briefs/` — the DM's and the players' briefs (a `session` or a whole
  `campaign`; a `oneshot` has briefs of its own, `dm-oneshot.md` and
  `player-oneshot.md`: build a level-12 character, keep a rules log in
  `rules.md`), and `resume.md` to bring an agent back after an interruption
  (its diary is its memory).
- `setup.mjs` — makes each person's folder (brief, pictures, tools' config),
  starts the seats, prints the command that starts each agent.
- `watch.py` — for a monitor: an agent finished or stopped, a diary gone
  quiet, a seat down; a status line every 15 minutes.

## Logs

Everything a run did can be read back:

- the host's `--log <file>`: each message a screen sent (who, what), each
  refusal the table answered with, each change it applied, joins and leaves;
- per person, in their folder: `log/agent.jsonl` (the agent's whole stream:
  what it thought aloud, each tool it used, each answer), `log/tools.jsonl`
  (each table tool call, its script, how long, its answer), `log/page.jsonl`
  (the browser: scripts run, console, page errors, dialogs, the socket),
  `timelapse/` (the screen every two minutes), `shots/` (the agent's own
  screenshots), `diary.md`, `review.md`, `improvements.md` (what each
  would change, most important first) and `favorites.md` (the screenshots of
  their favourite and least favourite parts);
- `timeline.mjs <run>` merges them into one timeline (`timeline.md`: every tool
  call too) and the story alone (`table.md`: chat, rolls, the DM's moves,
  refusals, who joined).

## A run

```
# the table: a campaign package, hosted headless (it runs until the stop file)
./run.sh godot --headless --path . -s tools/web_host.gd -- <package> \
    --seconds 21600 --web-port 47780 --ws-port 47777 --info <run>/host.json --stop <run>/host.stop --log <run>/host.jsonl

# the seats and the briefs (a whole campaign in 3½ hours, starting in 3 minutes)
node tools/agent_playtest/setup.mjs --run <run> --host <run>/host.json --mode campaign --hours 3.5

# then each agent, with the command setup printed (one at a time, in the background)
python3 -u tools/agent_playtest/watch.py <run>

# afterwards
kill $(cat <run>/seats.pids); touch <run>/host.stop
```

For a one-shot of rules lawyers, give them the rulebook they're limited to:
`--mode oneshot --cast tools/agent_playtest/cast4.json --docs <rules> --dm-docs
<rules with the creatures>` copies each folder into their own as `srd/`.

`<run>` must be outside any repository. The allowed tools are the table's,
reading and editing the agent's own folder, and web search for D&D; anything
else is refused (`--permission-mode dontAsk`, `--strict-mcp-config`).

## The levels playtest

Four tables, one per way of running a table. The DM sets the table up through
the site's walkthrough (`--walkthrough` on the host), and the briefs'
`{{#setup}}` sections (`setup.mjs --setup`) ask the DM to set it up their own
way — how much the site does, whose dice, where fights happen (maps or the
theatre of the mind), what the players know — make their rulings through the
site, give slow players time to answer, and try the map's tools; the players
read how their table runs, choose what the DM leaves to them (their dice,
being asked about their reactions), and roll their own dice with `roll_dice`
where the table types dice in (the DM too, for monsters).

```
# one table (here the first); each table its own host ports, away from 47777/47780
./run.sh godot --headless --path . -s tools/web_host.gd -- <package> --walkthrough \
    --seconds 21600 --web-port 48710 --ws-port 48711 --info <run>/host.json --stop <run>/host.stop --log <run>/host.jsonl
node tools/agent_playtest/setup.mjs --run <run> --host <run>/host.json --mode session --setup \
    --cast tools/agent_playtest/cast5-bookkeeping.json
```

The other tables: `cast5-rolling.json`, `cast5-assisted.json`,
`cast5-automated.json`, each with its own `<run>` and host ports. A package
may suggest a level (The Ruined Chapel suggests Assisted); the walkthrough
shows the suggestion and each DM chooses for themselves.

