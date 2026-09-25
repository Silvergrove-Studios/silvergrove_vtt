# Is Godot the right UI framework? (2026-09-25)

Two playtests in, the UI is what stops people: after the second, the
testers did not get as far as a fight, and said the Table *feels more like
Photoshop than a user-friendly tool* (`docs/playtest-2.md`). The user asked
for a round evaluating whether the choice of UI framework was the best.
This is that round: what we have, what the product needs from a UI stack,
the options, and a recommendation with a spike to test it before anything
is committed.

## First, what the framework is not to blame for

Most of the playtest's complaints are **design**, and they are mine: a
screen that starts with a map and no context, docked panes and an editor's
menu bar, tools named for the tool rather than the job (*Select*,
*Token*), four verbs for one fight (*Show*, *Stage*, *Launch*, *Go*), a
character sheet where a stat block belongs, no chat. A new framework with
the same design would get the same notes. Whatever we choose, the next
step is a designed DM screen — mocked up and agreed before it is built,
which the J3 step of `docs/playtest-1.md` asked for and I skipped.

The framework question is narrower: **how well, and how cheaply, can each
stack build a friendly, text-heavy app for the DM, and get players in from
their phones?** On that, Godot's toolkit does have real costs.

## What we have

| area | GDScript lines | what it is | framework-bound? |
|---|---|---|---|
| core, encounter, rules, net, io | ~17,000 | the maps and encounter documents, the event log, the rules kernel, the Luau plugin host, packages, the network protocol, exports | no (logic; it runs in Godot, but nothing in it is UI) |
| render | ~1,200 | the map canvas: terrain, props, walls, lights, fog, vision | yes (Godot 2D drawing) |
| table, player, ui, shell | ~13,900 | the DM's Table, the phone client, the view renderer, Home | yes (Godot Control nodes) |
| editor | ~4,100 | the map editor | yes |
| tests, tools | ~10,600 | 11,430 checks, journey and build tools | mostly logic tests |
| rulesets (Luau) | ~8,100 | srd5e and the sample plugins | no: plain Luau against the `hexmap.*` API |
| native | — | the Luau GDExtension (C++), Android NSD | Godot-bound |

Two things in the architecture matter a great deal here:

- **The Table and the phones talk JSON over WebSocket**, and what a
  player sees is sent as data: the projection of the rules state and the
  rulesets' views as declarative JSON. A browser could be a client of
  today's host without the host changing.
- **There is already a co-DM role** that gets the whole table and may
  drive it. A DM's screen in a browser is, to the protocol, a co-DM.

## What the product needs from a UI stack

0. **The same platforms as today (a fixed requirement, not a trade-off):**
   a game is **hosted** on macOS, Windows or Linux, and **played** on
   macOS, Windows, Linux, iOS or Android. Every option must keep all of
   these.
1. **App-like DM screens, cheap to make friendly**: typography (a
   display face, readable body text), rich formatted text (stat blocks,
   descriptions), lists, trees and forms, pop-out windows, drag and drop,
   a theme that does not look like an editor.
2. **Players in within seconds, on any phone**: no app to install, and a
   second window on the same computer can join. (Today an iPhone player
   needs TestFlight or the App Store; we have neither.)
3. **A map canvas** for hex and square maps with terrain, props, walls,
   lights, fog and vision; smooth pan and zoom, touch on phones.
4. **The rules sandbox (Luau) stays sealed**, and runs only on the host.
5. **Works offline on a LAN**, hosted by the DM's laptop.
6. **Desktop builds** for macOS, Windows, Linux (the host, and players on
   laptops).
7. **Text input on phones** that works: chat, notes, names.
8. **Cost and risk of change**, and keeping what the 11,430 checks prove.
9. Accessibility and other languages, eventually.

## Where Godot's toolkit costs us

- **Every friendly screen is hand-built.** Godot's Controls are a game
  engine's widgets: layout, theming and text work, but nothing is
  app-like by default. Typography is one theme font per type unless each
  label is styled, rich text is BBCode, and lists and trees are the
  editor's own.
- **The editor's look is the path of least resistance.** Docked panes,
  menu bars, tool rows and property forms are what Godot makes easy,
  which is how the Table came to look like the editor it grew out of.
- **Players must install an app.** Android can sideload; iPhones cannot
  without Apple's distribution. Godot can export the phone client for the
  web (single-threaded exports need no special headers since 4.3), but it
  is a large download and mobile browsers' keyboards and text entry are
  weak under it, which matters for chat and notes.
- **What Godot does well** we would give up in part: one codebase for
  desktop and phones, a capable 2D renderer (the map canvas), and the
  Luau GDExtension, which is ours and works.

## The options

### A. Stay on Godot and redesign

Build the designed screens in Godot: a component kit (cards, callouts,
chips, a stat-block view), a display font and a real type scale, no docked
panes or in-window menu bar on the DM's screen, real windows for pop-outs
(Godot supports separate OS windows on desktop). Serve the phone client
as a Godot web export from the Table, beside the native apps.

- **Platforms:** as today — the host on all three desktops; players on
  the desktop apps, the Android app, the iOS app (which needs Apple's
  distribution to reach testers), or the web export in a phone's browser.
- **For:** no rewrite; one language; the tests stay; the map canvas stays.
- **Against:** the slowest way to make friendly, text-heavy UI, and the
  lowest ceiling for it; the phone client's text entry on the web stays
  weak; every screen is custom work.
- **Size:** the DM and phone screens redesigned in place, about 14,000
  lines of UI touched.

### B. Keep Godot as the engine; move the Table and phone UIs to the web (recommended to try first)

Godot stays the **host**: the rules kernel, the plugins, the campaign and
packages, the network, and the map editor. The DM's screen and the
phones' become **web clients** (TypeScript, a component framework such as
Svelte or React, a WebGL map renderer such as PixiJS) speaking the
existing protocol. The host serves them over HTTP beside its WebSocket:
players open an address (or scan a QR code the Table shows)
and are in; the DM's screen opens in a browser window (a thin desktop
shell such as Tauri can come later).

- **Platforms:** the host is the Godot app on macOS, Windows and Linux,
  as now, and the DM's screen is a browser window on the same machine.
  Players play in a browser on any of the five — macOS, Windows, Linux,
  iOS, Android — with nothing to install, so the iOS distribution problem
  goes away. If a store app is wanted later, the same web client can be
  wrapped (as an installable web app, or in a native shell) without a
  rewrite.
- **For:** the UI moves to the platform every successful VTT uses (Roll20,
  Foundry VTT, Owlbear Rodeo). Typography, rich text, forms, pop-outs
  (browser windows), drag and drop, accessibility and phone text entry
  come with the platform. No app install for players, iPhones included; a
  second window on the same computer is just another tab. The kernel,
  rules, plugins and their tests stay as they are, and the protocol
  already carries what the phones see.
- **Against:** two stacks (GDScript for the host, TypeScript for the
  UIs). The map canvas and its fog and vision must be written again for
  WebGL, about 1,200 lines of drawing plus the vision code. The DM's
  screen needs host operations the protocol does not have yet (prep:
  places, notes, folders, sharing; today the Table's panes change the
  campaign directly). The host needs a small HTTP server for the static
  files. The DM runs the app and a browser window, until a desktop shell
  wraps them.
- **Size:** about 14,000 lines of UI replaced by new web code; the map
  canvas ported; a DM API added to the protocol; about 17,000 lines of
  logic and most tests kept.

### C. Rewrite everything for the web

Everything in TypeScript: the kernel on Node (inside Electron or a small
server), Luau compiled to WebAssembly for the plugins, the UIs as in B,
the map editor on the web too.

- **Platforms:** the host in Electron (or Node) on the three desktops;
  players in a browser on all five.
- **For:** one language and one runtime; the cleanest end state; could
  later run with no install at all.
- **Against:** everything rewritten, about 38,000 lines, and 11,430 checks
  to port and re-earn, with no playable build for the length of it. The
  plugin sandbox has to be rebuilt and re-audited on WebAssembly.
- **Size:** the whole product.

### D. Flutter

One Dart codebase for desktop and phone apps with good widgets and a
custom canvas.

- **Platforms:** Flutter builds for all five, host and player; iOS still
  needs Apple's distribution.
- **For:** better app widgets than Godot, and still native apps.
- **Against:** a full rewrite, like C, and players still install an app
  (the iPhone problem stays); smaller ecosystem for this kind of product.

Rejected: embedding a web view inside the Godot app. Third-party
extensions exist, but they add a browser engine to the build for the
benefit B gets from the user's own browser.

## Side by side

| need | A. Godot, redesigned | B. Godot host + web UIs | C. all web | D. Flutter |
|---|---|---|---|---|
| host on macOS / Windows / Linux | yes | yes | yes | yes |
| play on macOS / Windows / Linux / iOS / Android | yes (iOS via Apple's store) | yes (a browser on each) | yes (a browser) | yes (iOS via Apple's store) |
| friendly, text-heavy DM screens | possible, slow | strong | strong | good |
| players in without installing | web export: heavy, weak text entry | yes (a link or QR code) | yes | no |
| same-computer join | fixable | yes (another tab) | yes | fixable |
| map canvas | have it | port to WebGL | port to WebGL | port |
| rules sandbox | have it | have it | rebuild on WASM | port via FFI |
| offline LAN | yes | yes | yes | yes |
| keeps the logic and its tests | all | most | none | none |
| size of change | medium | large, incremental | very large | very large |
| risk | low; the ceiling is the risk | medium; a spike tells us | high | high |

## Recommendation

**B, tested by a spike before we commit.** It is the only option that
fixes the two things the toolkit is responsible for, friendly screens and
getting players in, without throwing away the parts that work: the
kernel, the rules sandbox, the formats and most of the tests. It is also
incremental: the phone client can ship first (it solves the install and
same-computer problems on its own), then the DM's screen, with Godot's
Table still there until the web one replaces it.

**The spike** (time-boxed; nothing is removed):

1. The host serves the web clients' files beside its WebSocket; the
   Table shows the join address as a QR code.
2. A web phone client: join, see the map (a first WebGL canvas: terrain,
   tokens, fog as the host sends it), a character sheet (the view
   renderer in TypeScript), chat.
3. The DM's World screen, designed first as a mockup for the user, then
   built as a web client: the party, the map, the reference with cards
   that read well and pop out, *Show the players*, chat and the roll log.
4. A review with the user: how it looks, how it felt to build, what the
   map canvas costs. Then the decision.

**If the spike disappoints** (the map canvas proves hard, or two stacks
feel worse than they look), fall back to **A** with the designed screens
and what the spike taught us. C and D are not worth their cost now; C
remains a possible later consolidation if the host ever needs to leave
Godot.

**Meanwhile**, what does not depend on this goes ahead: chat and the roll
log as a data model in the host (kept in the campaign), private and group
messages, joining from the same computer, stat blocks for NPCs in srd5e,
a real regional map and a cover image for the adventure, and loot as a
manual *Give an item* act.

## Open points to settle in the spike

- Whether mobile browsers on the LAN keep the WebSocket alive when the
  phone sleeps (and how quickly a player gets back in).
- How the host serves the files: on the same port (the host reads the
  request itself and completes the WebSocket handshake, since Godot's
  WebSocketPeer wants to read it) or on a second port beside it.
- How fog and vision reach a web client: computed by the host and sent,
  or ported with the canvas.
- Which component framework (Svelte or React) and map renderer (PixiJS
  or plain Canvas 2D) — small decisions, made on what builds the spike
  fastest.
