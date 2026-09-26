# The web Table

The DM's screen and the players' screens, as web pages the Hexmap host
serves on the local network (option B of `docs/ui-framework-evaluation.md`,
the plan in `docs/web-table-plan.md`). Players open an address or scan a
code on any phone or computer: nothing to install. The DM's screen opens in
a browser on the computer that runs the game.

Svelte 5, TypeScript, Vite. The host never runs this code: it serves
`webclient.zip` (the build, at the project's root) and talks to the pages
over its WebSocket (`src/lib/net.ts`, `src/lib/game.svelte.ts`).

```sh
npm ci
npm run check   # types and Svelte
npm test        # unit tests (grid, expressions, views, the book, picks, turns)
npm run build   # dist/ → ../webclient.zip — commit it with the sources
```

## Looking at it against a real table

`tools/web_host.gd` starts a campaign package headless and hosts it:

```sh
../run.sh godot --headless --path .. -s tools/web_host.gd -- <package.campaignpkg> \
    --party --seconds 900 --web-port 47790 --ws-port 47787 --info /tmp/host.json --stop /tmp/stop
```

It writes the DM's address (`dm`) and the players' (`player`) to the info
file and stops when its time is up or the stop file appears. Then the
journey — DM, a phone, a laptop; a place shown, chat, a sheet, a fight with
an attack picked on the map — in Chrome, with screenshots:

```sh
npm run e2e -- /tmp/host.json /tmp/journey
```

`tests/e2e/maker.mjs <host.json> <out>` walks the character maker
(host a package whose ruleset has one): a druid by point buy on a phone,
the connection dropped and the page reloaded half way, skills, equipment,
spells and a spell's card, then the DM's *Rules settings* switching to
rolled scores and to the standard array.

`tests/e2e/pictures.mjs <host.json> <out>` (host with `--party`): a
player's token picture through the crop window, on her sheet, the DM's
card and the fight's map; a picture in her journal shared with another
player; a picture in the DM's notes.

`tests/e2e/probe.mjs <host.json> dm|player '<expression>'` evaluates an
expression in a page (`window.hexmap.game` is what the page knows).
