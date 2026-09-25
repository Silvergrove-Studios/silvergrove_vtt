# Playtest 2: what the testers hit (2026-09-25)

A brief session with Hexmap 2.2.0 and *The Ruined Chapel* 0.3.0. The
testers stopped before starting a fight: *"we were struggling enough with
the UI we didn't bother trying to start a fight."*

## What they said, by theme

**It does not look or feel like a friendly tool.** *"The whole interface
feels more like I've opened Photoshop than I've opened some user friendly
tool."* The menus are still confusing; the interface is very cluttered.
The first screen is not visually appealing: the game's name and the
descriptions are in the same font; an adventure cannot have an icon or
cover.

**The first moments have no context.** Starting a game drops the DM on a
hex map with no explanation, and it looks like a battle map, not a region.
Clicking the map selects the background art instead of panning. The *Next*
line does not read as something addressed to the DM.

**Reading is cramped.** The Reference pane's cards open in a small area
at the bottom, cannot be popped out, and show long text as one block with
no formatting.

**NPCs are not stat blocks.** A person of the world shows a character
sheet, like a player character's, not the familiar stat block; pressing
*Attack* on one seemed to do nothing (it starts a target pick with only a
status-bar line to say so).

**Missing basics.** No chat and no roll log. Players should be able to
message privately, or a group of players; the chat should be kept in the
campaign. A second copy of the app on the same computer could not join the
game.

**Words and modes that do not explain themselves.** In Prep, the Maps
pane's *Show* puts a map up while its encounters are *staged* — what is
staging, does it start a fight? What do *Select* and *Token* do?

**Loot.** Giving items to players should be a manual act by default.
(Nothing manages loot automatically; the *End the fight* wording — "the
party keeps its wounds and its loot" — suggests it does.)

## Triage

Most of this is design (what is on screen, in what words, with what
emphasis), and would recur in any UI framework if the design stays; some
is the toolkit's friction. The user asked for a round evaluating the UI
framework itself (`docs/ui-framework-evaluation.md`), and the UI work waits
on it. What does not depend on the framework can go ahead.

| # | feedback | kind | depends on the framework decision |
|---|---|---|---|
| P1 | looks like Photoshop; cluttered; confusing menus | design + toolkit | yes |
| P2 | first screen unappealing; one font; no adventure cover | design + toolkit (+ package format: a cover image) | the screen yes; the cover no |
| P3 | a hex battle map with no context on starting | content (the adventure needs a real regional map) + design | the content no |
| P4 | clicking the map selects the background instead of panning | interaction design | yes |
| P5 | *Next* does not read as meant for the DM | design | yes |
| P6 | cards cramped, no pop-out, no formatting | design + toolkit | yes |
| P7 | NPCs are character sheets, not stat blocks | ruleset view (srd5e) | the view's data no; its look yes |
| P8 | *Attack* on an NPC seems to do nothing | interaction design (a pick with no visible prompt) | yes |
| P9 | no chat, no roll log, no private messages; keep chat in the campaign | feature (data model + UI) | the model no; the UI yes |
| P10 | a second app on the same computer cannot join | networking | no |
| P11 | Show / Stage / Launch / Go — what starts a fight? | design (one way to run a fight) | yes |
| P12 | what do Select and Token do? | design (tools named for the tool, not the job) | yes |
| P13 | loot should be manual | wording (+ a *Give an item* action) | no |
