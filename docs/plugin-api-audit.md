# Plugin API — audit of Phases 0–7

Date: 2026-09-21, against `dev` at `82eabc9` (Phase 7). Conducted
before Phase 8 (the real rulesets, one at a time) to answer three
questions: do we have the tests the plan promised, do the CI pipelines
cover the targets that matter, and did we achieve what the plan set out
to achieve. Everything below was checked against the code, the test
suites and the workflow run history, not against the phase write-ups.

## 1. Summary

The kernel, the runtime, the protocol and the Table are in a good
state: 9,395 checks pass headless and in the exported desktop builds
on all three OSes, every reference plugin's own tests run in the suite,
replay reproduces the document byte for byte through every phase's
fuzz, and the five goals of the plan hold (§3). Two things needed
fixing and were fixed during the audit (§5), and the honest gaps are
in the test layers the plan listed but never built (golden fixtures,
UI snapshots, compat fixtures, a nightly), in mobile coverage of the
rules path (phones only ever run the join test), and in the growth
items the phases never scheduled (§4). None of the gaps blocks
Phase 8; three of them should be closed before the *second* real
ruleset, because they are what would catch a regression that a real
ruleset introduces.

## 2. Phase by phase: exit criteria against evidence

| phase | exit criterion (plan) | met? | evidence |
|---|---|---|---|
| 0 | Luau chosen with a working spike; formats drafted; decisions recorded | yes | `docs/lua-runtime.md`, `LuaVm` + `rules_lua` (4 tests: sandbox, budgets, yield/resume, bridge), decisions §7 of the plan |
| 1 | v2 document with events, `EventLog`, typed numbers, effects, resources, kernel; fuzz + replay | yes | `rules_kernel` (10 tests incl. `test_rules_fuzz`: 500 random batches, every applied event inverts, replay reproduces, derived never stale) |
| 2 | plugins load, hooks/derive/actions/prompts from Lua, `hm.test`, `plugintest` | yes | `rules_plugins` (5), `sample.ordered` 23 checks; `tools/plugin_test.gd` |
| 3 | both turn shapes, tracks, clock, rests, pending prompts/rolls; `sample.focus` | yes | `rules_turns` (7 incl. `test_both_plugins_fuzz` driving intents through two plugins), `sample.focus` 43 checks |
| 4 | declarative views on three surfaces, intents, protocol v2, Display role | yes | `rules_views` (2, one end-to-end over sockets: v1 refused, sheet arrives, card played, prompt answered, display sees no controls), `ui_views` |
| 5 | 5,000-entry pack answers a faceted query in ~1.5 ms; homebrew spawns like shipped; character files round-trip | yes | `rules_content` (5), `sample.degrees` 53 checks |
| 6 | each reference plugin uses the map; closed door blocks sight; players never get GM regions | yes | `rules_map` (4, 55 checks); plugin map tests |
| 7 | a two-session campaign end to end with a recap between | yes | `rules_campaign` (9, 136 checks): `test_campaign_two_sessions_with_a_recap` |

Every phase's "byte for byte" property still holds after Phase 7's
additions (checkpoints and the campaign block are in the replayed
documents).

## 3. Goals of the plan

| goal | status | note |
|---|---|---|
| 1. A ruleset is a plugin; nothing about any game lives in Hexmap | holds | `hexmap/rules/` has no game terms; the three shapes live only under `tests/plugins/`; `tools/check_scripts.gd` keeps `rules/` portable |
| 2. Plugins run only on the Table; clients render data | holds | the addon is excluded from the Android and iOS presets (`export_presets.cfg`); `Protocol.client_document` strips the rules blocks; `Views.project` is the only thing a client receives; verified on a real Android emulator (9,069 checks on the phone build, no Lua) |
| 3. Everything a plugin does is an event: replayable, undoable, replicated, testable | holds, one decision | replay/undo/replication tested per phase. The *event log itself* is not persisted (decided in Phase 1, revisited in Phase 7): checkpoints are document snapshots instead, so a saved encounter carries the state, not the history. The informational log (rolls, notes, rulings, handouts) is in the file. |
| 4. The three studied shapes are expressible without a host change | holds | ordered initiative + modifiers (`sample.ordered`), focus holder + cards + GM pool (`sample.focus`), degrees + valued conditions + action budget (`sample.degrees`); plus a house-rules layer (`sample.house`). Phases 3–7 each added host features *the plugins asked for*, which is the point of the reference plugins — Phase 8 is the real test of this goal. |
| 5. Every layer has a test harness before it has a second feature | holds for the code, not for every harness the plan named | see §4.1 |

Standing constraints: the app version is still 1.2.0 (`project.godot`);
format versions are `.encounter` 2, `.campaign` 1, protocol 2, plugin
API 1, as planned.

## 4. Findings

Ranked by what would bite Phase 8 first.

### 4.1 Test layers the plan promised (§5.1) vs what exists

| layer | planned | actual | gap |
|---|---|---|---|
| Unit | every kernel class, evaluators with negative cases | 12 `rules_*` suites, 5,960 lines of suites, 1,455 check calls | none |
| Golden logs | `tests/golden/*.log.json` replayed from an empty document | replay is asserted *inline* in `test_kernel_end_to_end`, `test_rules_fuzz`, `test_both_plugins_fuzz`, `test_checkpoints_in_the_document` — against documents built in the same run | **no checked-in fixture log.** A format change that silently alters what an old log means would not be caught. Cheap to add: record one log per reference plugin from a fixed seed, check it in, replay it in CI. |
| Fuzz | intents through plugins; invariants incl. "audience never leaks" | `test_rules_fuzz` (kernel), `test_both_plugins_fuzz` (two plugins, 500 ops) | the audience-leak invariant is tested deterministically (`test_projection_audience`, `test_cogm_role`) but **not inside the fuzz**; the fuzz does not project for a player after each step |
| Plugin conformance | `plugins/conformance/`; fails a plugin that declares no tests | `run_tests` + `test_every_reference_plugin_passes_its_own_tests`; manifest `tests` is a schema field only | **no conformance suite as such**: nothing checks "derive is pure", "hooks return well-formed payloads", "no forbidden globals" for an *arbitrary* plugin — only for the reference ones, by running their tests. Needed before accepting a third-party plugin; not needed for Phase 8's first ruleset (we write it). |
| Reference plugins | tests in CI and in the self-test on every platform | in the suite since Phase 7; on desktop self-tests; **skipped on phones** (no runtime, by design) | fine |
| Sandbox | red-team suite | `rules_lua` (VM) + `rules_sandbox` (plugin API), 57 checks; found and fixed two real holes | none |
| Protocol | v1 refused; v2 schemas validated both ways; audience table-driven; reconnect restores prompts | v1 refusal, roles and audience are tested over sockets; prompts survive save/load; **messages are not schema-validated** — the host validates *events* and *intents by kind*, the client applies events it can validate | a malformed `view` from a rogue host is applied as-is by the client. Low risk on a LAN; note for the relay future. |
| End-to-end | Table hosts `sample.focus`, a Player joins, sheet arrives, card played, prompt answered; on desktop CI, Android emulator, iOS simulator | on desktop: yes (`test_wire_views_intents_and_roles`, in-process over real sockets). **On phones: the join test does welcome → maps → join → one move, against a Table with no plugins** (`tools/android_ci.sh` hosts `chapel_ambush.encounter`) | **the rules path has never run on a real phone build**: no view rendered, no intent sent, no prompt answered from Android or iOS. The Player-side code is the same as the desktop test exercises, but the platform (touch, layout, fonts, the JSON bridge on ARM) is not. This is the most valuable gap to close before Phase 8's first ruleset reaches a table. |
| UI snapshots | PNGs at phone and desktop sizes, diffed with tolerance | screenshots are taken (`selftest_*.png` artifacts) but **never diffed** | a rendering regression on a phone would pass CI. Medium value, medium cost (tolerance tuning across GPUs). |
| Performance | budgets in tests; nightly on a fixed runner | `rules_perf` (4 tests), `test_kernel_derive_budget`, `test_compendium_scale`; ×3 on CI | no nightly, no fixed runner — budgets are loose enough for shared runners. Acceptable. |
| Compatibility | `tests/compat/` fixtures: v1 upgrades and re-saves identically; unknown widget; pack updated under a character | v1 upgrade is tested inline (`test_encounter_document`: thin, nulls, pre-release initiative); unknown widget falls back to text (`ui_views`); `outdated()` tested | **no checked-in v1 fixture file**; the inline strings are the only v1 documents in the repo. Add `tests/compat/v1.encounter` and assert it upgrades and re-saves to a checked-in expected v2 file. |

### 4.2 Determinism (§5.2)

- Rolls from the seeded stream, replay reads faces: holds and tested.
- "`derive()` is called twice in debug builds and the test fails if the
  results differ": **not implemented**. `test_kernel_end_to_end` derives
  twice and compares once; the kernel does not do it. Cheap to add
  behind `OS.is_debug_build()` in `rederive()`; would catch a plugin
  whose derive reads `math.random` or mutates its input.
- Hook order shuffled by the fuzz: **not shuffled**; order is asserted
  deterministically (`test_plugin_ordering_between_plugins`, the
  layering test). Acceptable.
- No `Time.*` inside the kernel: holds (`grep` over `rules/`: none; the
  clock is document data; checkpoints stamp `when` in the *event*, so a
  replay lands on the same bytes).

### 4.3 CI on the targets that matter (§5.3)

| workflow | trigger | what it runs | last run against | verdict |
|---|---|---|---|---|
| `ci` | every push and PR | check, unit suite (all `rules_*`, plugin tests, sandbox, perf), examples regenerate, sheet | 82eabc9 ✓ | as planned |
| `desktop-test` | manual + weekly | headless suite, then the exported build's self-test on macOS, Windows, Linux | 82eabc9 ✓ (9,389–9,390 checks) | as planned; run by hand after every phase |
| `android-test` | manual + weekly | phone build self-test on an emulator (no Lua) + the join test against a Table on the runner | 82eabc9 **✗** — 2 failures | **found by this audit**: `test_table_campaign_panel_and_dialogs` assumed a Lua runtime. Fixed (§5). Phases 4–6 had been verified on Android (99ef0d5 ✓); Phase 7 had not. |
| `ios-test` | manual only (macOS minutes) | simulator self-test + join | 9b30b7e — **Phase 3** | **Phases 4–7 were never run on iOS.** Re-run as part of this audit (§5). |
| `build-luau` | manual | the Luau binaries for the three desktops | 7c43e68 ✓ | fine; the binaries are checked in |
| `release` | tags | builds | unchanged by this work | fine |
| nightly long fuzz + perf | planned | **does not exist** | — | low priority: the short fuzz runs on every push |

Two process points: the phone workflows are manual, so a phase can be
declared done without them having run (Phase 7 was). And `ci` does not
run the reference plugins' `plugintest` separately — it does not need
to since Phase 7 (they run inside the suite), but the plan's §5.3
should say so.

### 4.4 The primitives (P1–P15) and the growth list (G1–G20)

All fifteen primitives exist and are exercised by at least one
reference plugin. Two are narrower than the desirement:

- P5/G2, physical dice: typed-in faces work end to end (`spec.faces`,
  `t.roll_with_faces`) but **no client UI lets a player type a
  physical roll**; a plugin would have to prompt for it.
- P14, the typed event log: complete in memory; not persisted (see
  goal 3).

Growth items scheduled by the plan and delivered: G1, G3, G4, G5, G6,
G7, G10, G11, G12, G13, G15, G17, G18. Delivered in narrower form:
G8 (a Player joined to a table with no scene is not verified anywhere), G19
(art from packs, token art picker; no library UI). **Never scheduled
and not done**: G9 random tables as a primitive, G14 live encounter
feel (damage per side, a running read), G16 contextual suggestions,
G20 accessibility. G9 is the one a real ruleset will ask for first
(treasure, wild magic, encounter tables); it is small — a `tables`
collection kind in the compendium and `hm.comp.roll_on(collection, id)`
— and should go into Phase 8's first ruleset as a host addition when
it is asked for, not before.

Of the 37 marketplace features the desirements catalogue, the Must
tier (1–10) is buildable on the API as it stands, with two caveats a
real ruleset will hit: **drag-and-drop from the compendium to the map**
(feature 3) has no host support — the Compendium pane has "spawn"
through a plugin action instead; and **"going down" flows** (feature 7)
that need a prompt to the *GM* rather than a player work through the
`gm` recipient of `hm.prompt` but have no dedicated Table queue
beyond the Rules pane's list. Feature 30 (animation and audio hooks)
and 33 (localisation) have no API at all.

### 4.5 Smaller things noticed

- `docs/plugin-api-plan.md` §5.1 and §5.3 still describe the planned
  layers as if they existed (`tests/golden/`, `plugins/conformance/`,
  `tests/snapshots/`, `perf_*.gd`, a nightly). They should describe
  what is (this audit is the record of the difference).
- The `.uid` sidecar files are committed for every script, which is
  right for Godot 4.4+, but `tests/suites/rules_map.gd.uid` arrived a
  phase after its script; harmless.
- The perf budgets are ×3 on CI by environment variable; the exported
  self-test inherits it, so the desktop self-test measured under the
  relaxed budget. Fine, but it means the tight numbers are only ever
  asserted on a developer machine.
- `Bulk` and `Improv` have no Lua-side tests beyond `sample.degrees`'s
  burst and benchmark; the GDScript suites cover the rest.

## 5. Fixed during the audit

1. `test_table_campaign_panel_and_dialogs` assumed a Lua runtime; on
   the phone builds (no runtime, by design) two checks failed. Guarded:
   without a runtime the test asserts the table runs the campaign with
   no plugins.
2. `android-test` and `ios-test` re-run on the fixed commit; results
   recorded below.

## 6. Recommendations before Phase 8

In order:

1. **Run the phone workflows as part of "done".** A phase is done when
   `ci`, `desktop-test`, `android-test` and `ios-test` are green on its
   commit. Cost: ~25 min of runner time per phase, most of it macOS.
2. **Put the rules path on a phone in CI** (closes the largest gap):
   host the join-test Table with `sample.focus` loaded and actors
   linked, and extend `TestSuite.join_remote` to wait for a view, tap a
   card by intent, answer a prompt. One afternoon; reuses
   `test_wire_views_intents_and_roles`.
3. **Check in fixtures**: one golden log per reference plugin
   (`tests/golden/`), one v1 encounter with its expected v2
   (`tests/compat/`). An hour; they are the regression net for Phase 8's
   format additions.
4. **`derive` purity check in debug builds** (ten lines in `rederive`).
5. Defer: UI snapshot diffing, the nightly, a conformance suite for
   third-party plugins, protocol message schemas. Revisit when a plugin
   we did not write is about to be loaded, or when a relay is.

Phase 8 itself: take the rulesets one at a time as intended, and treat
every host change a ruleset needs as a finding against goal 4 — logged
in the plan's Phase 8 section with what it was and why the API lacked
it. The API is 1.0 when a ruleset ships with that list empty.

## 7. Results of the re-runs

On `6dcfc1c` (the audit commit, with the fix in §5):

| workflow | result |
|---|---|
| `ci` | success — 9,395 checks |
| `android-test` | success — 9,068 checks in the phone build, 7 in the join test (a first attempt failed on the runner itself: the emulator SDK download was a corrupt archive; the re-run went through) |
| `ios-test` | success — 9,068 checks in the simulator; the first iOS run since Phase 3, so Phases 4–7 are now verified there |
| `desktop-test` | success on 82eabc9 (unchanged by the audit commit) |

All four targets are green on the same commit for the first time
since Phase 3, which is the state Phase 8 starts from.
