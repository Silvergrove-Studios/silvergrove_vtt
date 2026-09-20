extends TestCase
## Phase 1 of the plugin API: the kernel core. Typed numbers, the hook
## bus, dice, effects, resources, the event log, derivation, and the
## whole chain through the SampleRules fixture — with the golden-log and
## undo-all invariants and a fuzz over the version-2 events.


func _state() -> EncounterState:
	var st := EncounterState.new(Encounter.create("Rules"))
	st.encounter.doc.rng = {"seed": 424242, "index": 0}
	st.encounter.doc.meta.created = "2026-09-20T00:00:00"
	return st


## A scene with no map: enough to hold tokens.
func _scene() -> Dictionary:
	return {"id": JsonDoc.new_id("s"), "name": "G", "map": "", "map_path": "", "level": "ground", "overrides": {}, "fog": {"enabled": false, "explored": []}, "tokens": []}


func _hero(st: EncounterState, id := "a_hero", agi := 3, strength := 1) -> void:
	st.apply({"t": "actor.add", "actor": {"id": id, "kind": "pc", "name": id, "ext": {"sample": {"level": 2, "stats": {"agi": agi, "str": strength, "wit": 0}}}}})


# ------------------------------------------------------------- numbers --

func test_typed_numbers() -> void:
	var n := TypedNumber.make([{"label": "base", "type": "base", "value": 10}, {"label": "agi", "type": "ability", "value": 3}])
	check(n.total == 13.0 and n.parts.size() == 2, "make totals its parts")
	n = TypedNumber.add(n, {"label": "bless", "type": "status", "value": 2})
	n = TypedNumber.add(n, {"label": "guidance", "type": "status", "value": 1})
	check(n.total == 16.0, "stacking is the default")
	check(TypedNumber.total(n.parts, {"status": "best"}) == 15.0, "best: the larger status bonus alone counts")
	n = TypedNumber.add(n, {"label": "shaken", "type": "status", "value": -2})
	check(TypedNumber.total(n.parts, {"status": "best"}) == 13.0, "best: plus the worst penalty of the type")
	check(TypedNumber.total(n.parts, {"*": "best"}) == 10 + 3 + 2 - 2, "'*' is the default policy for every type")
	check(TypedNumber.total([{"type": "x", "value": 1}, {"type": "x", "value": 5}], {"x": "override"}) == 5.0, "override: last wins")
	check(TypedNumber.value(n) == n.total and TypedNumber.value(4) == 4.0 and TypedNumber.value(null) == 0.0, "value() of anything")
	check(TypedNumber.of(7).total == 7.0 and not TypedNumber.is_typed(7) and TypedNumber.is_typed(TypedNumber.of(7)), "of / is_typed")
	var d := {"a": TypedNumber.make([{"type": "status", "value": 2}, {"type": "status", "value": 3}]), "b": 1}
	TypedNumber.retotal(d, {"status": "best"})
	check(d.a.total == 3.0 and d.b == 1, "retotal touches typed numbers only")


# ---------------------------------------------------------------- hooks --

func test_hook_bus() -> void:
	var bus := HookBus.new()
	var trail := []
	bus.on("x", func(p: Dictionary) -> Dictionary: trail.append("b"); p.n += 1; return p, "plugin_b", 2)
	bus.on("x", func(p: Dictionary) -> Variant: trail.append("a"); p.n *= 10; return null, "plugin_a", 1)
	bus.on("x", func(p: Dictionary) -> Dictionary: trail.append("c"); return p, "plugin_c", 2)
	var r := bus.run("x", {"n": 1})
	check(r.status == HookBus.HookRun.DONE and r.payload.n == 11 and trail == ["a", "b", "c"], "handlers run by order then registration, each seeing the last payload: %s %s" % [r.payload, trail])
	bus.off("plugin_c")
	check(bus.handlers("x").size() == 2, "off() drops an owner's handlers")
	bus.on("x", func(p: Dictionary) -> Dictionary: p.veto = "no"; return p, "plugin_v", 1)
	bus.on("x", func(p: Dictionary) -> Dictionary: p.late = true; return p, "plugin_l", 9)
	r = bus.run("x", {"n": 1})
	check(r.status == HookBus.HookRun.VETOED and not r.payload.has("late"), "a veto stops the chain")
	bus.off("plugin_v")
	# pause and resume
	bus.on("ask", func(p: Dictionary) -> Variant:
		return HookBus.Wait.make({"question": "spend?"}, func(pl: Dictionary, answer: Variant) -> Dictionary:
			pl.answer = answer
			return pl), "plugin_p")
	bus.on("ask", func(p: Dictionary) -> Dictionary: p.after = true; return p, "plugin_q")
	r = bus.run("ask", {})
	check(r.status == HookBus.HookRun.PENDING and r.request.question == "spend?" and not r.payload.has("after"), "a Wait pauses the run before later handlers")
	r.resume("yes")
	check(r.status == HookBus.HookRun.DONE and r.payload.answer == "yes" and r.payload.after == true, "resume continues through the rest of the chain")
	check(bus.run_sync("ask", {}).has("veto"), "run_sync treats a pause as a veto")
	# failure isolation
	var failed := []
	bus.handler_failed.connect(func(h: String, o: String, m: String) -> void: failed.append([h, o, m]))
	bus.on("f", func(_p: Dictionary) -> Dictionary: return {"__error": "boom"}, "bad")
	bus.on("f", func(p: Dictionary) -> Dictionary: p.ok = true; return p, "good")
	r = bus.run("f", {})
	check(r.status == HookBus.HookRun.DONE and r.payload.ok == true and r.errors.size() == 1 and failed.size() == 1 and failed[0][1] == "bad", "a failing handler is skipped and reported")
	check(bus.run("nothing", {"k": 1}).payload == {"k": 1}, "a hook nobody listens to passes the payload through")


# ----------------------------------------------------------------- dice --

func test_dice() -> void:
	check(Dice.face(1, 0, 20) == Dice.face(1, 0, 20) and Dice.face(1, 0, 20) != Dice.face(1, 1, 20) or Dice.face(1, 2, 20) != Dice.face(1, 1, 20), "faces are a pure function of seed and index")
	var counts := {}
	for i in 6000:
		var f := Dice.face(99, i, 6)
		counts[f] = int(counts.get(f, 0)) + 1
	check(counts.size() == 6, "every face of a d6 shows up")
	for f in counts:
		check(counts[f] > 800 and counts[f] < 1200, "d6 face %d is roughly uniform (%d/6000)" % [f, counts[f]])
	for bad in ["", "d6", "2d", "2d6kh", "x", "1d0", "0d6", "101d6", "2d6+", "1d6 r"]:
		check(Dice.parse(bad).has("error"), "'%s' is a parse error" % bad)
	var p := Dice.parse("2d6 + 1d8kh1 - 3 + 2")
	check(not p.has("error") and p.terms.size() == 2 and p.constant == -1.0, "constants fold: %s" % [p])
	var r := Dice.roll("2d6+3", 7, 0)
	check(r.ok and r.dice.size() == 2 and r.draw.count == 2 and r.total == r.groups.main.total and r.total == float(r.dice[0].face + r.dice[1].face + 3), "a plain roll: %s" % [r.total])
	var again := Dice.roll("2d6+3", 7, 0)
	check(JsonDoc.same(r, again), "the same seed and index give the same result")
	var kh := Dice.roll("4d6kh3", 7, 10)
	var kept := 0
	var sum := 0
	var lowest := 7
	for d in kh.dice:
		lowest = mini(lowest, int(d.face))
		if d.kept:
			kept += 1
			sum += int(d.face)
	check(kept == 3 and kh.total == float(sum) and kh.dice.size() == 4, "keep highest 3 of 4")
	var dl := Dice.roll("4d6dl1", 7, 10)
	check(JsonDoc.same(Dice.faces_of(dl), Dice.faces_of(kh)) and dl.total == kh.total, "drop lowest 1 is the same roll as keep highest 3")
	var rr := Dice.roll("10d2r1", 7, 20)
	var rerolled := 0
	for d in rr.dice:
		if d.rerolled:
			rerolled += 1
			check(not d.kept and int(d.face) == 1, "a rerolled 1 is shown and not counted")
	check(rerolled > 0 and rr.draw.count == 10 + rerolled, "rerolls draw extra faces")
	var ex := Dice.roll("3d2!", 7, 40)
	var exploded := 0
	for d in ex.dice:
		if d.exploded:
			exploded += 1
	check(exploded > 0 and ex.dice.size() == 3 + exploded and ex.dice.size() <= 3 + 3 * Dice.EXPLODE_LIMIT, "exploding dice add faces, bounded")
	var mn := Dice.roll("6d4min3", 7, 60)
	for d in mn.dice:
		check(int(d.face) >= 3, "min raises low faces (%d)" % int(d.face))
	# named groups, typed-in faces, parts
	var duality := Dice.roll({"expr": "", "named": {"hope": "1d12", "fear": "1d12"}, "parts": [{"label": "trait", "type": "ability", "value": 2}, {"label": "bless", "type": "status", "value": 1}, {"label": "curse", "type": "status", "value": 2}], "policy": {"status": "best"}, "kind": "action"}, 7, 0)
	check(duality.ok and duality.groups.has("hope") and duality.groups.has("fear") and duality.dice.size() == 2, "named groups")
	check(duality.modifier == 4.0 and duality.total == float(duality.groups.hope.total + duality.groups.fear.total) + 4.0, "typed parts are totalled under the policy (best status): %s" % duality.modifier)
	var typed := Dice.roll({"expr": "2d6+1", "faces": {"main": [4, 5]}}, 7, 0)
	check(typed.total == 10.0 and typed.draw.count == 0 and typed.dice[0].face == 4, "typed-in faces draw nothing from the stream")
	var half := Dice.roll({"expr": "2d6", "faces": {"main": [6]}}, 7, 0)
	check(half.draw.count == 1 and half.dice[0].face == 6, "partial typed-in faces draw the rest")
	check(not Dice.roll({"named": {}}, 1, 0).ok and not Dice.roll("2d6+x", 1, 0).ok, "bad specs fail softly")
	# pending
	var pend := Dice.Pending.new({"expr": "1d20", "parts": [{"label": "trait", "value": 1}]})
	check(pend.contribute("pl_b", "help", "1d6") == "" and pend.contribute("pl_c", "help", "1d6") != "" and pend.contribute("pl_c", "rally", "1dx") != "", "contributions are named and checked")
	var res := pend.resolve(7, 100)
	check(res.ok and res.groups.has("help") and res.contributions.size() == 1 and res.total == float(res.groups.main.total + res.groups.help.total) + 1.0, "a pending roll resolves with its contributions")


# -------------------------------------------------------------- effects --

func test_effects() -> void:
	var st := _state()
	_hero(st)
	var sc := _scene()
	st.apply({"t": "scene.add", "scene": sc})
	st.apply({"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", Vector2(1, 1), {"id": "t_h", "actor": "a_hero"})})
	var shaken := {"id": "e_1", "on": "token:t_h", "plugin": "sample", "key": "shaken", "value": 1, "duration": {"kind": "turn_end", "of": "t_h", "turns": 2}, "changes": [{"path": "defence", "mode": "add", "value": -2, "type": "status"}], "stack": "highest"}
	var evs := Effects.apply(st, shaken)
	check(evs.size() == 1 and evs[0].t == "effect.apply", "a new effect is applied")
	for ev in evs:
		st.apply(ev)
	check(Effects.on(st, "token:t_h").size() == 1 and Effects.on(st, "token:t_h", "shaken")[0].id == "e_1", "on() finds it")
	var lower := shaken.duplicate(true)
	lower.id = "e_2"
	lower.value = 0
	check(Effects.apply(st, lower).is_empty(), "highest: a lower value changes nothing")
	var higher := shaken.duplicate(true)
	higher.id = "e_3"
	higher.value = 3
	evs = Effects.apply(st, higher)
	check(evs.size() == 1 and evs[0].t == "effect.set" and evs[0].id == "e_1" and evs[0].changes.value == 3, "highest: a higher value updates the existing record")
	var none := shaken.duplicate(true)
	none.id = "e_4"
	none.stack = "none"
	check(Effects.apply(st, none).is_empty(), "none: nothing while one exists")
	var stacker := shaken.duplicate(true)
	stacker.id = "e_5"
	stacker.stack = "stack"
	check(Effects.apply(st, stacker)[0].t == "effect.apply", "stack: another one")
	# linked and expiry
	st.apply({"t": "effect.apply", "effect": {"id": "e_link", "on": "actor:a_hero", "plugin": "sample", "key": "mark", "duration": {"kind": "linked", "to": "e_1"}}})
	st.apply({"t": "effect.apply", "effect": {"id": "e_round", "on": "actor:a_hero", "plugin": "sample", "key": "haste", "duration": {"kind": "rounds", "rounds": 2}}})
	st.apply({"t": "effect.apply", "effect": {"id": "e_scene", "on": "actor:a_hero", "plugin": "sample", "key": "blessed", "duration": {"kind": "scene"}}})
	st.apply({"t": "effect.apply", "effect": {"id": "e_rest", "on": "actor:a_hero", "plugin": "sample", "key": "tired", "duration": {"kind": "rest"}}})
	var tick := Effects.expire(st, {"kind": "turn_end", "of": "t_h"})
	check(tick.size() == 1 and tick[0].t == "effect.set" and tick[0].changes["duration.turns"] == 1, "a counted duration ticks down: %s" % [tick])
	for ev in tick:
		st.apply(ev)
	tick = Effects.expire(st, {"kind": "turn_end", "of": "t_h"})
	var removed := []
	for ev in tick:
		removed.append(ev.id)
	check(removed.has("e_1") and removed.has("e_link"), "at zero it ends, and takes what is linked to it: %s" % [removed])
	check(Effects.expire(st, {"kind": "turn_end", "of": "t_other"}).is_empty(), "another token's turn end changes nothing")
	check(Effects.expire(st, {"kind": "round"})[0].changes["duration.rounds"] == 1, "rounds tick")
	check(Effects.expire(st, {"kind": "scene"})[0].id == "e_scene", "scene end")
	check(Effects.expire(st, {"kind": "rest"}).size() == 1 and Effects.expire(st, {"kind": "long_rest"}).size() == 1, "rests")
	check(Effects.remove(st, "e_1").size() == 2 and Effects.remove(st, "nope").is_empty(), "remove cascades through links")
	# changes on derived
	var derived := {"defence": TypedNumber.make([{"label": "base", "type": "base", "value": 10}]), "speed": 6.0, "hp_max": 20.0}
	Effects.apply_changes(derived, [
		{"id": "x1", "key": "shaken", "label": "Shaken", "changes": [{"path": "defence", "mode": "add", "value": -2, "type": "status"}]},
		{"id": "x2", "key": "slow", "changes": [{"path": "speed", "mode": "multiply", "value": 0.5}]},
		{"id": "x3", "key": "big", "value": 2, "changes": [{"path": "hp_max", "mode": "add", "expr": "@value * 5"}]},
		{"id": "x4", "key": "armour", "changes": [{"path": "defence", "mode": "upgrade", "value": 12, "type": "item"}]},
		{"id": "x5", "key": "wall", "changes": [{"path": "defence", "mode": "override", "value": 20}]},
	], {}, {"status": "best"})
	check(derived.speed == 3.0 and derived.hp_max == 30.0, "plain numbers: multiply and an expr with the effect's value: %s %s" % [derived.speed, derived.hp_max])
	check(derived.defence.total == 20.0 and derived.defence.parts.size() == 4, "typed: add, upgrade (delta) and override (delta) keep the parts summing to the total: %s" % [derived.defence])
	check(derived.defence.parts[1].source == "x1" and derived.defence.parts[1].label == "Shaken", "a change's part names its effect")


# ------------------------------------------------------------ resources --

func test_resources() -> void:
	var st := _state()
	_hero(st)
	var ref := "actor:a_hero"
	st.apply(Resources.set_event(ref, "sample", "hp", Resources.pool(7, 9, "rest")))
	st.apply(Resources.set_event(ref, "sample", "stress", Resources.track(6, 2, 1, [5], "long_rest")))
	check(Resources.get_record(st, ref, "sample", "hp").current == 7 and Resources.of(st, ref, "sample").size() == 2, "records are stored per ref, plugin and name")
	var ev := Resources.spend(st, ref, "sample", "hp", 3)
	check(ev.record.current == 4.0, "spend")
	st.apply(ev)
	check(Resources.spend(st, ref, "sample", "hp", 5).is_empty(), "cannot overspend")
	check(Resources.gain(st, ref, "sample", "hp", 20).record.current == 9.0 and Resources.gain(st, ref, "sample", "hp", 20, true).record.current == 24.0, "gain caps unless overflow")
	check(Resources.track_capacity(Resources.get_record(st, ref, "sample", "stress")) == 6, "capacity = max + extra - crossed")
	check(Resources.mark(st, ref, "sample", "stress", 4).record.marked == 6 and Resources.mark(st, ref, "sample", "stress", 5).is_empty(), "mark within capacity")
	check(Resources.clear(st, ref, "sample", "stress", 1).record.marked == 1 and Resources.clear(st, ref, "sample", "stress", -1).record.marked == 0, "clear some or all")
	var crossed := Resources.cross(st, ref, "sample", "stress", 3)
	check(crossed.record.crossed == [3, 5] and Resources.track_capacity(crossed.record) == 5, "cross out a box")
	st.apply(Resources.mark(st, ref, "sample", "stress", 3))
	var refill := Resources.refill(st, "rest")
	check(refill.size() == 1 and refill[0].name == "hp" and refill[0].record.current == 9.0, "refill by recharge kind touches the pools that need it")
	check(Resources.refill(st, "long_rest")[0].record.marked == 0 and Resources.refill(st, "session").is_empty(), "…and clears tracks")
	var inv := st.apply(Resources.set_event(ref, "sample", "hp", null))
	check(Resources.get_record(st, ref, "sample", "hp").is_empty() and inv.record.current == 4.0, "removing a record inverts to the old record")
	st.apply(inv)
	check(Resources.get_record(st, ref, "sample", "hp").current == 4.0, "…and back")


# ------------------------------------------------------- document, v2 --

func test_encounter_v2_events() -> void:
	var st := _state()
	check(st.encounter.doc.version == 2 and st.encounter.actors.is_empty() and st.encounter.doc.rng.index == 0, "a new encounter is version 2")
	# validate
	var bad := {
		"actor.add without id": {"t": "actor.add", "actor": {"name": "x"}},
		"actor.set of a missing actor": {"t": "actor.set", "id": "zz", "changes": {}},
		"effect.apply without key": {"t": "effect.apply", "effect": {"id": "e", "on": "encounter"}},
		"effect.apply on nobody": {"t": "effect.apply", "effect": {"id": "e", "on": "token:none", "key": "k"}},
		"resource.set with a bad ref": {"t": "resource.set", "ref": "thing:1", "plugin": "p", "name": "n", "record": {}},
		"ext.set bad scope": {"t": "ext.set", "scope": "galaxy", "plugin": "p", "changes": {}},
		"log.add without kind": {"t": "log.add", "entry": {"id": "l1"}},
		"log.remove missing": {"t": "log.remove", "id": "l9"},
	}
	for label in bad:
		check(st.validate(bad[label]) != "", label + " is refused")
	_hero(st)
	check(st.validate({"t": "actor.set", "id": "a_hero", "changes": {"derived.sample.x": 1}}) != "", "derived is not settable by event")
	check(st.validate({"t": "actor.add", "actor": {"id": "a_hero"}}) != "", "no duplicate actors")
	# apply / inverse round trips
	var start := JsonDoc.sans_modified(st.encounter.to_json())
	var events := [
		{"t": "actor.set", "id": "a_hero", "changes": {"ext.sample.stats.agi": 5, "name": "Ana", "ext.sample.stats.wit": null}},
		{"t": "actor.overlay.push", "id": "a_hero", "overlay": {"id": "o_bear", "patch": {"sample": {"stats": {"str": 4}}}}},
		{"t": "effect.apply", "effect": {"id": "e_1", "on": "actor:a_hero", "plugin": "sample", "key": "shaken", "value": 2}},
		{"t": "effect.set", "id": "e_1", "changes": {"value": 3, "duration.kind": "scene"}},
		{"t": "resource.set", "ref": "actor:a_hero", "plugin": "sample", "name": "hp", "record": Resources.pool(3, 9)},
		{"t": "ext.set", "scope": "encounter", "plugin": "sample", "changes": {"gm_pool": 4, "notes.a": "x"}},
		{"t": "log.add", "entry": {"id": "l_1", "kind": "note", "text": "hello"}},
		{"t": "log.add", "entry": {"id": "l_2", "kind": "roll", "draw": {"seed": 424242, "index": 0, "count": 3}}},
	]
	var inverses := []
	for ev in events:
		check(st.validate(ev) == "", "%s validates: %s" % [ev.t, st.validate(ev)])
		var inv := st.apply(ev)
		check(not inv.is_empty(), "%s applies" % ev.t)
		inverses.append(inv)
	var a := st.encounter.actor("a_hero")
	check(a.ext.sample.stats.agi == 5 and a.name == "Ana" and not a.ext.sample.stats.has("wit"), "dotted paths set deep and null removes")
	check(a.overlays.size() == 1 and st.encounter.effect("e_1").value == 3 and st.encounter.effect("e_1").duration.kind == "scene", "overlay pushed, effect changed by path")
	check(st.encounter.doc.state.ext.sample.gm_pool == 4 and st.encounter.doc.state.ext.sample.notes.a == "x", "encounter-scoped plugin state")
	check(st.encounter.log.size() == 2 and st.encounter.doc.rng.index == 3, "the log grew and a roll entry moved the dice stream")
	var mirror := EncounterState.new(Encounter.from_json(JsonDoc.stringify(JsonDoc.parse(start.replace('"modified": ""', '"modified": "x"')))))
	for ev in events:
		mirror.apply(ev)
	check(JsonDoc.sans_modified(mirror.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "a mirror fed the same events matches")
	for i in range(inverses.size() - 1, -1, -1):
		st.apply(inverses[i])
	check(JsonDoc.sans_modified(st.encounter.to_json()) == start, "inverses restore the start byte for byte (dice stream included)")
	# v1 upgrade
	var v1 := Encounter.load_file(example("chapel_ambush.encounter"))
	check(v1.doc.version == 2 and v1.actors.is_empty() and v1.doc.has("rng") and v1.log.is_empty(), "a version-1 file loads as version 2 with empty rules blocks")
	# path helpers
	var d := {"a": {"b": 1}}
	check(JsonDoc.at_path(d, "a.b") == 1 and JsonDoc.at_path(d, "a.c", 7) == 7 and JsonDoc.at_path({"l": [1, 2]}, "l.1") == 2, "get_path")
	check(JsonDoc.set_at_path(d, "a.c.d", 5) == null and d.a.c.d == 5 and JsonDoc.set_at_path(d, "a.b", null) == 1 and not d.a.has("b"), "set_path creates and removes")


# ------------------------------------------------------------ event log --

func test_event_log() -> void:
	var st := _state()
	var log := EventLog.new(st)
	var seen := []
	log.appended.connect(func(e: Dictionary) -> void: seen.append(e.seq))
	check(log.record({"t": "actor.add", "actor": {"id": "a_1", "name": "One"}}, "Add", {"by": "test"}) == "", "record applies a valid event")
	check(log.record({"t": "actor.set", "id": "nope", "changes": {}}) != "" and log.entries.size() == 1, "an invalid event is refused and not logged")
	check(log.entries[0].seq == 1 and log.entries[0].reason.by == "test" and log.entries[0].inv.t == "actor.remove", "entries carry seq, reason and inverse")
	check(log.record_all([{"t": "actor.set", "id": "a_1", "changes": {"name": "Two"}}, {"t": "actor.set", "id": "zz", "changes": {}}], "Batch") != "", "a batch with a bad event is refused")
	check(st.encounter.actor("a_1").name == "One" and log.entries.size() == 3, "…and what it applied is undone (as compensating entries)")
	check(log.record_all([{"t": "actor.set", "id": "a_1", "changes": {"name": "Two"}}, {"t": "actor.set", "id": "a_1", "changes": {"name": "Three"}}], "Batch") == "" and log.can_undo() and log.undo_label() == "Batch", "a good batch is one undo step")
	log.undo()
	check(st.encounter.actor("a_1").name == "One" and log.entries.size() == 7 and log.entries[6].undo_of == 4, "undo appends the inverses, marked with what they undo")
	log.redo()
	check(st.encounter.actor("a_1").name == "Three" and log.entries.size() == 9, "redo appends again")
	log.checkpoint("before")
	log.record({"t": "actor.set", "id": "a_1", "changes": {"name": "Four"}})
	log.record({"t": "actor.add", "actor": {"id": "a_2"}})
	check(log.restore("before") and st.encounter.actor("a_1").name == "Three" and st.encounter.actors.size() == 1, "restore goes back to a checkpoint")
	check(log.can_undo() and log.undo_label().begins_with("Restore"), "…as one undoable step")
	log.undo()
	check(st.encounter.actor("a_1").name == "Four" and st.encounter.actors.size() == 2, "…which undoes back to where we were")
	check(not log.restore("nowhere"), "an unknown checkpoint is refused")
	check(log.since(12).size() == log.entries.size() - 12, "since() for a catching-up client")
	# replay
	var fresh := EncounterState.new(Encounter.create("Rules"))
	fresh.encounter.doc.rng = st.encounter.doc.rng.duplicate()
	fresh.encounter.doc.id = st.encounter.doc.id
	fresh.encounter.doc.meta = st.encounter.doc.meta.duplicate()
	check(EventLog.replay(fresh, log.entries) == "", "the log replays onto a fresh state")
	check(JsonDoc.sans_modified(fresh.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "…and reproduces the document, undo and restore included")


# ----------------------------------------------------------- the kernel --

func test_kernel_end_to_end() -> void:
	var st := _state()
	var k := RulesKernel.new(st)
	var rules := SampleRules.new()
	rules.install(k)
	var changed := []
	k.derived_changed.connect(func(id: String) -> void: changed.append(id))
	var start := JsonDoc.sans_modified(st.encounter.to_json())
	# actors and a token
	check(k.commit([{"t": "actor.add", "actor": {"id": "a_hero", "kind": "pc", "ext": {"sample": {"level": 2, "stats": {"agi": 3, "str": 1}}}}},
		{"t": "actor.add", "actor": {"id": "a_gob", "kind": "npc", "ext": {"sample": {"level": 1, "stats": {"agi": 1, "str": 2}}}}},
		Resources.set_event("actor:a_hero", "sample", "hp", Resources.pool(15, 15, "rest")),
		Resources.set_event("actor:a_gob", "sample", "hp", Resources.pool(8, 8, "rest"))], "Party") == "", "a commit of several events")
	var hero := st.encounter.actor("a_hero")
	check(hero.derived.sample.defence.total == 13 and hero.derived.sample.hp_max == 15 and hero.derived.sample.level_label == "Level 2", "derived: a typed defence, a plain number, a data-declared field: %s" % [hero.derived])
	check(changed.has("a_hero") and changed.has("a_gob"), "derived_changed fired for both")
	var sc := _scene()
	k.commit([{"t": "scene.add", "scene": sc}, {"t": "token.add", "scene": sc.id, "token": Encounter.new_token("Hero", Vector2(1, 1), {"id": "t_h", "actor": "a_hero"})}], "Scene")
	# an effect on the token changes the actor's numbers
	changed.clear()
	k.commit(Effects.apply(st, {"id": "e_shaken", "on": "token:t_h", "plugin": "sample", "key": "shaken", "label": "Shaken", "value": 1, "duration": {"kind": "turn_end", "of": "t_h", "turns": 1}, "changes": [{"path": "defence", "mode": "add", "value": -2, "type": "status"}], "stack": "highest"}), "Shaken")
	hero = st.encounter.actor("a_hero")
	check(hero.derived.sample.defence.total == 11 and hero.derived.sample.defence.parts[2].label == "Shaken", "an effect on a linked token lowers the actor's defence with a named part")
	check(changed == ["a_hero"], "only the touched actor was re-derived: %s" % [changed])
	# an overlay
	k.commit([{"t": "actor.overlay.push", "id": "a_hero", "overlay": {"id": "o_bear", "patch": {"sample": {"stats": {"str": 4}}}}}], "Bear form")
	check(st.encounter.actor("a_hero").derived.sample.attack.total == 4 and st.encounter.actor("a_hero").ext.sample.stats.str == 1, "an overlay changes derived numbers without touching the source data")
	k.commit([{"t": "actor.overlay.pop", "id": "a_hero", "overlay_id": "o_bear"}], "Back")
	check(st.encounter.actor("a_hero").derived.sample.attack.total == 1, "…and reverts cleanly")
	# rolls through the hooks
	var r := k.roll("1d20", {"actor": "a_hero", "kind": "attack", "dc": 12}, "Test attack")
	check(not r.is_empty() and r.kind == "roll" and r.result.parts.size() == 2, "a roll went through before_roll: attack part and shaken part: %s" % [r.result.parts])
	check(r.result.modifier == -1.0, "the parts total under the ruleset's policy (str +1, shaken -2)")
	check(r.result.outcome in ["success", "failure", "critical"], "after_roll classified it: " + str(r.result.outcome))
	check(st.encounter.log.size() == 1 and st.encounter.doc.rng.index == 1 and st.encounter.log[0].draw.index == 0, "the roll is in the document log and moved the stream")
	check(k.roll("1d20", {"actor": "a_hero", "forbidden": true}).is_empty() and k.last_veto.contains("forbid"), "a hook can veto a roll")
	# a whole action
	var outcome := rules.strike("a_hero", "a_gob")
	check(outcome.ok, "strike ran: " + str(outcome.get("why", "")))
	var gob_hp: float = Resources.get_record(st, "actor:a_gob", "sample", "hp").current
	if outcome.outcome == "failure":
		check(gob_hp == 8.0, "a miss leaves the goblin whole")
	else:
		check(gob_hp == maxf(0.0, 8.0 - float(outcome.damage)), "a hit took %s hp: %s left" % [outcome.damage, gob_hp])
	# expiry through the kernel
	k.commit(Effects.expire(st, {"kind": "turn_end", "of": "t_h"}), "End of turn")
	check(st.encounter.effects.is_empty() and st.encounter.actor("a_hero").derived.sample.defence.total == 13, "the effect expired and the defence recovered")
	# golden replay: the log alone rebuilds the document, derived included
	var fresh := EncounterState.new(Encounter.from_json(JsonDoc.stringify(JsonDoc.parse(start.replace('"modified": ""', '"modified": "x"')))))
	var fk := RulesKernel.new(fresh)
	SampleRules.new().install(fk)
	check(EventLog.replay(fresh, k.log.entries) == "", "replay accepts every entry")
	fk.rederive_all()
	check(JsonDoc.sans_modified(fresh.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "replay reproduces the document byte for byte")
	# derive is pure: deriving twice changes nothing
	changed.clear()
	k.rederive_all()
	check(changed.is_empty(), "re-deriving an unchanged actor emits nothing")
	# undo everything
	while k.log.can_undo():
		k.log.undo()
	check(JsonDoc.sans_modified(st.encounter.to_json()) == start, "undoing every step restores the start byte for byte")
	# hooks from a removed ruleset are gone
	k.unregister_ruleset("sample")
	check(not k.hooks.has("before_roll") and k.rulesets.is_empty(), "unregister drops the ruleset and its hooks")


func test_kernel_derive_budget() -> void:
	var st := _state()
	var k := RulesKernel.new(st)
	SampleRules.new().install(k)
	var events := []
	for i in 200:
		events.append({"t": "actor.add", "actor": {"id": "a_%d" % i, "ext": {"sample": {"level": 1 + i % 5, "stats": {"agi": i % 4, "str": i % 3}}}}})
		events.append({"t": "effect.apply", "effect": {"id": "e_%d" % i, "on": "actor:a_%d" % i, "plugin": "sample", "key": "shaken", "changes": [{"path": "defence", "mode": "add", "value": -1, "type": "status"}]}})
	k.commit(events, "Crowd")
	var t0 := Time.get_ticks_msec()
	k.rederive_all()
	var ms := Time.get_ticks_msec() - t0
	say.call("  200 actors with an effect each derived in %d ms" % ms)
	check(ms < (50 if not OS.has_feature("mobile") else 400), "deriving 200 actors stays within budget (%d ms)" % ms)
	t0 = Time.get_ticks_msec()
	k.commit([{"t": "actor.set", "id": "a_7", "changes": {"ext.sample.stats.agi": 9}}], "One")
	ms = Time.get_ticks_msec() - t0
	check(ms < 20 and st.encounter.actor("a_7").derived.sample.defence.total == 18, "a single change derives one actor (%d ms)" % ms)


## Random version-2 events against the invariants: every applied event
## inverts, a mirror fed the events matches, replay reproduces, derived
## never goes stale, no ruleset error escapes.
func test_rules_fuzz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	var st := _state()
	var k := RulesKernel.new(st)
	SampleRules.new().install(k)
	var failures := []
	k.ruleset_failed.connect(func(id: String, m: String) -> void: failures.append([id, m]))
	var sc := _scene()
	k.commit([{"t": "scene.add", "scene": sc}], "Scene")
	for i in 4:
		k.commit([{"t": "actor.add", "actor": {"id": "a_%d" % i, "ext": {"sample": {"level": 1 + i, "stats": {"agi": i, "str": 1}}}}},
			{"t": "token.add", "scene": sc.id, "token": Encounter.new_token("T%d" % i, Vector2(i, 0), {"id": "t_%d" % i, "actor": "a_%d" % i})},
			Resources.set_event("actor:a_%d" % i, "sample", "hp", Resources.pool(10, 10, "rest")),
			Resources.set_event("token:t_%d" % i, "sample", "stress", Resources.track(6, 0, 0, [], "rest"))], "Actor %d" % i)
	var start := JsonDoc.sans_modified(st.encounter.to_json())
	var start_seq := k.log.seq
	var start_depth := k.log.undo_depth()
	var kinds := {}
	var applied := 0
	var refused := 0
	for i in 500:
		var evs := _random_rules_events(rng, st)
		if evs.is_empty():
			continue
		var why := k.commit(evs, "fuzz %d" % i)
		if why != "":
			refused += 1
			continue
		applied += 1
		for ev in evs:
			kinds[ev.t] = int(kinds.get(ev.t, 0)) + 1
		if i % 50 == 0:
			var before := JsonDoc.stringify(st.encounter.doc.actors)
			k.rederive_all()
			check(JsonDoc.stringify(st.encounter.doc.actors) == before, "derived is never stale after commit %d" % i)
	check(applied > 300 and kinds.size() >= 9, "applied %d batches (%d refused), %d kinds: %s" % [applied, refused, kinds.size(), kinds.keys()])
	check(failures.is_empty(), "no ruleset failures: %s" % [failures])
	# replay reproduces
	var fresh := EncounterState.new(Encounter.from_json(JsonDoc.stringify(JsonDoc.parse(start.replace('"modified": ""', '"modified": "x"')))))
	var fk := RulesKernel.new(fresh)
	SampleRules.new().install(fk)
	check(EventLog.replay(fresh, k.log.since(start_seq - 1)) == "", "the fuzzed log replays")
	fk.rederive_all()
	check(JsonDoc.sans_modified(fresh.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "replay reproduces the fuzzed document")
	# undo everything back to the start
	while k.log.undo_depth() > start_depth:
		k.log.undo()
	check(JsonDoc.sans_modified(st.encounter.to_json()) == start, "undoing every fuzz step restores the start")


func _random_rules_events(rng: RandomNumberGenerator, st: EncounterState) -> Array:
	var actors := st.encounter.actors.keys()
	actors.sort()
	var a := str(actors[rng.randi_range(0, actors.size() - 1)])
	var t := "t_" + a.substr(2)
	var fx_ids := st.encounter.effects.keys()
	fx_ids.sort()
	match rng.randi_range(0, 11):
		0: return [{"t": "actor.set", "id": a, "changes": {"ext.sample.stats.agi": rng.randi_range(-2, 6)}}]
		1: return [{"t": "actor.set", "id": a, "changes": {"ext.sample.level": rng.randi_range(1, 10), "name": "N%d" % rng.randi_range(0, 99)}}]
		2:
			var ovs: Array = st.encounter.actor(a).overlays
			if ovs.is_empty():
				return [{"t": "actor.overlay.push", "id": a, "overlay": {"id": "o_%d" % rng.randi_range(0, 3), "patch": {"sample": {"stats": {"str": rng.randi_range(0, 5)}}}}}]
			return [{"t": "actor.overlay.pop", "id": a, "overlay_id": str(ovs[0].id)}]
		3, 4:
			var on := ("actor:" + a) if rng.randf() < 0.5 else ("token:" + t)
			return Effects.apply(st, {"id": "e_%d" % rng.randi_range(0, 30), "on": on, "plugin": "sample", "key": ["shaken", "haste", "mark"][rng.randi_range(0, 2)],
				"value": rng.randi_range(0, 3), "stack": Effects.STACK_MODES[rng.randi_range(0, 2)],
				"duration": {"kind": ["turn_end", "rounds", "scene", "until_cleared"][rng.randi_range(0, 3)], "of": t, "turns": rng.randi_range(1, 3), "rounds": rng.randi_range(1, 3)},
				"changes": [{"path": ["defence", "initiative", "hp_max"][rng.randi_range(0, 2)], "mode": ["add", "multiply", "override", "upgrade"][rng.randi_range(0, 3)], "value": rng.randi_range(-3, 3), "type": ["status", "item", "untyped"][rng.randi_range(0, 2)]}]})
		5:
			if fx_ids.is_empty():
				return []
			return Effects.remove(st, str(fx_ids[rng.randi_range(0, fx_ids.size() - 1)]))
		6: return Effects.expire(st, {"kind": ["turn_end", "round", "scene", "rest"][rng.randi_range(0, 3)], "of": t})
		7:
			var ev := Resources.spend(st, "actor:" + a, "sample", "hp", rng.randi_range(1, 4))
			return [ev] if not ev.is_empty() else Resources.refill(st, "rest")
		8:
			var ev := Resources.mark(st, "token:" + t, "sample", "stress", rng.randi_range(1, 3))
			return [ev] if not ev.is_empty() else [Resources.clear(st, "token:" + t, "sample", "stress", -1)]
		9: return [{"t": "ext.set", "scope": "encounter", "plugin": "sample", "changes": {"gm_pool": rng.randi_range(0, 12)}}]
		10: return [{"t": "log.add", "entry": {"id": "n_%d" % rng.randi_range(0, 1000000), "kind": "note", "text": "fuzz"}}]
		11:
			if fx_ids.is_empty():
				return []
			return [{"t": "effect.set", "id": str(fx_ids[rng.randi_range(0, fx_ids.size() - 1)]), "changes": {"value": rng.randi_range(0, 5)}}]
	return []
