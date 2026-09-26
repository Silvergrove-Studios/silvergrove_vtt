extends TestCase
## Phase 3: turns in both shapes, tracks, the clock, rests, prompts and
## open rolls as encounter records, the Table's turn panel drawing either
## shape, and a fuzz over both reference plugins.


func _state() -> EncounterState:
	var st := EncounterState.new(Encounter.create("Turns"))
	st.encounter.doc.rng = {"seed": 31337, "index": 0}
	st.encounter.doc.meta.created = "2026-09-20T00:00:00"
	return st


func _scene() -> Dictionary:
	return {"id": "s_1", "name": "G", "map": "", "map_path": "", "level": "ground", "overrides": {}, "fog": {"enabled": false, "explored": []}, "tokens": []}


## A kernel with a scene, three actors with tokens (agi 3, 1, 2) and the
## SampleRules fixture; returns [kernel, rules].
func _party() -> Array:
	var st := _state()
	var k := RulesKernel.new(st)
	var rules := SampleRules.new()
	rules.install(k)
	k.turns.register("sample", {"shape": "ordered", "name": "Sample initiative", "initiative": "initiative", "tie_break": "highest", "budgets": {"actions": 1, "reactions": 1}})
	var events := [{"t": "scene.add", "scene": _scene()}]
	var agis := {"a": 3, "b": 1, "c": 2}
	for id in ["a", "b", "c"]:
		events.append({"t": "actor.add", "actor": {"id": "a_" + id, "name": id.to_upper(), "owner": "pl_" + id, "ext": {"sample": {"level": 1, "stats": {"agi": agis[id], "str": 0, "wit": 0}}}}})
		events.append({"t": "token.add", "scene": "s_1", "token": Encounter.new_token(id.to_upper(), Vector2(agis[id], 0), {"id": "t_" + id, "actor": "a_" + id})})
	check(k.commit(events, "Party") == "", "party made")
	return [k, rules]


# ------------------------------------------------------------ document --

func test_turns_document_events() -> void:
	var st := _state()
	st.apply({"t": "scene.add", "scene": _scene()})
	var bad := {
		"bad strategy": {"t": "turns.set", "changes": {"strategy": "spiral"}},
		"focus not a string": {"t": "turns.set", "changes": {"focus": 3}},
		"counters not an object": {"t": "turns.set", "changes": {"counters": []}},
		"track without id": {"t": "track.add", "track": {"name": "x"}},
		"track.set missing": {"t": "track.set", "id": "zz", "changes": {}},
		"pending bad kind": {"t": "pending.open", "kind": "wishes", "record": {"id": "p1"}},
		"pending close missing": {"t": "pending.close", "kind": "prompts", "id": "nope"},
		"clock bad field": {"t": "clock.set", "changes": {"epoch": 1}},
		"clock not a number": {"t": "clock.set", "changes": {"day": "one"}},
	}
	for label in bad:
		check(st.validate(bad[label]) != "", label + " is refused")
	var start := JsonDoc.sans_modified(st.encounter.to_json())
	var events := [
		{"t": "turns.set", "changes": {"strategy": "focus", "focus": "gm", "running": true, "counters/token:t_1": {"actions": 2}, "history": ["gm"], "requests": [{"player": "pl_1", "ref": "token:t_1"}]}},
		{"t": "track.add", "track": Tracks.make("sample", "Doom", 3, "countdown", {"on": "roll_outcome", "outcomes": ["dark"]}, "gm", "Boom")},
		{"t": "pending.open", "kind": "prompts", "record": {"id": "p_1", "to": "pl_1", "form": {"title": "?"}, "default": {}, "deadline": 30}},
		{"t": "pending.set", "kind": "prompts", "id": "p_1", "changes": {"deadline": 10, "form/title": "!"}},
		{"t": "pending.open", "kind": "rolls", "record": {"id": "q_1", "spec": {"expr": "1d20"}, "contributions": []}},
		{"t": "clock.set", "changes": {"day": 3, "minute": 90}},
	]
	events[1].track.id = "k_1"
	var inverses := []
	for ev in events:
		check(st.validate(ev) == "", "%s validates: %s" % [ev.t, st.validate(ev)])
		var inv := st.apply(ev)
		check(not inv.is_empty(), "%s applies" % ev.t)
		inverses.append(inv)
	var t := st.encounter.turns
	check(t.strategy == "focus" and t.focus == "gm" and t.counters["token:t_1"].actions == 2 and t.requests.size() == 1, "turns v2 fields")
	check(st.current_turn_token() == "" and st.encounter.tracks.has("k_1") and st.encounter.pending.prompts.p_1.form.title == "!" and st.encounter.clock.day == 3, "tracks, pending, clock applied")
	st.apply({"t": "turns.set", "changes": {"focus": "token:t_1"}})
	check(st.current_turn_token() == "", "a focus on a token that is not on a scene is no turn")
	st.apply({"t": "turns.set", "changes": {"focus": "gm"}})
	for i in range(inverses.size() - 1, -1, -1):
		st.apply(inverses[i])
	check(JsonDoc.sans_modified(st.encounter.to_json()) == start, "inverses restore the start")
	var v1 := Encounter.load_file(example("chapel_ambush.encounter"))
	check(v1.turns.strategy == "ordered" and v1.tracks.is_empty() and v1.pending.prompts.is_empty() and v1.clock.session == 1, "old files gain the new blocks")


# --------------------------------------------------------------- ordered --

func test_ordered_turns() -> void:
	var parts := _party()
	var k: RulesKernel = parts[0]
	var fired := []
	for h in ["round_start", "round_end", "turn_start", "turn_end"]:
		k.hooks.on(h, func(p: Dictionary) -> Dictionary:
			fired.append([h, str(p.get("ref", p.get("round", "")))])
			if h == "turn_start" and p.ref == "token:t_c":
				p.events.append({"t": "log.add", "entry": {"id": "n_c_%d" % fired.size(), "kind": "note", "text": "C is up"}})
			return p, "test")
	check(k.turns.start("s_1", "sample") == "", "start")
	var t := k.state.encounter.turns
	check(t.strategy == "ordered" and t.plugin == "sample" and t.order == ["t_a", "t_c", "t_b"], "ordered by derived initiative, highest first: %s" % [t.order])
	check(t.data.labels.t_a == "3" and t.counters["token:t_a"].actions == 1, "labels and budgets")
	check(fired == [["round_start", "1"], ["turn_start", "token:t_a"]], "round 1 and A's turn started: %s" % [fired])
	check(k.log.undo_label() == "Start turns", "one undo step")
	# an effect until A's turn ends, and a counter spent
	k.commit(Effects.apply(k.state, {"id": "e_a", "on": "token:t_a", "plugin": "sample", "key": "shaken", "duration": {"kind": "turn_end", "of": "t_a", "turns": 1}}), "Shaken")
	check(k.turns.consume("token:t_a", "actions") == "" and k.turns.counters("token:t_a").actions == 0 and k.turns.consume("token:t_a", "actions") != "", "counters spend and run out")
	fired.clear()
	check(k.turns.next() == "", "next")
	check(fired == [["turn_end", "token:t_a"], ["turn_start", "token:t_c"]], "A ended, C started: %s" % [fired])
	check(k.state.encounter.effects.is_empty(), "the effect tied to A's turn end expired")
	check(k.state.encounter.log.size() == 1 and k.state.encounter.log[0].text == "C is up", "a handler's events were committed")
	check(k.state.encounter.turns.turn == 1 and k.state.current_turn_token() == "t_c", "the current turn")
	fired.clear()
	k.turns.next()
	k.turns.next()
	check(fired.slice(0, 4) == [["turn_end", "token:t_c"], ["turn_start", "token:t_b"], ["turn_end", "token:t_b"], ["round_end", "1"]] and fired[4] == ["round_start", "2"] and fired[5] == ["turn_start", "token:t_a"], "wrapping ends the round and starts the next: %s" % [fired])
	check(k.state.encounter.turns.round == 2 and k.turns.counters("token:t_a").actions == 1, "round 2; A's budget is back")
	check(k.turns.previous() == "" and k.state.encounter.turns.turn == 2 and k.state.encounter.turns.round == 1, "previous steps back quietly")
	k.turns.next()
	# a veto in turn_end undoes the whole step
	k.hooks.on("turn_end", func(p: Dictionary) -> Dictionary: p.veto = "not yet"; return p, "veto")
	var before := k.state.encounter.to_json()
	check(k.turns.next().contains("not yet") and k.state.encounter.to_json() == before, "a vetoed step leaves nothing behind")
	k.hooks.off("veto")
	k.commit(Effects.apply(k.state, {"id": "e_r", "on": "token:t_a", "plugin": "sample", "key": "raging", "duration": {"kind": "rounds", "rounds": 10}}), "Rage")
	check(k.turns.stop() == "" and not k.turns.running(), "stop")
	check(not k.state.encounter.effects.has("e_r"), "what lasted rounds ends with the fight (a barbarian stayed Raging after one)")
	check(k.turns.set_focus("gm") != "", "focus calls are refused in the ordered shape")
	# the list strategy without a plugin keeps the DM's order
	k.commit([{"t": "turns.set", "changes": {"order": ["t_b", "t_a", "t_c"]}}], "Reorder")
	check(k.turns.start("s_1", "list") == "" and k.state.encounter.turns.order == ["t_b", "t_a", "t_c"] and k.state.encounter.turns.plugin == "", "the list strategy keeps the order as arranged")


func test_order_helpers_and_groups() -> void:
	var parts := _party()
	var k: RulesKernel = parts[0]
	var st := k.state
	# two goblins join the party's scene
	k.commit([{"t": "actor.add", "actor": {"id": "a_g1", "name": "Goblin 1", "ext": {"sample": {"level": 1, "stats": {"agi": 0, "str": 0, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_g2", "name": "Goblin 2", "ext": {"sample": {"level": 1, "stats": {"agi": 0, "str": 0, "wit": 0}}}}},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Goblin 1", Vector2(5, 1), {"id": "t_g1", "actor": "a_g1"})},
		{"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Goblin 2", Vector2(6, 1), {"id": "t_g2", "actor": "a_g2"})}], "Goblins")
	check(k.turns.start("s_1", "sample") == "" and st.encounter.turns.order == ["t_a", "t_c", "t_b", "t_g1", "t_g2"], "five in the order: %s" % [st.encounter.turns.order])
	# reorder keeps the current participant current; insert and remove
	k.turns.next()
	check(st.current_turn_token() == "t_c", "C is up")
	check(k.turns.reorder(["t_b", "t_a", "t_c", "t_g1", "t_g2"]) == "" and st.encounter.turns.turn == 2 and st.current_turn_token() == "t_c", "delaying A past C keeps C's turn current: turn %d" % st.encounter.turns.turn)
	check(k.turns.remove("t_b") == "" and st.encounter.turns.order == ["t_a", "t_c", "t_g1", "t_g2"] and st.current_turn_token() == "t_c", "removed B")
	check(k.turns.remove("t_b") != "", "not twice")
	check(k.turns.insert("t_b", 0) == "" and st.encounter.turns.order[0] == "t_b" and st.current_turn_token() == "t_c", "B back at the front; C still up")
	check(k.turns.insert("t_a") == "" and st.encounter.turns.order[-1] == "t_a", "insert without an index goes last")
	check(k.turns.reorder(["t_x", "t_a", "t_a"]) == "" and st.encounter.turns.order == ["t_x", "t_a"] and st.encounter.turns.turn == 1, "duplicates fold; a current entry that vanished leaves the index clamped")
	k.turns.reorder(["t_a", "t_c", "t_b", "t_g1", "t_g2"])
	# a group: one slot, each member's own turn
	var fired := []
	k.hooks.on("turn_start", func(p: Dictionary) -> Dictionary: fired.append(["start", p.ref, str(p.get("group", ""))]); return p, "test")
	k.hooks.on("turn_end", func(p: Dictionary) -> Dictionary: fired.append(["end", p.ref, str(p.get("group", ""))]); return p, "test")
	check(k.turns.group("gobs", ["t_g1", "t_g2"], "The goblins") == "" and st.encounter.turns.order == ["t_a", "t_c", "t_b", "group:gobs"], "the goblins fold into one slot: %s" % [st.encounter.turns.order])
	check(st.encounter.turns.data.groups.gobs.tokens == ["t_g1", "t_g2"] and st.encounter.turns.data.labels["group:gobs"] == "The goblins", "kept in the turns data with a label")
	check(k.turns.group("gobs", ["t_a"]) != "" and k.turns.group("", ["t_a"]) != "", "a group needs a new id and members")
	k.commit([{"t": "turns.set", "changes": {"turn": 2}}], "To B")
	fired.clear()
	check(k.turns.next() == "" and st.current_turn_tokens() == ["t_g1", "t_g2"] and st.current_turn_token() == "t_g1", "the goblins' slot: both are up")
	check(fired == [["end", "token:t_b", ""], ["start", "token:t_g1", "gobs"], ["start", "token:t_g2", "gobs"]], "each member got its own turn_start, tagged with the group: %s" % [fired])
	check(k.turns.counters("token:t_g1").actions == 1 and k.turns.counters("token:t_g2").actions == 1, "budgets per member")
	k.commit(Effects.apply(st, {"id": "e_g2", "on": "token:t_g2", "plugin": "sample", "key": "shaken", "duration": {"kind": "turn_end", "of": "t_g2", "turns": 1}}), "Shaken")
	check(st.allowed({"t": "token.set", "scene": "s_1", "id": "t_g2", "changes": {"pos": [1, 1]}}, "pl_a") == false, "a player who owns neither may not move a goblin")
	check(st.highlighted_token_ids() == ["t_g1", "t_g2"], "both goblins are marked as up")
	fired.clear()
	check(k.turns.next() == "" and fired == [["end", "token:t_g1", "gobs"], ["end", "token:t_g2", "gobs"], ["start", "token:t_a", ""]] and st.encounter.turns.round == 2, "both ended, the round wrapped: %s" % [fired])
	check(st.encounter.effects.is_empty(), "the effect until goblin 2's turn end expired")
	# undo restores the order and the group
	var before := st.encounter.to_json()
	check(k.turns.ungroup("gobs") == "" and st.encounter.turns.order == ["t_a", "t_c", "t_b", "t_g1", "t_g2"] and not st.encounter.turns.data.groups.has("gobs"), "ungroup puts the members back where the slot was")
	k.log.undo()
	k.log.undo()
	check(st.encounter.to_json() == before, "undo restores the group")
	# a restart keeps the group, at the first member's place
	check(k.turns.start("s_1", "sample") == "" and st.encounter.turns.order == ["t_a", "t_c", "t_b", "group:gobs"] and st.encounter.turns.data.groups.has("gobs"), "restarting keeps the group: %s" % [st.encounter.turns.order])
	check(k.turns.ungroup("nope") != "", "no such group")
	k.hooks.off("test")


# ----------------------------------------------------------------- focus --

func test_focus_turns() -> void:
	var parts := _party()
	var k: RulesKernel = parts[0]
	k.turns.register("spot", {"shape": "focus", "name": "Spotlight"})
	var fired := []
	k.hooks.on("focus_changed", func(p: Dictionary) -> Dictionary:
		fired.append([p.from, p.to, p.by])
		if p.to == "token:t_b" and p.by != "gm":
			p.veto = "only the GM may give B the focus"
		return p, "test")
	k.hooks.on("turn_start", func(p: Dictionary) -> Dictionary: fired.append(["start", p.ref]); return p, "test")
	k.hooks.on("turn_end", func(p: Dictionary) -> Dictionary: fired.append(["end", p.ref]); return p, "test")
	check(k.turns.start("s_1", "spot") == "", "start")
	var t := k.state.encounter.turns
	check(t.strategy == "focus" and t.focus == "gm" and t.order.is_empty() and t.history == ["gm"], "the GM holds the focus; there is no order")
	check(fired == [["", "gm", "gm"]], "focus_changed fired for the start: %s" % [fired])
	check(k.turns.request_focus("pl_a", "token:t_a") == "" and k.turns.request_focus("pl_a", "token:t_a") == "" and k.state.encounter.turns.requests.size() == 1, "a request, once")
	fired.clear()
	check(k.turns.set_focus("token:t_a", "gm") == "", "granted")
	t = k.state.encounter.turns
	check(t.focus == "token:t_a" and t.requests.is_empty() and t.history == ["gm", "token:t_a"] and k.state.current_turn_token() == "t_a", "the focus moved; the request cleared; A is up")
	check(fired == [["gm", "token:t_a", "gm"], ["start", "token:t_a"]], "hooks: focus_changed then A's turn_start: %s" % [fired])
	k.commit(Effects.apply(k.state, {"id": "e_a", "on": "token:t_a", "plugin": "sample", "key": "shaken", "duration": {"kind": "turn_end", "of": "t_a", "turns": 1}}), "Shaken")
	fired.clear()
	var before := k.state.encounter.to_json()
	check(k.turns.set_focus("token:t_b", "pl_b").contains("only the GM") and k.state.encounter.to_json() == before, "a vetoed focus change leaves nothing behind (A's effect too)")
	check(k.turns.set_focus("token:t_b", "gm") == "", "the GM may")
	check(fired.has(["end", "token:t_a"]) and fired.has(["start", "token:t_b"]) and k.state.encounter.effects.is_empty(), "A's turn ended (its effect expired) and B's began: %s" % [fired])
	check(k.turns.set_focus("gm") == "" and k.state.current_turn_token() == "" and k.state.encounter.turns.history.size() == 4, "back to the GM")
	check(k.turns.next().contains("no next"), "no next in the focus shape")
	check(k.turns.set_focus("token:t_zz") != "", "an unknown holder is refused")
	check(k.turns.deny_focus("token:t_a") == "", "deny is fine on nothing")
	# the effect duration works for actor refs too
	k.turns.set_focus("actor:a_c")
	k.commit(Effects.apply(k.state, {"id": "e_c", "on": "actor:a_c", "plugin": "sample", "key": "mark", "duration": {"kind": "turn_end", "of": "actor:a_c", "turns": 1}}), "Mark")
	k.turns.set_focus("gm")
	check(k.state.encounter.effects.is_empty(), "an effect until an actor holder's turn ends expires when the focus leaves")


# ----------------------------------------------------- tracks and clock --

func test_tracks_clock_and_rest() -> void:
	var parts := _party()
	var k: RulesKernel = parts[0]
	var doom := Tracks.make("sample", "Doom", 3, "countdown", {"on": "roll_outcome", "outcomes": ["failure"], "amount": 1}, "gm", "It happens")
	var rise := Tracks.make("sample", "Rise", 4, "clock", {"on": "roll"}, "all")
	var long := Tracks.make("sample", "Journey", 2, "countdown", {"on": "rest"})
	rise.linked = doom.id
	k.commit([Tracks.add_event(doom), Tracks.add_event(rise), Tracks.add_event(long)], "Tracks")
	check(doom.value == 3 and doom.direction == "down" and rise.value == 0 and rise.direction == "up", "a countdown starts full, a clock empty")
	var done := []
	k.hooks.on("track_done", func(p: Dictionary) -> Dictionary: done.append(p.track); return p, "test")
	var r := k.roll("1d20", {"actor": "a_a", "dc": 30}, "Fail")   # certainly a failure
	check(r.result.outcome == "failure", "a failing roll")
	check(k.state.encounter.tracks[rise.id].value == 1, "every roll ticks Rise")
	# Rise is linked to Doom, so Doom moved for the outcome and for the link: one event, two steps
	check(k.state.encounter.tracks[doom.id].value == 1, "linked tracks move together, summed into one change: %s" % [k.state.encounter.tracks[doom.id].value])
	k.roll("1d20", {"actor": "a_a", "dc": 30}, "Fail again")
	check(k.state.encounter.tracks[doom.id].done and done == [doom.id], "Doom finished and track_done fired once")
	check(Tracks.advance(k.state, doom.id, 1).is_empty() and Tracks.advance(k.state, doom.id, -1)[0].changes.value == 1, "a done track can only move back")
	check(Tracks.advance(k.state, "nope").is_empty(), "unknown tracks move nothing")
	# the clock
	var timed := []
	k.hooks.on("time_advanced", func(p: Dictionary) -> Dictionary: timed.append([p.minutes, p.day]); return p, "test")
	k.commit(Effects.apply(k.state, {"id": "e_t", "on": "actor:a_a", "plugin": "sample", "key": "light", "duration": {"kind": "time", "until": 60}}), "Light")
	check(k.clock.advance(30) == "" and k.state.encounter.clock.minute == 30 and k.state.encounter.effects.has("e_t"), "half an hour: the light burns")
	check(k.clock.advance(24 * 60) == "" and k.state.encounter.clock.day == 2 and k.state.encounter.clock.minute == 30 and not k.state.encounter.effects.has("e_t"), "a day later: day 2, the light is out")
	check(timed == [[30.0, 1], [1440.0, 2]], "time_advanced fired: %s" % [timed])
	check(k.clock.advance(0) != "", "time does not stand still")
	# rest
	k.commit([Resources.set_event("actor:a_a", "sample", "hp", Resources.pool(2, 9, "rest")), Resources.set_event("actor:a_a", "sample", "focus", Resources.pool(0, 3, "session"))], "Pools")
	k.commit(Effects.apply(k.state, {"id": "e_r", "on": "actor:a_a", "plugin": "sample", "key": "tired", "duration": {"kind": "rest"}}), "Tired")
	var rested := []
	k.hooks.on("rest", func(p: Dictionary) -> Dictionary: rested.append(p.kind); p.events.append({"t": "log.add", "entry": {"id": "n_rest", "kind": "note", "text": "zzz"}}); return p, "test")
	check(k.rest("rest") == "", "rest")
	check(Resources.get_record(k.state, "actor:a_a", "sample", "hp").current == 9 and not k.state.encounter.effects.has("e_r") and k.state.encounter.tracks[long.id].value == 1, "a rest refills, expires and ticks rest tracks")
	check(rested == ["rest"] and k.state.encounter.log[-1].text == "zzz" and k.state.encounter.clock.rests == 1, "the rest hook ran and its events landed; the clock counted")
	check(k.log.undo_label() == "Rest", "one undo step")
	check(Resources.get_record(k.state, "actor:a_a", "sample", "focus").current == 0, "session pools wait for a session")
	check(k.clock.next_session() == "" and k.state.encounter.clock.session == 2 and Resources.get_record(k.state, "actor:a_a", "sample", "focus").current == 3, "a new session refills them")
	k.commit(Effects.apply(k.state, {"id": "e_s", "on": "actor:a_a", "plugin": "sample", "key": "blessed", "duration": {"kind": "scene"}}), "Blessed")
	check(k.clock.next_scene() == "" and k.state.encounter.clock.scene == 2 and not k.state.encounter.effects.has("e_s"), "a new scene ends scene effects")


# ---------------------------------------------------------------- pending --

func test_pending_prompts_and_rolls() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var st := _state()
	var k := RulesKernel.new(st)
	var host := PluginHost.new(k)
	check(host.load_dir("res://tests/plugins/sample.ordered") == "", "sample.ordered loads")
	k.commit([{"t": "actor.add", "actor": {"id": "a_h", "owner": "pl_1", "ext": {"sample.ordered": {"level": 3, "stats": {"agi": 5, "str": 3, "wit": 0}}}}},
		{"t": "actor.add", "actor": {"id": "a_g", "owner": "pl_2", "name": "Gob", "ext": {"sample.ordered": {"level": 1, "stats": {"agi": -5, "str": 0, "wit": 0}, "armour": 2}}}}], "Actors")
	host.dispatch("sample.ordered", "setup", {"actor": "a_h"})
	host.dispatch("sample.ordered", "setup", {"actor": "a_g"})
	var finished := []
	var opened := []
	k.pending.opened.connect(func(kind: String, rec: Dictionary) -> void: opened.append([kind, str(rec.get("to", ""))]))
	# a strike against a defence of 5: a hit unless the d20 shows 1; the goblin has armour, so its owner is asked
	var pc := host.dispatch("sample.ordered", "strike", {"actor": "a_h", "target": "a_g"})
	k.pending.drive(pc, "sample.ordered", func(c: PluginHost.PluginCall) -> void: finished.append(c.status))
	if pc.status == PluginHost.PluginCall.OK:
		check(finished == ["ok"], "a miss finishes at once")
		return
	check(pc.status == PluginHost.PluginCall.PENDING and finished.is_empty(), "the strike is waiting")
	var prompts := k.pending.prompts()
	check(prompts.size() == 1 and opened == [["prompts", "pl_2"]], "a prompt record was opened for the goblin's owner: %s" % [prompts])
	var pid := str(prompts.keys()[0])
	var rec: Dictionary = prompts[pid]
	check(rec.to == "pl_2" and rec.by == "sample.ordered" and rec.form.title == "Spend armour?" and rec.deadline == 30 and rec.default.spend == false and rec.context.action == "strike", "the record carries the form, the default, the deadline and who asked: %s" % [rec])
	# it survives a save and a load — a reconnecting client is shown it again
	var reloaded := Encounter.from_json(st.encounter.to_json())
	check(reloaded.pending.prompts.has(pid) and reloaded.pending.prompts[pid].form.title == "Spend armour?", "the prompt is in the document")
	check(k.pending.answer(pid, {"spend": true}, "pl_1").contains("for pl_2"), "the wrong player may not answer")
	check(k.pending.answer("p_none", {}) != "", "unknown prompts are refused")
	var hp_before: float = Resources.get_record(st, "actor:a_g", "sample.ordered", "hp").current
	check(k.pending.answer(pid, {"spend": true}, "pl_2") == "", "the right player answers")
	check(pc.status == PluginHost.PluginCall.OK and finished == ["ok"] and k.pending.prompts().is_empty(), "the action resumed and finished: %s %s" % [pc.status, pc.error])
	check(Resources.get_record(st, "actor:a_g", "sample.ordered", "armour").marked == 1 and Resources.get_record(st, "actor:a_g", "sample.ordered", "hp").current == maxf(0.0, hp_before - float(pc.value.damage)), "the answer took effect: armour spent, damage reduced")
	# deadlines: the default answers
	var pc2 := host.dispatch("sample.ordered", "strike", {"actor": "a_h", "target": "a_g"})
	k.pending.drive(pc2, "sample.ordered")
	if pc2.status == PluginHost.PluginCall.PENDING:
		k.pending.tick(29.0)
		check(pc2.status == PluginHost.PluginCall.PENDING, "still waiting at 29 s")
		k.pending.tick(2.0)
		check(pc2.status == PluginHost.PluginCall.OK and Resources.get_record(st, "actor:a_g", "sample.ordered", "armour").marked == 1, "at the deadline the default (no) answered")
	# orphans: a prompt with no continuation (a restarted Table) is closed with its default
	k.commit([{"t": "pending.open", "kind": "prompts", "record": {"id": "p_old", "to": "pl_2", "form": {}, "default": {"x": 1}, "deadline": 5}}], "Old")
	k.pending.close_orphans()
	check(k.pending.prompts().is_empty(), "orphans closed")
	# open rolls
	var qid := k.pending.open_roll({"expr": "1d20", "parts": [{"label": "skill", "value": 2}]}, {"actor": "a_h", "kind": "check", "dc": 10}, "test", "Sneak", ["pl_1", "pl_2"], 60)
	check(qid != "" and k.pending.rolls().has(qid), "an open roll is a record")
	check(k.pending.contribute(qid, "pl_3", "help", "1d6").contains("not open"), "only those it is open to")
	check(k.pending.contribute(qid, "pl_2", "help", "1dx") != "", "a bad expression is refused")
	check(k.pending.contribute(qid, "pl_2", "help", "1d6") == "" and k.pending.contribute(qid, "pl_1", "help", "1d4") != "", "one contribution per name")
	check(Encounter.from_json(st.encounter.to_json()).pending.rolls[qid].contributions.size() == 1, "contributions are in the document")
	var entry := k.pending.resolve(qid)
	check(not entry.is_empty() and entry.result.groups.has("help") and entry.result.total == entry.result.groups.main.total + entry.result.groups.help.total + 2, "resolved with the help die and the parts: %s" % [entry.result.total])
	check(k.pending.rolls().is_empty() and k.pending.resolve(qid).is_empty(), "closed")


# ------------------------------------------------------------------ table --

func test_table_turn_panel_both_shapes() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var ctx := TableContext.new()
	ctx.app = App.new("user://test_prefs_turns.json")
	ctx.plugin_dirs = ["res://tests/plugins"]
	var e := Encounter.load_file(example("chapel_ambush.encounter"))
	ctx.set_encounter(e)
	ctx.state.resolve_maps()
	check(ctx.kernel != null and ctx.host != null and ctx.host.plugins.has("sample.focus") and ctx.host.plugins.has("sample.ordered"), "the Table loaded the plugins from its dirs: %s" % [ctx.plugin_log])
	check(ctx.kernel.turns.strategies.has("sample.focus") and ctx.kernel.turns.strategies["sample.focus"].shape == "focus", "the focus strategy is on offer")
	var panel := TurnsPanel.new(ctx)
	root.add_child(panel)
	panel.bind()
	var names := []
	for i in panel.system_select.item_count:
		names.append(panel.system_select.get_item_metadata(i))
	check(names[0] == "list" and names.has("sample.focus") and names.has("sample.ordered"), "the strategy menu lists them, the list first: %s" % [names])
	ctx.commands.set_turn_mode("ordered")
	check(ctx.commands.run({"t": "turns.set", "changes": {"system": "sample.focus"}}) == "" and ctx.commands.start_turns(ctx.scene_id) == "", "start with the focus strategy")
	panel.refresh()
	check(ctx.encounter().turns.strategy == "focus" and panel._round.text == "Focus: the GM" and panel._next.text == "Give focus", "the panel draws the focus shape from data")
	var rows := []
	var it := panel.list.get_root().get_first_child()
	while it != null:
		rows.append(it.get_text(0))
		it = it.get_next()
	check(rows[0].contains("The GM") and rows.size() == 1 + ctx.state.tokens(ctx.scene_id).size(), "one row for the GM and one per token: %s" % [rows])
	# give the focus to the second row (a token) through the panel
	var second := panel.list.get_root().get_first_child().get_next()
	var second_ref := str(second.get_metadata(1))
	var second_token := str(second.get_metadata(0))
	second.select(0)
	panel._give_focus()
	panel.refresh()
	check(ctx.encounter().turns.focus == second_ref and panel._round.text.begins_with("Focus: ") and not panel._round.text.ends_with("the GM"), "the focus moved to the token and the panel says so: " + panel._round.text)
	check(ctx.state.current_turn_token() == second_token, "the holder's token is up (gold ring, player may move it)")
	# and the ordered shape still draws
	ctx.commands.run({"t": "turns.set", "changes": {"system": "sample.ordered"}})
	check(ctx.commands.start_turns(ctx.scene_id) == "", "start the ordered strategy")
	panel.refresh()
	check(ctx.encounter().turns.strategy == "ordered" and panel._round.text == "Round 1" and panel._next.text == "Next turn", "…and the panel draws the ordered shape")
	check(ctx.commands.next_turn() == "" and ctx.encounter().turns.turn == 1, "Next steps through the runner")
	# a group draws as one row with its members under it
	var gobs := []
	for tk in ctx.state.tokens(ctx.scene_id):
		if str(tk.get("name", "")).begins_with("Goblin"):
			gobs.append(str(tk.id))
	check(gobs.size() >= 2 and ctx.kernel.turns.group("pack", gobs, "The goblin pack") == "", "the goblins grouped")
	panel.refresh()
	var group_row: TreeItem = null
	it = panel.list.get_root().get_first_child()
	while it != null:
		if str(it.get_metadata(0)) == "group:pack":
			group_row = it
		it = it.get_next()
	check(group_row != null and group_row.get_text(0).contains("The goblin pack") and group_row.get_text(1) == "%d together" % gobs.size() and group_row.get_child_count() == gobs.size(), "one row for the pack, a child per goblin")
	panel.queue_free()
	await tree.process_frame


# ------------------------------------------------------------------- fuzz --

## Both reference plugins on one kernel, driven by random operations:
## actions with answers, turns in whichever shape is running, rests, the
## clock, tracks. Invariants: replay reproduces, undo-all restores, no
## plugin failure escapes, no prompt is left dangling.
func test_both_plugins_fuzz() -> void:
	if not PluginHost.available():
		skip("no Lua runtime in this build")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var st := _state()
	var k := RulesKernel.new(st)
	var host := PluginHost.new(k)
	check(host.load_dir("res://tests/plugins/sample.ordered") == "" and host.load_dir("res://tests/plugins/sample.focus") == "", "both load")
	var failures := []
	host.plugin_failed.connect(func(id: String, where: String, msg: String) -> void: failures.append([id, where, msg]))
	var events := [{"t": "scene.add", "scene": _scene()}]
	for i in 3:
		events.append({"t": "actor.add", "actor": {"id": "a_%d" % i, "name": "P%d" % i, "owner": "pl_%d" % i, "ext": {
			"sample.ordered": {"level": 1 + i, "stats": {"agi": i, "str": 1, "wit": 0}, "armour": 1},
			"sample.focus": {"traits": {"nerve": 1, "grace": i, "wit": 0}, "hand": ["dash"], "vault": ["rally", "trick"]}}}})
		events.append({"t": "token.add", "scene": "s_1", "token": Encounter.new_token("P%d" % i, Vector2(i, 0), {"id": "t_%d" % i, "actor": "a_%d" % i})})
	events.append({"t": "actor.add", "actor": {"id": "a_gob", "name": "Gob", "ext": {"sample.ordered": {"level": 1, "stats": {"agi": 0, "str": 1, "wit": 0}}, "sample.focus": {"traits": {"nerve": 1}, "adversary": true}}}})
	events.append({"t": "token.add", "scene": "s_1", "token": Encounter.new_token("Gob", Vector2(5, 0), {"id": "t_gob", "actor": "a_gob"})})
	check(k.commit(events, "Party") == "", "party")
	for a in ["a_0", "a_1", "a_2", "a_gob"]:
		host.dispatch("sample.ordered", "setup", {"actor": a})
		host.dispatch("sample.focus", "setup", {"actor": a})
	var start := JsonDoc.sans_modified(st.encounter.to_json())
	var start_seq := k.log.seq
	var start_depth := k.log.undo_depth()
	var ops := {}
	var refused := 0
	for i in 400:
		var op := _fuzz_op(rng, k, host)
		ops[op[0]] = int(ops.get(op[0], 0)) + 1
		if op[1] != "":
			refused += 1
		if i % 40 == 0:
			var before := JsonDoc.stringify(st.encounter.doc.actors)
			k.rederive_all()
			check(JsonDoc.stringify(st.encounter.doc.actors) == before, "derived is never stale after op %d" % i)
	check(ops.size() >= 10, "operations covered: %s (%d refused)" % [ops, refused])
	# an action may refuse for a rules reason (too much strain to recall);
	# what must never happen is a derive or hook failure, or a Lua runtime error
	var real := failures.filter(func(f: Array) -> bool:
		return not str(f[1]).begins_with("action") or str(f[2]).contains("attempt to") or str(f[2]).contains("nil"))
	check(real.is_empty(), "no plugin failures beyond rules refusals: %s" % [real.slice(0, 5)])
	check(k.pending.prompts().is_empty(), "no prompt left dangling")
	var fresh := EncounterState.new(Encounter.from_json(JsonDoc.stringify(JsonDoc.parse(start.replace('"modified": ""', '"modified": "x"')))))
	var fk := RulesKernel.new(fresh)
	var fh := PluginHost.new(fk)
	fh.load_dir("res://tests/plugins/sample.ordered")
	fh.load_dir("res://tests/plugins/sample.focus")
	check(EventLog.replay(fresh, k.log.since(start_seq - 1)) == "", "the fuzzed log replays")
	fk.rederive_all()
	check(JsonDoc.sans_modified(fresh.encounter.to_json()) == JsonDoc.sans_modified(st.encounter.to_json()), "replay reproduces the document")
	while k.log.undo_depth() > start_depth:
		k.log.undo()
	check(JsonDoc.sans_modified(st.encounter.to_json()) == start, "undoing every step restores the start")


## One random operation; [name, why-refused].
func _fuzz_op(rng: RandomNumberGenerator, k: RulesKernel, host: PluginHost) -> Array:
	var actors := ["a_0", "a_1", "a_2", "a_gob"]
	var a: String = actors[rng.randi_range(0, 2)]
	var target: String = actors[rng.randi_range(0, 3)]
	var turns := k.state.encounter.turns
	var answers := [{"spend": rng.randf() < 0.5}, {"spend": false}, {"spend": true}]
	match rng.randi_range(0, 13):
		0:
			if not turns.running or turns.strategy != "ordered":
				return ["start_ordered", k.turns.start("s_1", "sample.ordered")]
			return ["next", k.turns.next()]
		1:
			if not turns.running or turns.strategy != "focus":
				return ["start_focus", k.turns.start("s_1", "sample.focus")]
			var holders := ["gm", "token:t_0", "token:t_1", "token:t_2", "actor:a_gob"]
			return ["focus", k.turns.set_focus(holders[rng.randi_range(0, 4)], "gm")]
		2:
			return ["request", k.turns.request_focus("pl_%s" % a.substr(2), "token:t_" + a.substr(2))]
		3, 4:
			var pc := host.dispatch("sample.ordered", "strike", {"actor": a, "target": target, "token": "t_" + a.substr(2)})
			k.pending.drive(pc, "sample.ordered")
			var n := 0
			while not k.pending.prompts().is_empty() and n < 3:
				k.pending.answer(str(k.pending.prompts().keys()[0]), answers[rng.randi_range(0, 2)])
				n += 1
			return ["strike", pc.error]
		5:
			var pc := host.dispatch("sample.focus", "act", {"actor": a, "trait": ["nerve", "grace", "wit"][rng.randi_range(0, 2)], "dc": rng.randi_range(5, 15),
				"help": {"by": "pl_9", "expr": "1d6"} if rng.randf() < 0.3 else null})
			return ["act", pc.error]
		6:
			var pc := host.dispatch("sample.focus", "damage", {"target": target, "amount": rng.randi_range(1, 10)})
			k.pending.drive(pc, "sample.focus")
			while not k.pending.prompts().is_empty():
				k.pending.tick(30.0)
			return ["damage", pc.error]
		7:
			var d: Dictionary = k.state.encounter.actor(a).ext["sample.focus"]
			var hand: Array = d.get("hand", [])
			var vault: Array = d.get("vault", [])
			if rng.randf() < 0.5 and not hand.is_empty():
				return ["play", host.dispatch("sample.focus", "play", {"actor": a, "card": hand[rng.randi_range(0, hand.size() - 1)], "target": target}).error]
			if not vault.is_empty() and hand.size() < 3:
				var pc := host.dispatch("sample.focus", "recall", {"actor": a, "card": vault[rng.randi_range(0, vault.size() - 1)], "free": rng.randf() < 0.5})
				return ["recall", "" if pc.status == PluginHost.PluginCall.OK else pc.error]
			return ["cards", ""]
		8:
			return ["rest", k.rest(["rest", "long_rest"][rng.randi_range(0, 1)])]
		9:
			return ["clock", k.clock.advance(rng.randi_range(1, 900))]
		10:
			var pc := host.dispatch("sample.focus", "countdown", {"actor": a, "steps": rng.randi_range(1, 3)})
			return ["countdown", pc.error]
		11:
			var pc := host.dispatch("sample.ordered", "condition", {"key": ["shaken", "prone", "blessed"][rng.randi_range(0, 2)], "target": "actor:" + target, "value": rng.randi_range(1, 3)})
			return ["condition", pc.error]
		12:
			if turns.running:
				return ["stop", k.turns.stop()]
			return ["session", k.clock.next_session()]
		13:
			var qid := k.pending.open_roll("1d20", {"actor": a, "kind": "attack", "dc": 10}, "fuzz", "Open", "all", 10)
			k.pending.contribute(qid, "pl_1", "help", "1d6")
			return ["open_roll", "" if not k.pending.resolve(qid).is_empty() else k.last_veto]
	return ["none", ""]
