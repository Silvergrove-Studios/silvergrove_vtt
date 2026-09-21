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

A pack can also be one file — `{"pack": {…}, "collections": {"creatures":
[…]}}` — which is how packs are exported to share.

**Layering.** Packs load in order: what a plugin ships (its manifest's
`packs`), then the table's own packs under `user://content/`. Within a
collection a later pack's entry with the same id replaces an earlier
one, so a table can override a shipped creature by id; removing the
override brings the shipped one back. Every indexed entry carries
`__pack`, the pack it came from.

**The index.** The Table indexes packs on load: facets over every
top-level scalar and list-of-scalar field (except id, name, text,
description), words over every string field. Queries filter on facets
(equal, or any of a list), match text words by prefix, sort, and page;
they answer in low milliseconds on thousands of entries and never hand a
VM the whole collection. The sort of a whole collection is cached per
sort key until entries change.

**Homebrew.** The Compendium panel copies a shipped entry into the
table's homebrew pack for that plugin (`<plugin>.homebrew`), edits it in
the schema form, saves the pack to `user://content/<pack>/` and can
export it as one file. A plugin may write its own homebrew pack with
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
