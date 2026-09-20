# Plugin API desirements

What a ruleset plugin needs from Hexmap, ranked. This is the joint list
distilled from three independent per-ruleset studies (a class-and-level
game with initiative, a card-and-narrative game with no initiative, and a
tactical game with deep automation) plus a set of *growth* desirements —
things DMs reach for that no current tool does well. Nothing here names a
game; a capability that only one ruleset needs is still listed, because the
point of the exercise is to find the API that lets *any* ruleset be a plugin.

Licensing of rules content is deliberately out of scope for this document.
Each study recorded what its source material permits; those findings stay
with the studies and will matter when a plugin ships data, not when we
design the API.

## How to read this

- **Tiers.** *Must*: a ruleset plugin cannot exist without it. *Should*:
  every table expects it; the difference between usable and good. *Could*:
  large payoff for some tables. *Later*: real, but not blocking.
- **Ranking** runs within a tier, most valuable first.
- **Capability tags** name the part of the API each item leans on:

  | tag | meaning |
  |---|---|
  | `schema` | a data model the plugin declares and the host stores under `ext.<plugin_id>` |
  | `derive` | plugin-computed fields the host recomputes and republishes on change |
  | `hooks` | lifecycle points where the host asks the plugin, with a modifiable payload |
  | `dice` | the roll service |
  | `effects` | records attached to tokens/actors that change numbers and expire |
  | `turn` | the `TurnSystem` strategy |
  | `state` | shared non-token state at encounter or campaign scope |
  | `comp` | compendium: shipped and user packs |
  | `ui` | declarative forms, sheets, panels, cards, widgets |
  | `prompt` | Table → Player questions with ids and deadlines; Player → Table intents |
  | `map` | queries and placement on the map (never rules in the map) |
  | `clock` | time other than turns: scenes, rests, sessions, days |
  | `events` | the typed, reversible event log |
  | `net` | what Player clients render and may request |
  | `packs` | import/export, versioning, provenance |

- **Standing constraints** (from `docs/encounter-format.md` and the plugin
  plan): plugins run only on the Table; Player clients render plain data and
  never run plugin code; plugins change state by emitting events, never by
  mutating the map; the map and tokens carry no rules; plugin data lives
  under `ext.<plugin_id>`; the plugin language is sandboxed Lua.

---

## Part 1 — Primitives

The three studies converged on the same small set of things the host must
provide. Every feature in Part 2 is built from these, so they are ranked
first. If the host gets these right, a ruleset plugin is mostly data plus
small Lua; if it gets them wrong, every plugin re-implements them badly.

### P1. Ask, don't tell: a complete hook lifecycle — `hooks`
The host calls the plugin at every moment a rule could apply, with a payload
the handler may **modify, veto, or extend** (add a modifier, change an
outcome, queue a follow-up), in a deterministic handler order. Minimum
lifecycle: `before/after_roll`, `before/after_attack`, `before/after_damage`,
`on_hp_change`, `on_turn_start/end`, `on_round_start/end`, `on_focus_changed`,
`on_token_moved`, `on_token_entered/left_region`, `on_template_placed`,
`on_effect_applied/expired`, `on_item_equipped`, `on_rest(kind)`,
`on_session_start/end`, `on_time_advanced`, `on_actor_changed`,
`on_scene_entered`. Hooks must be **resumable**: a damage or rest flow may
pause for a Player decision (P9) and continue.

### P2. A derivation layer on actors — `derive`, `schema`
The plugin declares computed fields (defences, modifiers, thresholds, DCs,
carrying limits, speeds) and a `derive(entity)` function; the host
recomputes whenever a dependency changes (source data, equipment, effects,
overlays, conditions) and republishes the result to Players. Sheets and
Player clients never compute rules. Overlays (a transformation, a stance,
an alternate form) stack on an actor and revert cleanly.

### P3. Typed numbers — `derive`, `dice`
Every number the host carries for a plugin is a breakdown, not a scalar:
`{total, parts: [{label, type, value, source}]}`. This lets the plugin apply
its own stacking rules (best-of-type, non-stacking, override) and lets
Players see *why*.

### P4. Effects as first-class records — `effects`, `turn`, `clock`
An effect has an icon, a source, an optional **numeric value** (rendered as
a badge), a list of changes to actor keys with modes
(add/multiply/override/upgrade), optional hook registrations (so it can
alter rolls, not only stats), a stacking policy (stack / highest wins /
none), and a **duration** in any of: rounds, turns relative to a specific
combatant (start/end of X's next turn), until a check succeeds, until a
linked effect ends, until cleared, scene, rest, long rest, session, real
time. The TurnSystem and the clock drive expiry. Effects live in the
encounter overlay keyed by token, never in the map. Auras apply an effect to
whatever is within a distance of a token.

### P5. Structured dice — `dice`, `events`
A roll returns individual die faces with kept/dropped/rerolled flags, the
evaluated total, and the expression; dice within one roll can be **named**
and **themed** so a client can render "the hope die" differently from "the
fear die"; rolls carry a **type** (check, attack, damage, save, reaction,
secret, flat) and a **visibility** (all, owner, GM, blind); the plugin can
attach an **outcome classification** (pass/fail, four degrees, six-way,
custom label) in a post-roll hook; post-roll transforms are allowed within a
window (reroll with substitution, keep-best-of-two, spend a resource to
bump). Rolls resolve on the Table with a seed so tests are deterministic.
**Pending rolls**: a roll may collect contributions from *other* Players
(help dice, joint actions) before it resolves. Physical dice: any roll may
be satisfied by a typed-in result instead (see G2).

### P6. Turn strategies — `turn`
`TurnSystem` is a strategy the plugin supplies, not a list the host owns.
Two shapes must both be first-class:
- **Ordered**: initiative from a plugin-chosen statistic, tie-break policy,
  rounds, insertion at arbitrary positions, delay/ready, grouping, hidden
  entries, per-combatant counters (actions, reactions, penalties) with
  `consume`/`has` queries, off-turn prompts (reactions, saves).
- **Focus-holder**: no order and no rounds; a current holder that can be any
  actor or "the GM"; Player *requests* for focus; GM grant/seize; moves
  triggered by roll outcomes; per-participant counters and a history of who
  has not had focus recently.
Plus the app's own free / DM-select / ordered modes for *who may move
tokens* remain a separate, host-owned choice. Effect durations (P4) must be
expressible in both shapes.

### P7. Resources and slot tracks — `schema`, `ui`
A generic **pool** `{current, max, recharge: rest|long_rest|session|day|
turn_start|roll(expr)|manual}` used for spell slots, charges, uses per day,
tokens on a card, hero points, legendary actions. And a **slot track**
`{max, marked, permanent_extra, crossed_out}` with mark/clear/cross-out
operations, undo, and a tap UI — for hit boxes, stress, armour slots, hope,
advancement grids. Resources can live on any entity: actor, item, card,
adversary, scene, campaign. Refills are driven by P1's rest/turn/time hooks.

### P8. Shared state beyond tokens — `state`, `events`
Encounter-scoped and campaign-scoped records that belong to no token: a GM
resource pool, countdowns and clocks, shared token pools between
adversaries, an environment or hazard "actor" with no token, party position
on a hex map, faction tracks, per-session counters. Every change is an event
with a **reason** (which roll, which feature) so logs and undo work, and
each record declares its **audience** (GM, owners, everyone).

### P9. Prompts and intents — `prompt`, `net`
Table → Player: a prompt with an id, a declarative form (P10), a deadline
and a GM override, sent to one Player, some, or all; the answer resumes the
hook that asked (P1). Player → Table: a fixed vocabulary of **intents** —
roll (with dialog answers), use action X on target Y, mark/clear a slot,
move a card, spend a resource, join someone's pending roll, request focus,
end turn, pick up/transfer an item, answer prompt N, propose a move. The
Table validates every intent against the plugin and per-field permissions;
nothing is applied client-side.

### P10. Declarative UI on three surfaces — `ui`
Sheets, forms, wizards, panels, chat cards, trackers and prompts described
as data and rendered natively on the Table, on the phone Player client, and
in the log. Required widgets: tabs/sections/fields, repeaters (features per
level), computed labels, roll buttons, action bars with **cost glyphs** and
enabled-state, compendium pickers, conditional fields and validation
messages, list/detail browsers with facets, **cards** (face, zones such as
hand/loadout/vault, drag with cost confirmation), **slot grids**, **progress
trackers** placeable on the map, and multi-step wizards. Homebrew editors
fall out of record definitions for free (P11). A Player client of version N
must render a plugin of version N+1 gracefully: unknown widgets degrade to
text.

### P11. Compendium: schema-validated, layered, indexed — `comp`, `packs`
Typed collections with JSON schemas, stable ids, per-entry provenance
(source, version, license) and a rules-version tag; shipped read-only packs
with user packs layered on top (override by id); full-text and faceted
search served **paged and indexed by the host** (a compendium can be tens of
MB and must never be loaded into the Lua sandbox wholesale); entries
referenced by id from actors so a pack update does not break characters,
with an explicit "update instance to latest" operation; import/export of
packs and single records as JSON with attribution carried in metadata.

### P12. Map queries, not map mutation — `map`
`distance(a, b) → {units, band}` honouring token size, reach and a
plugin-registered band table and diagonal rule; templates (burst, cone,
line, emanation, band radius) placed from a point or a token with the
origin rules the plugin chooses, returning the cells and tokens covered;
line-of-sight and **cover classification** against walls, doors and tokens;
light level at a point; per-token vision profile and attached light
sources; **regions** with tags (difficult terrain, trigger, zone) and
enter/leave hooks; **zones** — a placed template that persists with an
effect and a duration; spawn/replace/remove tokens and props linked to
actors; child/attached tokens (mounts, vehicles) that move together; hex
adjacency and **per-hex plugin state** with GM-only vs revealed layers;
rulers and auras labelled by the plugin. All changes are events the map
applies.

### P13. A second clock — `clock`
Scenes, rests, sessions, days, and in-game calendar time as a host object
the plugin can read, advance and subscribe to. Needed for durations longer
than a fight, daily resets, afflictions, travel, downtime and projects.

### P14. The typed event log with undo — `events`
Every rules outcome is an event with a schema (roll, attack, damage, heal,
effect, focus change, resource change, card move, rest, level-up, prompt
answered) and an audience. The log, Player clients, animations, recaps and
other plugins subscribe. Undo is compensating events; the GM can undo any
plugin-emitted change from the log.

### P15. Plugin manifest, permissions and tests — `packs`
A manifest with id, version, dependencies on other plugins, attribution and
compatibility text, and **declared capabilities** (needs network to these
hosts, needs file import, writes campaign state) that the DM sees and
approves. Plugins ship **self-tests** (fixed seeds, fixture actors, expected
outcomes) runnable in Hexmap's existing self-test mode, and a harness where
a plugin can simulate rolls and assert on emitted events. The common cases
(a feature with a cost and an effect; a card that spends a resource and
rolls) should be expressible as data with small Lua expressions, full Lua
reserved for the long tail.

---

## Part 2 — Features

What DMs and players buy, install and ask for, merged across the three
studies and stated without reference to any one game.

### Tier 1 — Must

#### 1. The character sheet — `schema` `derive` `ui` `net` `dice`
View, edit and roll from one sheet whose every derived number is computed on
the Table (P2) and rendered on the phone. Owners edit their own; the GM sees
all; field-level visibility flags. Tappable resources and slot tracks (P7).
The sheet is the product on every platform and "character sheets" is the
number-one gap named by users of every rules-light VTT.

#### 2. Dice with the ruleset's semantics — `dice` `ui` `prompt` `events`
Roll dialogs as declarative forms (choose statistic, situational bonus,
spend a resource, add help), outcome classification supplied by the plugin,
roll requests pushed to specific Players and answered as intents, GM-private
and blind rolls, a roll history everyone can see. (P5)

#### 3. The compendium, browsable and drag-droppable — `comp` `ui`
Search and filter every content type; drag entries onto sheets, tokens onto
maps, abilities into lists. Shipped packs plus user packs of the same shape,
rules-version tags, and a player-facing subset (no secret stat blocks). (P11)

#### 4. Turn tracking in the ruleset's shape — `turn` `hooks` `net`
Ordered or focus-holder (P6); grouping; hidden entries; start/end-of-turn
triggers; a Player-visible order or holder with "my turn" highlighting and
an end-turn / request-focus intent; per-turn budgets shown as an action bar.

#### 5. Conditions and effects on tokens — `effects` `hooks` `turn` `net`
A plugin-defined condition registry (icon, value, mechanical flags, clearing
rule, stacking policy); effects that change numbers *and* alter rolls; turn-
and clock-driven expiry; concentration-style linked effects; numeric badges
on tokens; Players see their own effect list with remaining durations. (P4)
This is the single biggest automation differentiator in every marketplace.

#### 6. Resources, casting and recharge — `schema` `ui` `hooks` `effects`
Pools and slot tracks (P7) for slots, points, charges, uses and card tokens;
casting entries of several kinds (prepared, spontaneous, innate, focus,
ritual, item-bound) with scaling by level or slot; areas as templates;
durations with sustain reminders and expiry; refills on rest, day, session
and turn start.

#### 7. Damage, healing, and going down — `hooks` `prompt` `effects` `events`
A damage pipeline the plugin implements over host hooks: typing, resistance
and vulnerability, thresholds or subtraction, temporary points, a **Player
decision point** (spend armour? which death move?), dying/wounded/stabilise
progression, massive damage, undo per target. Multi-target attacks resolve
per target from one roll. Rests as a multi-player flow with per-Player
choices and GM-side consequences. (P1, P9)

#### 8. Stat blocks on the map — `schema` `comp` `map` `ui` `net`
Drop a compendium creature as a token with its sheet attached; roll its
actions from a compact GM panel whose buttons check and deduct costs;
numbering of duplicates; hordes and minion groups as one bar; elite/weak
and tier re-scaling; **non-token actors** (environments, hazards, shared
pools) at scene scope (P8); GM-only fields per token.

#### 9. Homebrew editors for every content type — `ui` `comp` `packs`
Form-based create/edit for every record type the plugin declares —
species, backgrounds, feats, subclasses, features, spells, cards, items,
creatures, hazards, conditions, effects — with the same schema as shipped
entries so home-made content behaves identically; guided pickers rather
than raw JSON; save to user packs; export and share. On every platform the
loudest complaint is "I can't add my own"; for a plugin shipping only
open-licensed data it is how a table gets the rest of its rules in.

#### 10. The phone as the player's device — `net` `ui` `prompt`
The Player client renders the computed sheet, action bar with cost glyphs,
resources, hand of cards, inventory, conditions, the turn order or focus,
shared trackers, the log, and prompts — all as plain data — and sends only
intents (P9). Structurally this is what no incumbent has: a real rules
engine driving a phone-first client with a light Table.

### Tier 2 — Should

#### 11. Character creation and level-up wizard — `ui` `comp` `schema`
Multi-step, data-driven from compendium queries (the plugin declares what is
chosen at each level and the constraints), with prerequisites, dependent
option lists, slot-grid advancement pickers, homebrew flowing through the
same wizard, and a summary to the log. Runnable for many characters at once.

#### 12. Attack and action workflow with targeting — `map` `dice` `hooks` `ui` `net`
Select attacker and target(s) on the map (or on the phone), check range,
reach and cover, roll against a hidden defence on the Table, apply damage
through item 7, prompt follow-ups (concentration, reactions), all in one
progressive card with apply/undo buttons — **with every step individually
switchable** between roll-only, roll-and-compare and roll-compare-apply.
Multiple-attack penalties and other per-turn counters from P6.

#### 13. Encounter builder with a difficulty budget — `comp` `ui` `map` `schema`
Party size and level → budget; browse creatures by level/tier/type/role;
live totals and a threat read-out; environments and hazards; save as a
preset; deploy to a scene in one action; live re-balance mid-fight (add
reinforcements, toggle elite/weak).

#### 14. Inventory, equipment and currency — `schema` `derive` `ui` `net`
Items with quantity, weight or bulk, equipped/held/stowed slots and hands,
containers, attunement or investment limits, upgrades (runes, materials)
feeding derived stats, currency with denominations and conversion, coins as
tiers where the ruleset prefers it, consumables that use up, transfer
between Players via the Table.

#### 15. Templates, ranges and bands — `map` `ui` `net`
Areas placed from ability data with the ruleset's origin rules; affected
cells and tokens highlighted and auto-targeted; distances reported in units
*and* in named bands; rulers and auras labelled accordingly; flanking and
cover hints; movement advisory ("further than X needs a roll") rather than
enforced. (P12)

#### 16. Vision and light from the sheet — `map` `effects` `net`
Senses (range, mode, precision) and carried or cast light sources set from
actor data and effects; scene light levels; per-observer detection states
(seen / concealed / hidden / undetected) available to the roll pipeline;
Player clients see what their token sees.

#### 17. Movement and combat helpers — `map` `turn` `effects` `hooks`
Speed from the sheet minus effects; movement budget (where the ruleset has
one) with colour-coded reach; difficult terrain and hazard regions; leaving-
reach prompts; one-click stances and manoeuvres as effects; mounted and
attached movement.

#### 18. The shared log with cards, whispers and undo — `events` `ui` `net`
Structured cards for rolls, damage, condition changes, resource changes,
card moves, focus changes and rests; whispers and per-audience visibility;
buttons on cards (apply, save, undo); GM undo of any plugin change. (P14)

#### 19. Rules variants and campaign settings — `schema` `hooks` `comp`
Per-campaign toggles the plugin declares (rules edition, optional rules,
automation levels, house rules) that the pipeline consults, with mixed-
edition content allowed and a rules-version filter on the compendium.

#### 20. Party overview and group actions — `ui` `schema` `dice` `net`
One GM panel with every PC's key numbers, senses, conditions and resources;
group checks; rewards split (XP, currency, loot) pushed to Players; travel
pace; exploration activities per PC feeding initiative.

#### 21. Progress tracks, countdowns and subsystems — `state` `ui` `hooks` `net`
A generic **progress track** primitive (value, start, direction, kind:
manual / per-roll / per-outcome / per-rest / linked / looping, visibility,
"what happens at zero") used for countdowns, clocks, victory-point
subsystems (influence, research, chases, infiltration), project work and
faction objectives; auto-advanced from roll-outcome and rest hooks; a
compact widget on the map and on phones. (P8) One primitive covers what
three rulesets implement three ways.

#### 22. Rest, downtime and the day — `clock` `hooks` `prompt` `ui` `dice`
Rest kinds with per-Player choices, refills, expiries and GM consequences;
daily preparation; downtime activities (earn, craft, train, research,
recover) driven by level-based DC tables; projects as progress tracks;
in-game date and time advancing by rest and travel. (P13)

#### 23. Companions, summons and alternate forms — `schema` `map` `turn` `effects`
Sub-actors linked to an owner (companions, familiars, summons) that act on
the owner's turn and spawn/despawn with events; **overlays** on an actor
for shapeshifting and transformations with a clean revert (P2).

### Tier 3 — Could

#### 24. Afflictions and staged effects — `effects` `clock` `turn`
Poisons, diseases, curses: onset, interval saves, stages with their own
conditions and damage, maximum duration; badge shows stage.

#### 25. Loot, item piles and merchants — `map` `schema` `ui` `net` `dice`
Loot containers on the map Players open; rollable treasure tables by level
or rarity; identify/unidentified names for Players; merchants with stock,
price modifiers and availability caps; party stash; coin splitting.

#### 26. Traps, hazards and zones — `map` `hooks` `effects` `dice`
Hidden props with trigger regions; token-enters-region hooks; zones that
persist with an effect and a duration (P12); complex hazards with routines
on the turn order; environmental effects as scene-scoped effects.

#### 27. Secret checks and partial reveals — `dice` `net` `map`
Player-triggered rolls the Table resolves hidden; graded reveals of creature
knowledge to one Player; seek/search within a template.

#### 28. Settlements, factions and NPC directory — `schema` `ui` `state`
Settlement records with availability rules for merchants; faction and
relationship tracks (P8); an NPC directory linking to tokens and journal
entries.

#### 29. Journal, handouts and read-aloud — `schema` `ui` `net`
Session notes, quest log, handouts pushed to some or all Players, read-aloud
boxes, secret DM notes, `@compendium` links that pop over on the phone.
Mostly host-level; the plugin needs link resolution.

#### 30. Animation and audio hooks — `events` `map` `net`
Plugins emit `effect:play` with an asset id and target; a presentation layer
(and Player clients) render it. The plugin never owns rendering.

#### 31. Macros and table-level scripting — `hooks` `ui`
Small user Lua snippets bound to sheet buttons or chat commands, sandboxed
exactly like plugins, so a table can add a house rule without forking.

#### 32. Import from external builders — `packs` `comp` `schema`
Read the popular character-builder export formats into the plugin's schema
with fuzzy matching and flagged unknowns; allow-listed HTTPS fetch of a
share code as an explicit manifest capability (P15).

#### 33. Localisation — `ui` `packs`
Label keys in UI schemas; string tables in plugin data; community
translations as packs.

### Tier 4 — Later

#### 34. Vehicles, mass combat, strongholds and domain play
Sheets for things that carry tokens; turn phases longer than a round; large
project trackers. Mostly items 21–23 plus custom schemas.

#### 35. Organised-play records and printable output
Chronicle-style session records; printable sheets and cards.

#### 36. Migrations between rules editions
Name maps and record transforms so imported legacy characters resolve
against current packs; a generic "migrate pack/actor" operation (P11).

#### 37. AI assistants
Stat block from a prompt, rules Q&A over the compendium. A separate plugin
talking to the same compendium, if ever.

---

## Part 3 — Growth desirements

Things DMs think about that the marketplace surveys under-represent — either
because nobody does them well or because they only become possible once the
primitives above exist. Ranked by how much a DM would notice them.

### G1. The hybrid table: a TV and phones — `net` `ui`
A **display client** mode: the map full-screen with no controls, on a TV or
projector at a physical table, showing only what Players may see; phones as
sheets; the DM's laptop as the Table. This is how many groups actually
play, it needs nothing but a third role, and no incumbent treats it as a
first-class mode. Includes a QR/code join for the phones.

### G2. Physical dice — `dice` `prompt`
Every roll can be satisfied by typing in the result of real dice. The
pipeline (classification, modifiers, follow-ups) runs the same; only the
random step is replaced. Half of in-person tables will not give up their
dice; this keeps them inside the automation.

### G3. Prep that fires during play — `map` `hooks` `state` `events`
Attach prep to map regions and scenes: read-aloud text, tokens to spawn,
lights to change, a countdown to start, a handout to push — triggered when
the party enters, a door opens, or the DM presses one button. The most
installed automation module on the biggest platform is exactly this; it
belongs to the host with the plugin contributing the rules half.

### G4. Improvisation tools — `comp` `schema` `ui`
"Give me a level-4 brute right now": stat blocks from the ruleset's
benchmark tables with one slider; quick adjust of any number on a token;
number-only tokens for the fight nobody planned; a name generator. DMs
improvise every session and tooling assumes they prepared.

### G5. Checkpoints and rewind — `events` `state`
Name a checkpoint before the fight; restore to it. Undo already exists as
compensating events (P14); this is the coarse-grained version, plus a
"what happened since" diff for the log.

### G6. Session recap — `events` `packs`
Generate the recap for next session from the event log: who fought what,
what was found, what changed, in Markdown the DM can edit and hand out.
Free once P14 exists; nobody offers it.

### G7. Audience as a first-class concept — `net` `events` `state`
One model for who may see what: every record, event, prompt and field has
an audience (GM, owners, some players, all). Whispers, secret rolls,
mystified items, hidden combatants, partial reveals and GM-only fields are
then one rule, not seven features.

### G8. Theatre of the mind — `ui` `state`
The Table and Player clients must be fully usable with **no scene at all**:
sheets, turn/focus, trackers, log and prompts. A great many sessions have
no battle map, and those groups still want the rules engine.

### G9. Random tables as a primitive — `comp` `dice` `ui`
Rollable tables with weights, nested tables, ranges and text templates,
usable for loot, rumours, encounters, weather, names and anything a DM
keeps in a binder; shipped in packs, authored in the homebrew editor,
rolled from anywhere.

### G10. Plugin layering and dependencies — `packs` `hooks`
A ruleset plugin, a setting pack, and a house-rules plugin that overrides
two hooks — installed together, with declared dependencies and a defined
override order. Tables customise rulesets far more than they replace them.

### G11. Campaign persistence across encounters — `state` `schema` `clock`
Characters, party inventory, resources that carry between sessions, and
campaign-level trackers live in a **campaign** document, not in any one
encounter; encounters reference it. Today's `.encounter` is a session; the
campaign is the thing the group keeps for two years.

### G12. Player-owned characters — `packs` `net`
A character lives on the player's phone as a file and is contributed to a
Table on join; the Table validates it against the plugin and owns it while
the session runs; the player takes it home. Groups change DMs, play in
several groups, and want their character to be theirs.

### G13. Bulk operations — `map` `effects` `prompt`
Apply damage to everything in a template, add a condition to all selected,
roll a save for a group and apply per result, advance a horde as one. Every
fight with many enemies is bookkeeping without it.

### G14. Live encounter feel — `ui` `state` `events`
A running read of the fight for the DM: damage dealt and taken per side,
resources left, expected rounds remaining — so the DM can decide to add
reinforcements or end it. Also fun for players afterwards.

### G15. Persistent zones — `map` `effects` `hooks`
Spell and hazard areas that stay on the map for a duration with an effect
and enter/leave/turn-start hooks (fog, grease, fire, difficult ground).
Listed under P12; called out here because DMs track these on scrap paper
today.

### G16. Contextual suggestions for new players — `ui` `net`
"You can: attack, move, use X (1 action)" — the action bar filtered by what
is legal now (budget, range, resources), with the plugin supplying the
predicate. Turns onboarding into UI rather than a DM lecture.

### G17. Roles beyond DM and Player — `net`
Co-GM (full Table view on a second device), spectator/display (G1), and
DM-controlled absent PCs; token ownership transfer during a session.

### G18. The rulings journal — `state` `ui`
"We ruled that X" with a link to the rule and the roll that prompted it,
searchable next session. Tables argue about the same ruling twice because
nobody wrote it down.

### G19. Art and token library — `comp` `map`
Token art bound to compendium entries and to packs; a portrait shown to
Players when a creature is revealed; quick token from an image.

### G20. Accessibility — `ui` `dice`
Named dice are also *labelled* dice (not colour alone); larger UI scale is
already in the app; screen-reader-friendly sheets follow from declarative
UI if we keep semantic roles in the schema.

---

## Part 4 — What this implies for the order of work

1. **P1, P2, P3, P4, P5, P7, P14** first: hooks, derivation, typed numbers,
   effects, dice, resources and the event log. With these a plugin can do
   items 1, 2, 5, 6 and 7 end to end.
2. **P6** with both shapes, then item 4. The focus-holder shape is the test
   that nothing is hard-coded.
3. **P9 and P10** together, then item 10: prompts, intents and declarative
   UI are what put the plugin on a phone.
4. **P11**, then items 3, 8 and 9: the compendium, stat blocks and the
   homebrew editors that fall out of the same schemas.
5. **P12, P13, P8**: map queries, the second clock and shared state, which
   unlock most of Tier 2 and Part 3.
6. **P15** early enough that every plugin written during this phase ships
   with tests.

Sources: three per-ruleset studies in the `ruleset-*` repositories of the
Silvergrove-Studios organisation.
