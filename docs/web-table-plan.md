# The web Table: plan and progress (branch `web-table`)

Option B of `docs/ui-framework-evaluation.md`, built for the third
playtest: **Godot stays the host** (rules kernel, Luau plugins, campaigns,
packages, networking, the map editor); **the DM's screen and the players'
screens become web pages** the host serves on the LAN. Players open a link
(or scan a QR code) on any phone or computer — nothing to install; the DM's
screen opens in a browser window on the host machine. Hosting stays on
macOS, Windows and Linux; playing works on those and on iOS and Android.

## The next playtest's journey

1. The DM opens Hexmap → *Run a game* → starts or continues an adventure
   (Godot's first screens, restyled).
2. The DM's screen opens in the browser. The Hexmap window says the game
   is running and how players join.
3. Players scan the QR code the DM's screen shows (or type the address),
   type their name, make a character.
4. The DM runs the village: reads places out, shows pictures and handouts,
   talks as the NPCs (their cards: stat block, what they know), asks for
   rolls; everyone chats; rolls land in the log.
5. The DM runs the chapel fight: launches it from the place, reveals
   creatures, rolls initiative, runs turns with stat blocks and attacks
   picked on the map, ends it.

## The work

| # | what | where | status |
|---|---|---|---|
| H1 | an HTTP server beside the WebSocket: the web clients' files, pack art and pictures, map files | host (Godot) | done — serves `webclient.zip` (one file the exports carry; Godot would import a folder of fonts), reopened when rebuilt |
| H2 | join by name (a new player is added; a returning one is found); a local DM role with a token | host | done — any spelling of this computer's address counts (a browser's `localhost` arrives as long-form IPv6) |
| H3 | scene snapshots for web clients, filtered for each viewer (hidden tokens, GM regions, what their tokens see) | host | done |
| H4 | chat: messages to everyone, to the DM, to some players; kept in the log and banked into the campaign; the roll log | host | done |
| H5 | DM operations and state for the web DM screen (campaign, places, people, notes, pictures, contents, fights, turns, sharing, sessions) | host | done — and a launched fight now brings the party's tokens (the players saw only fog without them) |
| W1 | the web project: Vite, TypeScript, Svelte; the protocol client; grid math; the expression language; tests | web | done — Vite 8, Svelte 5, TypeScript 6; the build is reproducible (CI checks the committed zip) |
| W2 | the map canvas: terrain, props, walls, lights, tokens, fog, backdrops; pan and zoom by mouse and touch | web | done — Canvas 2D; pack SVGs rasterised once per size; terrain cached; follows the player's own token |
| W3 | the view renderer: rulesets' sheets, party views, cards, forms, wizards, pickers, prompts | web | done — every widget type, forms, wizards, pickers, prompts |
| W4 | the player's screen: join, map, character, journal (their notes and what they were shown), chat, what the DM shows | web | done — join by name or a tap, map, character (or the maker), table, chat, journal, what the DM shows |
| W5 | the DM's screen: party, map, the book (contents, cards that read well and pop out), showing players things, chat and rolls, sessions, the fight | web | done — book with folders, cards that pop out, show the players, chat, the fight bar and order, stat blocks, targets picked on the map, a next-step note, the rules' questions to the DM |
| R1 | NPCs and creatures as stat blocks | srd5e | done — derived.block carries the lines; the sheet is a stat block for a creature or a person made from one; a damage-or-healing form for the DM |
| R2 | giving an item: a manual act for the DM | srd5e | done — give_item (said in the log); Give an item / Give a magic item on a sheet for the DM; players add gear but no magic items |
| R3 | the adventure: a regional map that looks like a region, a cover image | srd5e (package) | done — The Vale of Thornwick, painted, in place of the forest road; a cover; Start here written for the web screen (built to try out; the package's version waits on a decision) |
| G1 | Godot: Home and the first screens restyled; adventure covers; the running-game window; *Join a game* opens the web client | host | done — Home and the picker restyled (Fraunces, cards, covers); the running panel; the DM's screen opens as the campaign opens; Join a game offers the browser; End the fight's loot wording |
| T1 | tests: Godot suites for the host; web unit tests; end-to-end in a browser; CI | both | done — Godot suites (11,516 checks), 30 web unit tests, `tools/web_host.gd` + `web/tests/e2e/journey.mjs` (21 steps in Chrome: joining, showing, chat, character making, a roll asked, the party moved, a place revealed, the fight with an attack picked on the map), CI job for the web |
| D1 | docs, the playtest-3 script, a build for testers | both | in progress — `docs/playtest-3.md`, README, CHANGELOG; the build for testers waits on a version decision |
