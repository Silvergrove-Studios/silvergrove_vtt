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
  Playwright), `wait_for_change`. Every answer starts with the time. Tools, not
  a shell: scripts with braces in them were refused by the shell's permission
  checks, which the agents took for clicks that didn't land.
- `cast.json` — who plays: persona, device, model, seat port, camera roll.
  `cast2.json` is another table (a warlock, a paladin, a sorcerer, a rogue,
  and a DM who improvises fights): `setup.mjs --cast cast2.json`.
  `cast3.json` names no classes (the players choose), and its DM lets the
  players lead, as the DM brief now asks of every DM.
- `briefs/` — the DM's and the players' briefs (a `session` or a whole
  `campaign`), and `resume.md` to bring an agent back after an interruption
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

`<run>` must be outside any repository. The allowed tools are the table's,
reading and editing the agent's own folder, and web search for D&D; anything
else is refused (`--permission-mode dontAsk`, `--strict-mcp-config`).
