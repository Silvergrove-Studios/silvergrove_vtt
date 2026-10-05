# The web Table

The DM's screen and the players' screens, as web pages the Hexmap host
serves on the local network (option B of `docs/ui-framework-evaluation.md`,
the plan in `docs/web-table-plan.md`). Players open an address or scan a
code on any phone or computer: nothing to install. The DM's screen opens in
a browser on the computer that runs the game.

Svelte 5, TypeScript, Vite. The host never runs this code: it serves
`webclient.zip` (the build, at the project's root) and talks to the pages
over its WebSocket (`src/lib/net.ts`, `src/lib/game.svelte.ts`). A view, a
scene and the DM's state come whole once and then as what changed, each
view schema once by an id made from its contents (`src/lib/wire.ts`, the
host's `hexmap/net/wire.gd`): the page keeps the schemas, for a reload
too, and says which it holds when it joins.

```sh
npm ci
npm run check   # types and Svelte
npm test        # unit tests (grid, expressions, views, the book, picks, turns, rulers and templates, the wire, dice typed in)
npm run build   # dist/ → ../webclient.zip — commit it with the sources
```

## Looking at it against a real table

`tools/web_host.gd` starts a campaign package headless and hosts it:

```sh
../run.sh godot --headless --path .. -s tools/web_host.gd -- <package.campaignpkg> \
    --party --seconds 900 --web-port 47790 --ws-port 47787 --info /tmp/host.json --stop /tmp/stop
```

It writes the DM's address (`dm`) and the players' (`player`) to the info
file and stops when its time is up or the stop file appears. To try work
in progress with the zip left as it is, build it elsewhere
(`npx vite build --outDir /tmp/webdist`) and add `--web-root /tmp/webdist`.
Then the journey — DM, a phone, a laptop; a place shown, chat, a sheet, a
fight with an attack picked on the map — in Chrome, with screenshots:

```sh
npm run e2e -- /tmp/host.json /tmp/journey
```

`tests/e2e/maker.mjs <host.json> <out>` walks the character maker
(host a package whose ruleset has one): a druid by point buy on a phone,
the connection dropped and the page reloaded half way, skills, equipment,
spells and a spell's card, then the DM's *Table settings* switching to
rolled scores and to the standard array; a Thaumaturge acolyte cleric by
the array, whose skills say they're her background's, and whose level 2
(the DM's, at a milestone) asks for the spell her prepared list grows by.

`tests/e2e/levels.mjs <host.json> <out>` (host with `--party`): the DM
gives the party three levels and Ben takes Brakka's on his phone, level 2
in one tap, then each level's choices in its wizard (the Champion at 3;
the Ability Score Improvement and a weapon mastered at 4, said on its last
step), the wizard starting over for each level.

`tests/e2e/pictures.mjs <host.json> <out>` (host with `--party`): a
player's token picture through the crop window, on her sheet, the DM's
card and the fight's map; a picture in her journal shared with another
player; a picture in the DM's notes.

`tests/e2e/bookkeeping.mjs <host.json> <out>` (host with `--party
--wizard`): how much the rules do is the DM's. The DM sets the table's
sheets to Bookkeeping in the settings, and Ana's sheet follows at once: a
By hand tab, no Cast, Sela's spell slots counters she ticks herself (the
table hears of it), a condition a tap and a note. In the chapel fight the
DM wounds a goblin on its stat block, its Bloodied mark on her map; the DM
says the players see nothing of a monster's health and the mark leaves her
map, the DM's keeping it; at Exact its hit points show under it on both.

`tests/e2e/things.mjs <host.json> <out>` (host with `--party`): things
a caster moves. The DM gives Wren Dancing Lights; in the chapel fight, on
her turn, Ana casts it at a space on her phone, and her sheet says how the
four lights move; she taps one light and then Wren, and it goes onto
Wren's own square; another goes to a space away from her; one sent off
alone is refused, saying why.

`tests/e2e/summons.mjs <host.json> <out>` (host with `--party --wizard
--seed 12`): a creature a spell makes. The DM gives Sela Find Familiar;
in the chapel fight, on her turn, Ana casts it on her phone, choosing an
owl (fey) as it's cast; the owl comes up beside Sela with a tab of its
own on her Character pane (its stat block: whose familiar it is), and a
slot of its own in the order; on its turn Ana moves it on the map and
ends its turn from its tab; a goblin's arrow drops it to 0 and it's gone
from the map, the order and her tabs.

`tests/e2e/choices.mjs <host.json> <out>` (host with `--party --wizard
--seed 5`): what the rules make the player's choice is asked, never taken
for her. The DM gives Sela Chromatic Orb; in the chapel fight Ana casts it
at a goblin on her phone, and before anything is spent a card asks the
type of orb (a button each, Cancel spends nothing); she picks Fire, and the
cast's line and its rolls say Fire. Then the DM gives Sela a Javelin of
Lightning; her throw hits, and a card is in front on her phone at once
(Piercing or Lightning, its seconds counting) while the DM's screen says
the table waits on her; the DM answers it for her (Answer, beside Go on)
and the damage roll says Lightning.

`tests/e2e/tools.mjs <host.json> <out>` (host with `--party --wizard
--seed 5`): the table's tools, everyone's. The DM gives Sela Fireball; in
the chapel fight, one goblin hidden from the players again, Ana previews
Fireball on her phone off her turn and puts it on the goblins; Ben's
screen and the DM's show it with its label ("Sela: Fireball, 20-ft
sphere"), and say who it would catch — Ben's only the creatures he can
see, the DM's the hidden goblin too; Ben measures from Brakka with the
ruler and Ana's phone shows it as his laptop does; the DM pings by a
right-click (both players see it, and not a second ping over the hidden
goblin); the DM puts a template on the goblins and deals Damage those
caught from its banner (the DM's card: a fire trap, DC 40) — their saves
rolled, it lands, Ben's chat saying so without the hidden goblin — and a
template on Sela puts her save on a card on Ana's phone, nothing rolled for
her until she rolls it; then the DM clears everyone's marks. (On a package
built on the rules being tried, as for rulings.mjs.)

`tests/e2e/reactions.mjs <host.json> <out>` (host with `--party --wizard
--seed 12`: Ana plays Sela, a wizard with Shield prepared, and the dice
start from a known place): the chapel fight; a goblin's hit on Sela puts
a Shield card on Ana's phone at once, its seconds counting down, while
Ben's screen and the DM's say whom the fight waits on; she casts it, the
attack misses, and her level 1 slot and her reaction are spent; the next
round the DM goes on without waiting for her answer.

`tests/e2e/settings.mjs <host.json> <out>` (host with `--walkthrough`:
the campaign as a DM starting it has it, not yet set up): how the table
runs. The walkthrough opens by itself on the DM's screen — on maps,
Assisted offered and Bookkeeping picked, the table's questions each with a
line of its answer (one opened with Change), the rules options and a house
rule, a summary that says Bookkeeping; then Table settings: "As Bookkeeping
has it", a switch to Automated that says what it would change and is
cancelled, a setting changed by hand ("Customized") and its section's
Reset. A player joins and is shown How this table runs, and finds it again
in the ⋯ menu.

`tests/e2e/overrides.mjs <host.json> <out>` (host with `--party --wizard
--seed 12`): the DM's hand on anything. In the chapel fight the DM opens a
goblin's Adjust tab and sets its AC to 17: the tab and its stat block say
"AC 17 · 15 computed, set by the DM", the log says so to the DM alone, and
the other goblins keep 15; a goblin's hit on Sela puts a Shield card on
Ana's phone, she casts it and her reaction is spent, and the DM gives it
back from Sela's Adjust tab (said to everyone); on her turn her Fire Bolt at
the goblin is rolled against AC 17 (the DM's log says so; Ana's doesn't).

`tests/e2e/rulings.mjs <host.json> <out>` (host with `--party --seed 12`,
on a package built on the rules being tried: `tools/package.py --out` and
`build_starter.gd --out … --rules …` in the ruleset): the DM's rulings and
the approval step. The DM turns on *Approve outcomes before they land* in
Rules settings (an Assisted table); in the chapel fight a goblin's hit on
Wren (Ana's rogue) is in everyone's chat at once while its damage waits on
the DM's card (Apply, Change…, Skip), Ana's phone and Ben's screen saying
the table waits on the DM, Wren unhurt; the DM changes the damage and
applies it, and the log says so; a later hit applied as it is, the DM
calls it a miss from its line in Chat & rolls (Rule), and the damage is
healed back — the roll's line kept as it was rolled.

`tests/e2e/mind.mjs <host.json> <out>` (host with `--party --wizard
--seed 12`, on a package built on the rules being tried, as for
rulings.mjs): a fight in the theatre of the mind. The DM lets each fight
decide where it happens (Table settings), gives Sela Burning Hands and
makes a fight with no map — three goblins — and starts it in the theatre
of the mind: the DM's screen and both players' Map tabs show who's in the
fight (names, health, the order) and no map. On Sela's turn Ana picks a
goblin from the list for her Fire Bolt; on her next she casts Burning
Hands naming two goblins ("Who does your Burning Hands catch?"), and
nothing lands until the DM applies it on a card, though the table
approves nothing else. The DM adds a wolf with no token to put down; the
fight ends.

`tests/e2e/traffic.mjs <host.json> <out> [--budget] [--frames]` (host with
`--party --seed 12`): what the table sends the screens, measured. The DM's
screen and Ana's phone through the chapel fight's first rounds (the session
and the fight started, initiative, the party inside, a goblin's attack, Ana's
attacks on her turns, a line of chat), Ana's phone dropping its connection
and coming back, and the DM setting the sheets to Bookkeeping (the sheets
built anew): every message each page receives counted by kind and size,
phase by phase; views, scenes and the DM's state taken apart by what they
carry, the view schemas on their own. `--budget` fails the run when a
schema reaches a page twice unchanged or a phone's views run large;
`--frames` writes every message to `<out>/frames.jsonl`.

`tests/e2e/hidden.mjs <host.json> <out>` (host with `--party`, on a package
built on the rules being tried, as for rulings.mjs): what the players know.
The DM keeps monsters' names and conditions from the players (Rules
settings) and gives Wren Fireball. In the chapel fight one goblin is shown:
on Ana's phone and Ben's laptop it is "a creature" labelled "?", the DM's
stat block saying what the players call it; its scimitar at Wren is "A
creature: Scimitar → Wren" in their chat and the goblin's in the DM's. A
second goblin shown, the two are 1 and 2, and Ana's Fireball preview says
"2 creatures" on Ben's screen; the DM seeing as Ana has her names and her
marks; the DM reveals the first goblin's name (Reveal its name) and both
players' screens name it, its token and the roll said before; a Frightened
put on the other goblin from its stat block reaches neither player.

`tests/e2e/dice.mjs <host.json> <out>` (host with `--party --seed 12`, on a
package built on the rules being tried, as for the rulings journey): real
dice typed in, the creatures' rolls out of sight, and a player's own
preference. The DM gives Wren a dagger and sets the table to real dice:
Ana's attack asks her phone for her d20 (a 25 is refused, saying a d20
shows 1 to 20; the total worked out as she types) and then her damage
dice, and the chat marks both rolls *rolled at the table*. The DM lets
each player choose: Ana takes her own dice in *My preferences* (⋯), the
DM's Table settings lists it as hers, her next attack asks (*Roll it for
me* lets the app roll it), and back on the app's dice the next rolls at
once. In the chapel fight the DM rolls the creatures' dice by hand: a
goblin's attack on Wren asks the DM's screen for the d20 and the damage,
and Wren takes what was typed; then out of sight, a goblin hits Wren and
Ben's screen says so ("…attacks Wren with its Scimitar: it hits, 7
slashing damage.") with no roll of the goblin's in his log.

`tests/e2e/probe.mjs <host.json> dm|player '<expression>'` evaluates an
expression in a page (`window.hexmap.game` is what the page knows).
