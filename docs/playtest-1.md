# Playtest 1: what the DMs hit, and what we did about it

The first wave of human testing (2026-09, Hexmap 2.1.0 on macOS, "The
Ruined Chapel" package). The testers' notes, grouped, then the change for
each. Status is kept here so the next wave can check it.

## What they said, by theme

**The window did not answer at first.** After starting a campaign from a
package, the File menu and toolbar in the window did nothing and showed
no tooltips; only the macOS menu at the top of the screen worked. After a
few clicks in that macOS menu, the window's menus, buttons and tooltips
started working together. (Four notes: menus dead, toolbar icons dead and
without tips, "started working after a few interactions", "hover text
started working at the same time".)

**Starting was a blank page.** A DM who had just started a campaign did
not know what to do next. The package "seemed to have no scenes": the
scene drop-down was empty and did nothing, because a package starts with
its maps in the library but no scene shown.

**Controls that did not belong where they were.** The token tool and the
fog of war were offered with no map on screen; turns could be started
with no map scene.

**Words that did not explain themselves.** *Checkpoint* — marked from the
Edit menu, with nothing on the Table to go back to one. *Review a newer
version of its package…* — always in the File menu, for campaigns that
did not come from a package and when there was nothing newer. The
keyboard shortcuts list was missing half of the shortcuts.

**Hosting was a chore.** Network → Host on this network is a step every
DM takes every time; why doesn't the Table host by itself?

## What we did

| # | feedback | change | where | status |
|---|---|---|---|---|
| 1 | window deaf until the macOS menu was used | every dialog, native file dialogs included, hands keyboard focus back to the Table window and brings it forward when it closes; on macOS the app is activated when the Table opens | Hexmap | done (`a039897`) |
| 2 | toolbar icons without tips, doing nothing | same cause as 1; tooltips are all set | Hexmap | done (`a039897`) |
| 3 | a new campaign is a blank page | a campaign with no scene shows its regional map (or its first map) when it opens; a **Getting started** list in the Session pane — show a map, players join (with the address), players make characters, start the session — ticks itself off as the DM goes; the empty canvas says what to do | Hexmap | done (`a039897`) |
| 4 | the package "had no scenes" | fixed by 3; the package also carries a *Start here* note for the DM | Hexmap, ruleset (starter) | done (`a039897`) |
| 5 | the scene drop-down did nothing | it reads "No scene yet — show a map" and opens the Maps pane when there is none | Hexmap | done (`a039897`) |
| 6 | token tool, fog and turns with no map on screen | the map tools, the Scene menu's map items and the Turns pane's Start are disabled until a scene is shown, with a tip that says why | Hexmap | done (`a039897`) |
| 7 | "Checkpoint" meant nothing | renamed **Restore point**: *Mark a restore point…* (with a sentence on what it is for) and *Go back to a restore point* listing them; restoring asks first | Hexmap | done (`a039897`) |
| 8 | "Review a newer version of its package" out of context | shown only for a campaign started from a package, and named for what it does: *Update from package (1.3.0 available)…*; disabled with "up to date" otherwise | Hexmap | done (`a039897`) |
| 9 | shortcuts list out of date | built from the menus' own accelerators and the tools' keys, so it cannot drift | Hexmap | done (`a039897`) |
| 10 | hosting by hand | the Table hosts as soon as a campaign opens (a preference turns it off); the Session pane shows the address players join at; Network → Host stays as the switch | Hexmap | done (`a039897`) |

## Phase 2: the journey itself

The fixes above treat symptoms. The testers could not find their way
onto a map or start anything, and that is a structure problem: the Table
grew out of a map editor (a menu bar and a toolbar of editing tools over
a canvas, with panes docked around it), and a DM running a game needs a
different shape. So the next phase is an audit of the whole user
journey, use cases to hold it to, and a refactor of the UI around them.

| step | what | done when |
|---|---|---|
| **J1 Walk the journey** | Screenshot every screen a new DM and a new player pass through — Home, the campaign picker, a package started, a campaign open with nothing done, hosting, a phone joining, making a character, starting a session, launching a fight — and write down, per screen, what they have to know that the screen does not tell them. | `docs/ui-journey-audit.md` with the screenshots and findings — **done** |
| **J2 Use cases** | The jobs people come to do, as short stories with a start, an end and what must be true for each: start a campaign from a package and run session one; build a campaign from scratch; prep between sessions; run a fight; a player joins and plays from a phone; a returning DM picks up where they left off; an author makes and releases a package. Each names the fewest steps it should take. | `docs/use-cases.md`, reviewed with the user — **drafted, awaiting review** |
| **J3 The shape** | From J1 and J2: the Table's structure — what the first screen is, what is always on screen, what is a mode (prep / play), which panes exist and which become part of a flow, what the editor-era chrome (menu bar, tool bar, docking) keeps and loses. Sketches for the user before code. | an agreed design note with sketches |
| **J4 Refactor** | Build it, screen by screen, each use case as an end-to-end test (the journey tools already drive the Table and phones over the wire). | every use case passes as a test; the four workflows green |
| **J5 Playtest 2** | Same testers, the same package, the use cases as their script. | their notes, against this file |

## Honest notes

- **Item 1 is a diagnosis from the symptoms, not a reproduction.** A
  window that ignores clicks and hover until the app menu is used is how
  macOS treats a window that is not the key window; native file dialogs
  in Godot 4 are known to leave the main window that way. The fix
  restores focus after every dialog. The next playtest should confirm
  it; if it recurs, the note should say what was clicked just before.
- The macOS build is signed ad-hoc since 2.1.0's "damaged" report; macOS
  still asks once before opening an app that is not notarized.
