# Content packs and character files

Two more documents beside `.hexmap`, `.encounter` and `.campaign`: the
**content pack** a ruleset ships or a table writes (creatures, feats,
spells, cards — whatever the plugin's collections are), and the
**character file** a player keeps on their own device.

## Content packs

A pack is a directory:

```
my.pack/
  pack.json
  creatures.json
  feats.json
```

`pack.json`:

```json
{
  "format": "silvergrove.content", "version": 1,
  "id": "sample.degrees.core",          unique; a table's homebrew is "<plugin>.homebrew"
  "name": "Sample degrees: core",
  "pack_version": "1",                  bump when entries change; actors record what they were built against
  "plugin": "sample.degrees",           whose collections these are
  "provenance": { "source": "…", "license": "CC0-1.0", "attribution": "…", "url": "…" },
  "audience": "all",                    or "gm": a pack players never receive
  "collections": { "creatures": "creatures.json", "feats": "feats.json" }
}
```

Each collection file is `{"entries": [ … ]}` (or a bare array). An entry
is a plain record with an `id` unique within its collection and,
conventionally, a `name` and a `text`; every other field is the
plugin's, described by the schema it declares for the collection
(`hm.schema.define("creatures", …)`), which is what the Table's editor
form is generated from and what homebrew entries are checked against.
Scalars and lists of scalars are indexed as facets, and so are the
scalars inside nested objects, three levels down, under paths like
`stats/level` — queries filter, sort and facet on those paths too.

Players' devices may ask the Table for a page or an entry of any
collection (`need {kind: comp}` in the protocol; `Session.comp` on the
client); they receive what their audience allows — every entry whose
pack and whose own `audience` field are `"all"` (the default). Put a
GM's secrets in a pack with `"audience": "gm"`, or on the entry.

A pack can also be one file — `{"pack": {…}, "collections": {"creatures":
[…]}}` — which is how packs are exported to share.

**What is parsed.** Only the open campaign's content: the rulesets it
plays (its `plugins` list — no other installed ruleset is loaded, so no
other ruleset's packs are parsed), the packs of theirs its settings call
for, and the campaign's own. A plugin's manifest may make a pack
conditional — `"packs": [{"path": "packs/srd52", "when": {"rules": "2024"}},
{"path": "packs/srd51", "when": {"rules": "2014"}}]` — and it is loaded
only when the campaign's settings match (a list of values means any of
them). A ruleset's own tests, `./run.sh schemas` and pack checks read
every pack regardless (`PluginHost.all_packs`).
Nothing else on the machine is read. The table's library under
`user://content/` is where loose packs wait to be imported and where a
pack is exported to; it is opened only when the DM imports from it.

**Layering.** Packs load in order: what a plugin ships (its manifest's
`packs`), then the open campaign's own (its `packs` list, under its
folder), whose homebrew is written there too. Within a
collection a later pack's entry with the same id replaces an earlier
one, so a campaign can override a shipped creature by id; removing the
override brings the shipped one back. Every indexed entry carries
`__pack`, the pack it came from.

**Importing.** `ContentImport` brings a pack directory, a one-file pack
or a file of entries (`{"collection": "spells", "entries": [ … ]}`) into
the open campaign: every entry is checked against the ruleset's schema
for its collection (the entry's id and the failing path are named, and
nothing is copied if one fails), the content is written into the
campaign's `packs/<id>/`, and the campaign records it in `packs` and
`content.imported`. It loads at once, mid-session included.

**The schema contract.** A pack may declare the `content_api` of the
ruleset it was written against, and a ruleset declares its own in its
manifest (`"content_api": 1`, default 1). A pack written for a *newer*
content API than the installed ruleset is refused with the reason; an
older one loads. Within one content API a ruleset may change its
collection schemas only additively — a new optional field, a new
collection, a wider enum; renaming, removing, requiring or narrowing a
field needs a new content API. Fields a Table does not know are kept,
never dropped. `docs/campaign-packages.md` has the whole picture.

**Publishing the shapes.** `./run.sh schemas <plugin dir> <out dir>`
writes each collection's schema as JSON Schema (draft 2020-12) plus
`content-api.json` — the ruleset, its `content_api`, its collections and
its references. A ruleset commits these beside its releases so a pack
author can validate in CI with any JSON Schema tool, and diffs them in
its own CI so a change to a shape is never silent. A ruleset's own packs
should be checked against them too (`ruleset-dnd5e/tools/check_packs.gd`
is the pattern).

**References between collections.** A schema may annotate a string
field with `"collection": "features"`: the ids in it name entries of
that collection. It is an annotation — any JSON Schema tool ignores it —
and Hexmap uses it when content is imported to say what an entry names
that nothing has ("classes/my-warden names features/warden_rage, which
is nowhere"). That is a warning beside the import, not a refusal: the
rest of the pack is good content. In `srd5e` a class's `features[].id`,
its `subclass_of` and a background's `feat` carry it.

**Turning content off.** A campaign may say it does not use an entry
(`content.disabled`). It is hidden from every offer — searches,
pickers, wizards, the Compendium pane's lists — while still answering
by id, so a character already built on it keeps working. `query` takes
`disabled: true` to list them anyway.

**The index.** The Table indexes packs on load: facets over every
top-level scalar and list-of-scalar field (except id, name, text,
description), words over every string field. Queries filter on facets
(equal, or any of a list), match text words by prefix, sort, and page;
they answer in low milliseconds on thousands of entries and never hand a
VM the whole collection. The sort of a whole collection is cached per
sort key until entries change.

**Homebrew.** The Compendium panel copies a shipped entry into a
homebrew pack for that plugin (`<plugin>.homebrew`), edits it in the
schema form, saves the pack into the open campaign's own `packs/`
folder — the campaign lists it, so it comes back with the campaign —
and can export it as one file. A campaign that has never been saved has
nowhere to keep content, and the Table says so. A plugin may write its own homebrew pack with
`hm.comp.put` (the `content` capability). Actors made from entries carry
`packs: {pack id: pack_version}`; when a pack's version changes,
`Compendium.outdated(actor)` says so and the sheet shows it.

## Character files

```json
{ "format": "silvergrove.character", "version": 1,
  "plugins": [ {"id": "sample.focus", "version": "0.1.0"} ],
  "actor": { "id": "a_ana", "kind": "pc", "name": "Ana's rogue",
             "ext": { "sample.focus": { … } }, "packs": { … }, "token": { … }, "audience": { … } },
  "saved": "2026-09-21T…" }
```

An actor on its own, without what a table owns (`owner`, `derived`,
`overlays`). A Player keeps them under `user://characters/` and brings
one to a table with the `character` intent; the Table adopts it as that
player's (the rulesets' schemas check it like any actor), or updates the
one it already has with that id and owner. "Keep on this device" writes
the table's current version back to the file, so the character travels
between tables and stays the player's.
