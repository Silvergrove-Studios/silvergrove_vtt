# Packaging: an audit, and what it leaves open

Written 2026-09-23, after P1–P7 of `docs/campaign-packages.md` were
built. The design has been growing a step at a time; this is a read of
the whole of it against the code, the holes it has, and the questions
whose answers change what gets built next.

## What is actually true today

| | state |
|---|---|
| A campaign is a folder | yes — `<campaigns>/<name>/<name>.campaign` plus `maps/`, `packs/`, `rules/`; a loose `.campaign` still opens |
| It parses only its own content | yes — the rulesets its `plugins` names, their packs, its own packs; nothing else on the machine |
| A package is one archive | yes — a zip: `package.json`, `campaign.json`, `maps/`, `packs/`, `rules/<id>/` |
| A package carries its rules | yes — the rulesets the campaign plays, copied whole, licences included; export refuses if one is not on the machine |
| A package is immutable | yes — play never writes to it; starting one copies it out |
| Content can be turned off | in the compendium, yes; **in a ruleset's own lists, no** (see A1) |
| Content can be imported later | yes — pack folder, one-file pack, entry file; schema-checked; into the campaign |
| Shapes are published and frozen | yes — `srd5e` content API 1, schemas committed, CI diffs them |
| Campaigns can be copied | yes — `Campaign.duplicate_to`, with a "fresh start" mode |

## A. Holes in what we have built

**A1 (closed 2026-09-23). Turning a class off does not turn it off.** The Compendium hides
a disabled entry from searches and pickers, but `srd5e`'s character
wizard lists classes, species and backgrounds from **constants in Lua**
(`D.CLASS_ORDER`, `D.SPECIES`, `D.BACKGROUNDS`), not from the
compendium. So a campaign that disables the monk still offers the monk
in the wizard, and `create_character` still finds it by id and builds
it. The same cut stops an *imported* class from ever appearing in the
wizard. This is the DM-facing promise of the whole content story and it
is not kept. It is Hexmap gap **G9** (a `picker` field inside a form or
wizard step, so options come from a live query) plus a rule about
whether a disabled entry may still be *used* by id, not only offered.

**A2. A package does not carry the art its maps need.** A `.hexmap`
records the **art packs** it draws from (`{"dungeons_and_castles":
"0.1.0", "woodland": "0.1.0"}`) and names assets as `pack:asset`. Art
packs live in app preferences (`pack_dirs`), are global, and are not in
the package. Download a package on a clean machine and its maps render
without their terrain and props. "Everything it needs" is not yet true.

**A3. Art packs are app-global while everything else became
campaign-scoped.** After the content change, rules content belongs to
the campaign and nothing else is parsed — but art is still whatever the
app has, shared by every campaign, in a preference. The two halves of
"what a map/table needs" now follow different rules.

**A4. Getting a package in is manual.** The picker lists
`user://packages`; a downloaded file lands in Downloads and the DM must
move it or find it through a file dialog. There is no "install this
package" action, no association for `.campaignpkg`, no open-with.

**A5. No way to move to a newer ruleset, and no way to update a
package.** A campaign pins the rules it came with, which is what we
want — but nothing offers "this package has a 1.3.0, bring in its new
maps" or "srd5e 0.2.0 fixes a bug, move this campaign onto it". Both are
in the design as prose only.

**A6. Duplicate's "fresh start" is not offered.** `duplicate_to` takes
`fresh` and the tests use it; the menu always passes false.

**A7. Homebrew moves between campaigns only by hand.** *Export pack…*
writes to the library, *Import content…* reads from it. That is the
whole path — no "copy this class into my other campaign".

**A8. Handouts are text.** The design's `handouts/` folder has nothing
that writes to it: the journal's handouts are prose, and a package
cannot carry an image, a map of the region as a picture, or a PDF.

**A9. Doc drift.** `docs/campaign-format.md` documents `content` but
not `package` or `rules_dir`, both of which the code writes.

## B. Tensions in the design itself

**B1. Two things are called a pack.** Art packs (terrain, props, tokens)
and content packs (spells, classes) share the word, the `packs/` folder
name and a `pack.json`. A campaign folder's `packs/` means content. A
package that also carried art would have to invent a second name.

**B2. The ruleset is both a dependency and a payload.** A package
carries `rules/srd5e/` whole, which makes it self-contained — and means
a table with ten packages has ten copies of the SRD, each pinned. That
was the accepted trade. But nothing yet says what happens when two
*open* things disagree: a campaign carrying srd5e 0.1.0 while the table
has 0.3.0 installed for its other campaigns. (Today: the campaign's copy
wins, silently.)

**B3. "The DM edits the base" has no shape.** A package is immutable and
editing means instancing and exporting a new version — so a campaign
developer's working copy is just another campaign, and the link back
(`package.id`) is only a note. There is no notion of "this instance *is*
the source of package X", no version bump, no changelog.

**B4. Content API 1 froze the shapes, but the *rules* have no version.**
A pack declares the content shapes it was written for. A ruleset
declares `api: 1`, the plugin API. Nothing declares "this campaign's
saved actors were written by srd5e 0.1.0" beyond `tested_with` — and the
per-actor `packs: {pack: version}` stamp, which `Compendium.outdated`
reports but nothing acts on.

**B5. Player devices are outside the story.** A phone fetches entries
from the Table under its audience. Fine. But a package's content, a
campaign's disabled list and an import are all Table-side; the phone
sees the consequences without being told anything changed.

## C. Answered 2026-09-23

The questions below were put to the user; these are the answers, and
they are now the design.

1. **Disabled means unoffered, not unusable.** Turning the monk off
   hides it from every search, picker and wizard; a DM who deliberately
   asks for it by id still gets it, and a character already built on it
   keeps working. No ruleset has to honour a new rule — the host does
   the hiding.
2. **Choice lists come from the compendium, live.** Hexmap grows
   pickers inside forms and wizard steps (gap G9), and rulesets stop
   hardcoding their class, species and background lists. That is what
   makes disabling and importing show up where a DM makes a character.
3. **A package carries the art its maps use.** The art packs a map
   names travel in the package, like its rules and its content. Art
   whose licence does not permit redistribution cannot be packaged, and
   export has to say so.
4. **Art belongs to the campaign**, as content and rules do:
   `<campaign>/art/<pack>/`, loaded for that campaign. A campaign copy
   carries its art with it.
5. **Packages are for strangers on the web.** The format is built to
   survive that: a content checksum in the manifest, and the licences
   and attributions of everything bundled surfaced *before* a DM starts
   it. Signing and a catalogue wait for a distribution channel.
6. **Updates are opt-in, with a report.** The Table may notice that a
   newer package or ruleset exists and offer it, showing what would
   change; nothing moves on its own, nothing moves silently.
7. **A campaign can be a package's working copy.** It owns the package
   id, export bumps the version and keeps a changelog, and re-exports to
   the same file. That is what makes the developer role real.

## D. Questions still open

- **What does a player device see when content changes?** Nothing, a
  note, or their own readable copy that works offline?
- **Image handouts** — does the first real package need to carry a
  region map as a picture, a letter, a portrait?
- **Two things are called a pack** (B1): with art now bundled beside
  content, `art/` and `packs/` sit side by side in a campaign. Is that
  naming good enough, or does one of them want a better word?
- **A campaign carrying a ruleset the table also has installed** (B2):
  today the campaign's copy wins, silently. Should the Table say so?

## E. Questions as they were asked

1. **Should a disabled entry be unusable, or only unoffered?** Does
   disabling the monk stop `create_character` building one by id (a
   hard rule the ruleset must honour), or is it purely about what the
   Table offers, with the DM free to say yes by hand?
2. **Where do a ruleset's *choices* come from?** To make A1 real,
   either the host grows live pickers inside forms/wizards (G9) and
   rulesets stop hardcoding lists, or rulesets query the compendium at
   registration and reload when content changes. Which?
3. **Does a package carry the art its maps use?** Bundle the art packs
   (biggest, simplest, licence questions), bake each map's art into an
   image the package carries, or ship maps that name art and tell the DM
   what is missing?
4. **Do art packs become campaign content too?** A campaign's `art/`
   beside its `packs/`, imported the same way — or do they stay a global
   library the app manages?
5. **How does a package get installed?** Drop-in folder only, a File →
   *Install a package…* that copies it in, a double-click association,
   or eventually a catalogue the app can fetch from?
6. **What is the upgrade story?** Never (a campaign is pinned forever),
   opt-in per campaign ("move to srd5e 0.3.0" with a report of what
   changed), or automatic for compatible versions?
7. **Is a package's source a first-class thing?** Should a campaign be
   able to say "I am the working copy of package X, version 1.3.0",
   with export bumping the version and keeping a changelog?
8. **Who is a package for?** One group's table, or a thing sold and
   downloaded by strangers? The second implies signing, a catalogue,
   integrity checks and a licence surface we have not designed.
9. **What does a player see of all this?** Nothing (Table-side only), a
   note when content changes, or their own copy of what they may read
   (a spell list on the phone that works offline)?
10. **Do we need image handouts before the first real package?** A
    package that can carry a region map as a picture, a letter, a
    portrait — or is text enough for v1?
