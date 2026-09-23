# Campaign packages: what a DM downloads

A design for the thing most tables will actually use: not a blank
campaign and a pile of parts, but **a campaign someone else assembled**
— the adventure, its maps, the rules it was written for, the content it
adds, the content it turns off — downloaded as one file, turned into
*their* campaign at startup, and changed from there for as long as they
play it.

Status 2026-09-22: **P1–P6 built.** A campaign's own packs load with it,
entries can be turned off and on, content imports at any time
(schema-checked), campaigns live in a folder of their own, a
`.campaignpkg` can be read, started and exported, and a campaign can be
duplicated. P7 (the author-side schema contract) and P8 (an example
package) are still ahead. It follows `docs/campaign-plan.md` (the
campaign-first Table) and `docs/content-format.md` (packs).

**A package is a template and stays one.** Nothing the table does writes
to a `.campaignpkg`: starting one copies it into a campaign folder, and
that copy is what is played, imported into, saved and autosaved. To
change a package, work on a campaign of your own and export a new
version of it.

**A package carries everything it needs**, the rulesets and the art
included. A DM who has installed nothing downloads one file, starts it,
and plays: the ruleset runs from the campaign's own `rules/`, the maps
draw with the campaign's own `art/`. Exporting a package copies the
rulesets the campaign plays (and anything they depend on) whole, their
content packs and licence files with them, and refuses to write a
package whose ruleset is not on the machine to copy.

**A package can be checked, and says what it holds.** Export writes the
SHA-256 of every file into `package.json` (`files`, and one `digest`
over them all). Before a DM starts a package the Table checks every file
against it, refuses a damaged one by name, and shows what is inside —
the campaign, each ruleset, each art pack, each content pack — with its
version, licence and attribution. This catches damage on the way; it is
not a signature (whoever alters a package can alter its manifest), which
waits for a distribution channel that can vouch for a publisher.

**The author's loop.** *Export as a package…* the first time asks where
the package goes and makes the campaign that package's working copy
(`source_of`: id, version, path, changelog). Every later export asks
what changed, bumps the version (a patch by default) and writes the same
file again with the changelog inside. A campaign started from a package
that is then exported continues that package's id and versions. The
package never carries the author's own play: sessions, runtime, their
party, played or running encounters, the authoring record.

**Updates are offered, never applied.** When a campaign was started from
a package and the library holds a newer version of it, the Table says so
on open, and *Review a newer version of its package…* shows the report —
the changelog since, maps, content and art added or changed, prepared
encounters added, and rulesets whose version differs — before anything
moves. Taking it brings in the new maps, content, art and encounters;
the party, the sessions, the journal and encounters already played stay
as they are, and the rules stay as they are unless the DM chooses to move
them too (`apply_update(…, rules = true)`). Each update is noted in
`package_updates`.

**Art belongs to the campaign.** Adding a map to a campaign copies the
map into its `maps/` (remembering where it came from as `source`) and
the art packs it names into its `art/`; the Table draws with that art
and nothing else, and hands the same art to the players' devices.
Export puts `art/` in the package and lists each art pack's licence in
`package.json`; art whose licence does not allow it to be passed on
(anything but CC0, CC-BY, MIT, ISC, Apache, OFL, BSD, zlib, Unlicense
or public domain, unless its manifest says `"redistributable": true`)
stops the export, by name.

## Three roles

- **The DM who wants to play something.** Downloads a package, picks it
  when starting a campaign, names the campaign, invites players, plays.
  They never think about plugins or packs. Later they want the wizard
  spells from some third-party supplement, or to turn the monk back on
  because a player asked; both are a button.
- **The campaign developer.** Does the onerous work once: chooses the
  ruleset, writes or gathers the content, draws the maps, prepares the
  encounters, decides what of the base rules is in or out, tests it, and
  ships one file. The package is their unit of work and their unit of
  distribution.
- **The DM building from scratch.** Takes the developer's role for their
  own table: starts from the ruleset alone, imports what they like,
  and — if they want — exports the result as a package for someone else.

## What is wrong today

- There is no bundle. A campaign is a `.campaign` file that *references*
  maps by relative path and packs by relative path; moving it means
  moving a folder nobody defined, and sharing it means a zip with a
  README of instructions.
- `campaign.packs` is in the format and **never loaded** — the Table
  loads a plugin's own packs and `user://content`, nothing else. So a
  campaign cannot carry content at all right now.
- Content is all-or-nothing: what a pack ships is in the compendium.
  There is no way to say "this table does not use the monk" and no way
  to change one's mind.
- Importing content means putting a directory under `user://content` by
  hand; there is no import, no validation with a readable error, and
  what you import is global to the app, not to the campaign.
- Copying a campaign means copying a file and hoping about paths.
- A ruleset is installed separately (Rules pane → *Install ruleset…*),
  so a package cannot promise "this is the rules it was tested with".

## Two shapes

**A campaign package** (`.campaignpkg`, a zip) is a *template*, read-only
and redistributable. It is what a developer publishes and a DM
downloads.

**A campaign instance** is a folder with the `.campaign` file and
everything it uses. It is the DM's own; it is what autosaves, what gets
copied, and what can be zipped back into a package.

Instancing a package copies its contents into a new instance folder. The
instance is then self-contained: no path outside it, nothing shared with
another campaign, so copying the folder copies the campaign.

```
The Sunken Reach.campaignpkg          a download
└── (instanced at startup) ──▶  ~/Hexmap/Campaigns/The Sunken Reach/
                                  reach.campaign
                                  maps/…            the package's maps
                                  packs/…           the package's content
                                  rules/srd5e/…     the ruleset it was tested with
                                  handouts/…        images the journal points at
```

## The package

```
reach.campaignpkg (zip)
  package.json
  campaign.json            the starting campaign document (no runtime, no sessions)
  maps/reach.hexmap …
  packs/reach/pack.json …  content this package adds
  rules/srd5e/manifest.json …   optional: the ruleset itself, as its release zip unpacks
  handouts/…
  cover.png
```

`package.json`:

```json
{
  "format": "silvergrove.campaignpkg",
  "version": 1,
  "id": "sunken-reach",
  "name": "The Sunken Reach",
  "package_version": "1.2.0",
  "authors": ["…"], "license": "CC-BY-4.0", "url": "…",
  "description": "A drowned-coast campaign for four characters, levels 1–6.",
  "cover": "cover.png",
  "requires": { "app": ">=2.0.0", "plugins": [ { "id": "srd5e", "version": ">=0.1.0", "content_api": 1 } ] },
  "tested_with": { "app": "2.0.0", "plugins": { "srd5e": "0.1.0" }, "packs": { "srd5e.srd52": "1" } },
  "bundles_rules": true,
  "campaign": "campaign.json"
}
```

- `requires` is checked before instancing: a missing ruleset is offered
  for install from `rules/` when the package bundles it, and named
  plainly when it does not ("needs the srd5e ruleset 0.1.0 or newer").
- `tested_with` is recorded into the instance, so a later "this campaign
  was written for srd5e 0.1.0, you are running 0.3.0" is answerable.
- `bundles_rules` says whether `rules/` is there, and for a package this
  build writes it always is: the download works offline, on a table with
  nothing installed, and pins the rules that were tested. `rules/<id>/`
  is the ruleset's own directory copied whole, so its licence file and
  its content packs travel with it. `requires.plugins` is then only for
  the rare package that deliberately leans on an installed ruleset
  (`bundle_rules: false`), and it is what tells a DM what is missing.

## The instance

The `.campaign` document gains three things (format v3, upgraded from v2
in place):

```json
  "package": { "id": "sunken-reach", "version": "1.2.0", "tested_with": { … } },
  "content": { "disabled": ["srd5e:classes/monk", "srd5e:spells/wish"],
               "imported": [ { "id": "some.supplement", "path": "packs/some.supplement", "version": "2", "at": "session 3" } ] },
  "rules_dir": "rules"
```

- `packs` (already in the format, at last loaded): every pack under the
  instance folder, layered over what the plugins ship, in list order.
- `content.disabled`: entries the table does not use, as
  `<plugin>:<collection>/<id>`. **Suppression, never deletion**: the
  entry stays in its pack, the compendium hides it from search, pickers
  and the character wizard, and unchecking it brings it back exactly.
  An actor already built on a disabled entry keeps working (it is only
  the *offer* that is hidden), and the Table says so when one is in play.
- `content.imported`: what was added after instancing and when, so a
  campaign can explain itself years later.
- `rules_dir`: a ruleset the instance carries. The Table loads it for
  this campaign *in addition to* the installed ones, and prefers it when
  the ids collide, so two campaigns can run two versions of a ruleset
  without a global install.

## What the DM does

| | how |
|---|---|
| **Start from a package** | The campaign picker lists installed packages (with cover, author, description, what it needs) beside the recent campaigns. *New from package…* also takes a `.campaignpkg` from disk. Instancing asks for a name and a folder, copies everything, gives the campaign a fresh id, and opens it. |
| **Turn content off / on** | Compendium pane: a checkbox per entry (and *Disable all of this class* on a class), the disabled ones shown struck through under a *Show disabled* toggle. Also a Content section in campaign settings: the base packs with counts, what is off, what was imported. |
| **Import content** | *Import content…* takes a pack directory, a one-file pack, a `.campaignpkg` (for its packs only) or a single entry file, validates it against the plugin's schemas, copies it into the instance's `packs/`, adds it to `packs` and `content.imported`, and reloads the compendium. Works at any time, mid-session included. |
| **Copy a campaign** | *Duplicate campaign…*: copies the folder, new campaign id, optionally clears players, sessions, journal and runtime ("start it again with a new group"). |
| **Export a package** | *Export as a package…*: writes a `.campaignpkg` from the instance — the campaign document stripped of `runtime`, `sessions`, the journal's private notes and (optionally) the players and their characters, plus the maps, the packs, and the ruleset if the DM says to bundle it. This is how a from-scratch DM becomes a developer. |
| **Update a package** | A newer version of a package a campaign came from: the Table offers to bring in its *content* (maps, packs, prepared encounters not yet played) while leaving the play state alone. Never automatic. |

## Schema stability

Everything above rests on content authored by strangers loading into a
campaign years later. That is a promise about the collection schemas —
what a class, a spell, a feature, an item looks like — and it needs to
be written down and enforced, not assumed.

**The contract.** A ruleset declares a content API version in its
manifest:

```json
  "content_api": 1
```

and a pack declares what it was written against:

```json
  "plugin": "srd5e", "content_api": 1
```

Within one `content_api` a ruleset may only change its collection
schemas **additively**: add an optional field, add a collection, widen
an enum, relax a constraint. Renaming a field, removing one, making one
required, narrowing a type or changing what a field means requires
`content_api: 2` — and the ruleset then either keeps reading `1` packs
(an upgrade step per collection) or says plainly that it cannot.

**What the Table does with it.** A pack whose `content_api` is *newer*
than the plugin's is refused with the reason. A pack that is older loads
unless the plugin says otherwise. A pack with no `content_api` is
assumed to match (packs that exist today). Unknown fields in an entry
are kept and ignored, never dropped — a v1 Table must round-trip a v2
author's entry without eating it.

**Validation.** Entries are validated against the plugin's schema at
three moments, with the entry's id and the failing path in the message:
on import (refuse the pack, list the bad entries), on write from the
Compendium editor (today's behaviour), and on pack load (a warning in
the Rules pane, not a refusal — a table mid-session is not the place to
lose content).

**Authoring offline.** A content author cannot be asked to run the Table
to check their work. `./run.sh schemas <plugin dir> <out dir>` writes
each collection's JSON Schema, plus a `content-api.json` naming the
plugin, its `content_api` and its collections — files a pack repository
can commit and validate against in CI with any JSON Schema tool. The
`srd5e` ruleset publishes these with each release, and its own packs are
validated against them in its CI.

**Documentation.** `docs/content-format.md` gains the rules above; each
ruleset documents its collections' fields (the schema is the source of
truth, the doc is the prose). `srd5e` freezes `classes`, `spells`,
`features`, `items`, `magic_items`, `feats`, `creatures`, `species`,
`backgrounds` and `conditions` at `content_api: 1` with this release.

## Steps

| # | step | done when |
|---|---|---|
| ~~**P1 Campaign packs load**~~ | **done**: `campaign.packs` load with the campaign (after the plugins' and `user://content`, so the campaign wins by id); `TableContext.load_campaign_packs()`. | `rules_content.gd::test_campaign_content` |
| ~~**P2 Content toggles**~~ | **done**: `content.disabled` on the campaign, `Compendium.disabled` filtering every query (`disabled: true` asks for them anyway) while by-id lookups still answer; the Compendium pane's *Use at this table* and *Show what is off*. | `rules_content.gd` (both tests) |
| ~~**P3 Import**~~ | **done**: `ContentImport.inspect/import_into/write_pack` (a pack directory, a one-file pack, a file of entries), schema-checked per entry, `content_api` gate, copied into the campaign and recorded; *Import content…* in the Compendium pane. Left for P5: importing a `.campaignpkg`'s packs. | `rules_content.gd::test_campaign_content` |
| ~~**P4 The instance folder**~~ | **done**: campaigns are made in `App.campaigns_dir()` (`~/Documents/Hexmap/Campaigns/<name>/`, the `campaigns_dir` preference moves it), a folder each; a loose `.campaign` still opens; `rules_dir` adds a campaign-carried ruleset, which wins over an installed one of the same id. | `table.gd::test_campaign_packages` |
| ~~**P5 Packages**~~ | **done**: `CampaignPackage.read/unmet/instance/export_from`; *New from a package…* in the File menu and the picker, which lists what is in `user://packages` with what each needs; *Export as a package…*. | `table.gd::test_campaign_packages` |
| ~~**P6 Duplicate**~~ | **done**: `Campaign.duplicate_to(source, dest, name, fresh)` — the whole folder, a new id, and with `fresh` none of this group's play; *Duplicate this campaign…* in the File menu. | `table.gd::test_campaign_packages` |
| ~~**P7 Schema contract**~~ | **done**: `content_api` in manifests and packs with the refusal rule (P3), `./run.sh schemas` publishing JSON Schema + `content-api.json`, the `collection` annotation and the missing-reference report on import, `srd5e` frozen at content API 1 with its schemas committed and checked in CI (`tools/check_packs.gd`). | `rules_content.gd`; the ruleset's CI |
| **P8 The 5e package** | A small example package in `ruleset-dnd5e` (or its own repo): a two-map starter with a prepared fight, built on `srd5e`, exported by the export path itself. | it instances on a clean machine and plays |

Order: P1 → P2 → P3 (the three that make a live campaign ownable), then
P4 → P5 → P6 (distribution), P7 beside P3 (it is the import's contract),
P8 last as the proof. P7's enforcement half (a pack declaring the
`content_api` it was written for, refused when it is newer than the
ruleset) came with P3; what is left is the authoring half — publishing
the schemas, freezing `srd5e`'s collections, and the prose.

## Decisions

- **A package is a zip, not a folder.** One file downloads, one file
  is checksummed, one file is what a marketplace would carry.
- **Instancing copies.** Nothing is shared between instances, so a
  campaign cannot be broken by another campaign's import, and a folder
  copy is a real copy. The cost is disk (a few MB of JSON, plus maps).
- **Suppression, not deletion.** Turning content off is a campaign-level
  view over the compendium, reversible, and never edits a pack.
- **Campaign-scoped content, and nothing else parsed.** A campaign
  parses the rulesets it plays, their packs and its own — another
  installed ruleset is not loaded at all, and the table's library under
  `user://content` is only read when the DM imports from it. Imports and
  homebrew land in the campaign's folder. A campaign that has not been
  saved has nowhere to keep content yet, and is told so.
- **A package carries its rules.** It is one download that plays: the
  ruleset it was tested with travels inside it and runs for that
  campaign only, so two campaigns may run two versions of a ruleset and
  a table needs nothing installed.
- **Campaigns live in a managed folder** by default
  (`~/Documents/Hexmap/Campaigns/<name>/`), listed by the picker, and can
  still be opened from anywhere (P4).
- **A ruleset is copied whole, not filleted.** It keeps its own release
  cycle and its own licence notices, and a package that carries it
  carries those too — `rules/<id>/` is the ruleset's directory verbatim.
