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
| H1 | an HTTP server beside the WebSocket: the web clients' files, pack art and pictures, map files | host (Godot) | |
| H2 | join by name (a new player is added; a returning one is found); a local DM role with a token | host | |
| H3 | scene snapshots for web clients, filtered for each viewer (hidden tokens, GM regions, what their tokens see) | host | |
| H4 | chat: messages to everyone, to the DM, to some players; kept in the log and banked into the campaign; the roll log | host | |
| H5 | DM operations and state for the web DM screen (campaign, places, people, notes, pictures, contents, fights, turns, sharing, sessions) | host | |
| W1 | the web project: Vite, TypeScript, Svelte; the protocol client; grid math; the expression language; tests | web | |
| W2 | the map canvas: terrain, props, walls, lights, tokens, fog, backdrops; pan and zoom by mouse and touch | web | |
| W3 | the view renderer: rulesets' sheets, party views, cards, forms, wizards, pickers, prompts | web | |
| W4 | the player's screen: join, map, character, journal (their notes and what they were shown), chat, what the DM shows | web | |
| W5 | the DM's screen: party, map, the book (contents, cards that read well and pop out), showing players things, chat and rolls, sessions, the fight | web | |
| R1 | NPCs and creatures as stat blocks | srd5e | |
| R2 | giving an item: a manual act for the DM | srd5e | |
| R3 | the adventure: a regional map that looks like a region, a cover image | srd5e (package) | |
| G1 | Godot: Home and the first screens restyled; adventure covers; the running-game window; *Join a game* opens the web client | host | |
| T1 | tests: Godot suites for the host; web unit tests; end-to-end in a browser; CI | both | |
| D1 | docs, the playtest-3 script, a build for testers | both | |
