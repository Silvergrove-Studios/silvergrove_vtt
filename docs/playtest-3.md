# Playtest 3: the web Table

The response to the second playtest (`docs/playtest-2.md`) is option B of
`docs/ui-framework-evaluation.md`: Hexmap stays the host — the rules, the
campaign, the network — and the screens people look at are web pages it
serves. The DM's screen opens in a browser on the computer that runs the
game; the players open an address, or scan a code, on any phone or
computer. Nothing to install for them.

This is what changed, how to run the session, and what to watch for.

## What changed, for what the testers said

| # | playtest 2 | now |
|---|---|---|
| P1 | "like Photoshop"; cluttered; confusing menus | The DM's screen is three places and no modes: the book (left), the map the players see (middle), the party and the talk (right). A fight adds a bar over the map. The Hexmap window shows only that the game is running and how players join; the full Table is a press away for prep. |
| P2 | first screen plain; one font; no adventure cover | Home and *Run a game* set names in a display face (Fraunces) over Inter, choices as cards. A package can carry a cover; *The Ruined Chapel* has one. |
| P3 | a hex battle map with no context | The adventure opens on a painted regional map, *The Vale of Thornwick*, with no grid; the chapel's battle map comes with the fight (see *During the playtest* below). |
| P4 | clicking the map selects the background | The map pans when dragged and zooms with the wheel, a trackpad or two fingers; tapping opens what is there (a place's card, a creature's stat block). |
| P5 | *Next* not addressed to the DM | *Your next step · only you see this*, in the DM's colour: invite players, start the session, then read what the adventure says to read first (in *The Ruined Chapel*, its *Introduction*). Gone during a fight. |
| P6 | cards small, no pop-out, no formatting | A card opens large over the map: the picture, the words to read aloud (boxed), the DM's own notes, who is there. *Pop out ↗* puts it in a window of its own. Headings, bold, lists render. |
| P7 | NPCs are sheets, not stat blocks | Creatures and people made from them read as stat blocks (AC, HP, speed, the six abilities, skills, senses, challenge, traits, actions). |
| P8 | *Attack* does nothing visible | A yellow banner over the map: *Scimitar: tap a creature on the map*, with Cancel; the roll lands in the chat. |
| P9 | no chat, no roll log, no private messages | Chat & rolls on every screen: to everyone, to the DM, to some players, or privately between players (the DM does not see those). Kept in the campaign. |
| P10 | a second app on the same computer cannot join | Open another browser window: *Invite players* has *Open a player's screen on this computer*. |
| P11 | Show / Stage / Launch / Go | One way: a fight's place card says *Start the fight*. The party comes onto the fight's map by itself. |
| P12 | what do Select and Token do? | No tools: drag moves, tap opens. |
| P13 | loot should be manual | Nothing is looted by itself. The DM gives: a sheet's Inventory has *Give an item* and *Give a magic item* (players cannot add magic items themselves). |

## Before the session (the DM)

1. Install Hexmap (the build for this playtest) and download
   `ruined-chapel-<version>.campaignpkg` into Downloads.
2. Hexmap → *Run a game* → the adventure's card → *Start*. Start a new
   version fresh: a campaign started from an earlier one keeps its maps.
   Read the *Introduction* in the book before the players come.
3. Your screen opens in the browser. (If not: the Hexmap window's *Open
   the DM's screen*.) Keep the Hexmap window open — it runs the game.
4. *Invite players*: a code to scan and an address. Phones must be on the
   same Wi-Fi as the computer.

## The session

1. **Joining.** Players scan the code, type their name, and make a
   character (three steps: who, abilities, skills). The DM's next-step
   note says who is still making one.
2. **Start session 1** (top of the DM's screen).
3. **Thornwick.** Tap the village on the map (or find it in the book):
   read the boxed text, *Show the players*. Show *The reeve's notice*
   (the book, Handouts). Talk as Marta and the reeve (their cards: what
   they know, the DCs). *Ask for a roll* in the Party panel: the players
   answer on their phones; the rolls land in the chat.
4. **The road.** Drag the party (★) west. On the ford's and the chapel's
   cards, tick *The players can see it on the map* when they learn of
   them. Brother Aldous's hut is south of the road. The goblins' lookout
   is an optional fight on the forest road's battle map: its card has
   *Start the fight* too.
5. **The chapel.** Its card: *Start the fight*. Reveal the goblins
   (Fight → *Reveal them all*, or one at a time), *Roll initiative*,
   *Next turn*. Tap a goblin for its stat block: *Use* on an attack, then
   tap the target. Players attack from their sheet's Combat tab.
6. **End the fight** (the bar over the map), give the loot by hand,
   **End the session**.

Throughout: everyone can chat; the DM can pop cards out; players keep
what they were shown, and their own notes, in the Journal.

## What to watch, and ask

- The first two minutes: does the DM know what to do without help? Do
  the players get in without typing an address?
- Reading aloud from a card; showing things; finding a person or a rule
  in the book.
- The fight: does everyone know whose turn it is (the player's header
  turns gold on their turn)? Does picking a target read clearly?
- Phones: text size, buttons large enough, the map on a small screen.
- The chat: do people use it? Private messages?
- Anything that took more than one try.

## During the playtest: the DM's first notes

Before the rest of the session the DM said the web screens were "a big
improvement", and asked for three things. *The Ruined Chapel* 0.5.0 (the
`playtest-3` prerelease of the ruleset repo, on Hexmap 2.3.0) answers the
first two; the third is in Hexmap after 2.3.0.

| # | the DM said | now |
|---|---|---|
| D1 | "a dnd book usually has a long preamble describing the campaign" | The book opens with *The adventure*: an *Introduction* (background, overview, hooks, how to run it, the people), then *Part 1: Thornwick*, *Part 2: The road west*, *Part 3: The ruined chapel* and a *Conclusion*, in the order they are played. *Running it in Hexmap* is a note of its own. |
| D2 | the forest road used as a regional map does not match one (a log two cells long, a village one cell wide, tents shown but not the chapel); "the forest road IS a battle map" | A true regional map: *The Vale of Thornwick*, painted at one scale — the village a cluster of roofs, the chapel a ruined church on its hill, the hut under an oak, the goblins' tents in the trees — each beside its place's marker. The forest road is a battle map again, for the optional fight at the goblins' lookout. |
| D3 | a regional map may be hex when travel is measured, but for many campaigns it should have no grid at all | Map settings → *Show the grid* (off: no grid drawn, in the editor, the Table, the web screens and the SVG and PDF exports). In 2.3.0 the vale hides its grid with a clear grid colour. |

## Known gaps

- Only the Table can edit maps and prepare places and fights (the full
  Table, from the Hexmap window). The web screens run the game.
- Map notes the DM left on the map show as pins with their titles; they
  cannot be edited from the web screen yet.
- The players' screens need the DM's computer reachable on the same
  network; a guest network that isolates devices will not work.

## For developers

`tools/web_host.gd` hosts a package headless; `web/tests/e2e/journey.mjs`
walks this whole session in Chrome — the DM, two phones and a laptop —
and takes screenshots of each step (`web/README.md`).
